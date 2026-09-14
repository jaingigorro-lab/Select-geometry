using System;
using System.Collections.Generic;
using System.Globalization;
using Autodesk.AutoCAD.Colors;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.Geometry;

namespace ConductosPlugin
{
    /// <summary>
    /// Everything that touches the AutoCAD database: axis styling, elbow block
    /// creation/lookup, block insertion with attributes, and curve offsetting.
    /// Every method here is strongly typed against the real AutoCAD .NET API
    /// (Autodesk.AutoCAD.DatabaseServices), so there is no VARIANT coercion, no
    /// missing DXF subclass markers, no ambiguous point-list-vs-variant guessing -
    /// the compiler already caught anything of that shape before this ever runs.
    /// </summary>
    internal static class DrawingUtil
    {
        public const double RadiusFactor = 1.5; // codo circular: radio = este factor x diametro (SMACNA)
        public const double RectElbowLegFactor = 1.0; // codo rectangular: longitud de pata = este factor x ancho

        public static string ElbowBlockName(string tipo, double dim, double angDeg) =>
            $"CODO_{(tipo == "Circular" ? "CIRC" : "RECT")}_D{NumTag(dim)}_A{NumTag(angDeg)}";

        private static string NumTag(double x) =>
            x.ToString("0.0", CultureInfo.InvariantCulture).Replace('.', '_').Replace('-', 'n');

        public static void EnsureCenterLinetype(Transaction tr, Database db)
        {
            var lt = (LinetypeTable)tr.GetObject(db.LinetypeTableId, OpenMode.ForRead);
            if (lt.Has("CENTER")) return;
            try { db.LoadLineTypeFile("CENTER", "acad.lin"); }
            catch
            {
                try { db.LoadLineTypeFile("CENTER", "acadiso.lin"); }
                catch { /* se deja en linea continua; no es un fallo fatal */ }
            }
        }

        /// <summary>Marca una entidad como "eje": gris (ACI 8), CENTER si se pudo cargar, con su propia escala de linea.</summary>
        public static void MarkAsAxis(Transaction tr, Database db, Entity ent, double ltScale)
        {
            EnsureCenterLinetype(tr, db);
            var lt = (LinetypeTable)tr.GetObject(db.LinetypeTableId, OpenMode.ForRead);
            if (lt.Has("CENTER")) ent.Linetype = "CENTER";
            ent.Color = Color.FromColorIndex(ColorMethod.ByAci, 8);
            if (ltScale > 0) ent.LinetypeScale = ltScale;
        }

        public static Polyline BuildPolyline(IList<Point2d> pts)
        {
            var pl = new Polyline();
            for (int i = 0; i < pts.Count; i++) pl.AddVertexAt(i, pts[i], 0.0, 0.0, 0.0);
            return pl;
        }

        /// <summary>Como BuildPolyline, pero con un bulge por vertice (define el arco del tramo hacia el siguiente).</summary>
        public static Polyline BuildPolylineWithBulge(IList<(Point2d pt, double bulge)> data)
        {
            var pl = new Polyline();
            for (int i = 0; i < data.Count; i++) pl.AddVertexAt(i, data[i].pt, data[i].bulge, 0.0, 0.0);
            return pl;
        }

        /// <summary>Desfasa una polilinea "dist" unidades (signo = lado) y añade las curvas resultantes al mismo BTR. Devuelve las curvas creadas.</summary>
        public static List<Curve> OffsetPolyline(Transaction tr, BlockTableRecord owner, Polyline pl, double dist)
        {
            var result = new List<Curve>();
            DBObjectCollection offsets = pl.GetOffsetCurves(dist);
            foreach (DBObject obj in offsets)
            {
                var curve = (Curve)obj;
                owner.AppendEntity(curve);
                tr.AddNewlyCreatedDBObject(curve, true);
                result.Add(curve);
            }
            return result;
        }

        private static bool HasContent(BlockTableRecord btr)
        {
            foreach (ObjectId id in btr) return true;
            return false;
        }

        private static void ClearBlockContents(Transaction tr, BlockTableRecord btr)
        {
            var ids = new List<ObjectId>();
            foreach (ObjectId id in btr) ids.Add(id);
            foreach (ObjectId id in ids)
            {
                var ent = (Entity)tr.GetObject(id, OpenMode.ForWrite);
                ent.Erase();
            }
        }

        private static void AddAttDef(Transaction tr, BlockTableRecord btr, string tag, string prompt, string defaultValue, Point3d pos, double height)
        {
            var attDef = new AttributeDefinition
            {
                Position = pos,
                Height = height,
                Tag = tag,
                Prompt = prompt,
                TextString = defaultValue,
                Justify = AttachmentPoint.BaseLeft,
            };
            btr.AppendEntity(attDef);
            tr.AddNewlyCreatedDBObject(attDef, true);
        }

        private static void AddLine(Transaction tr, BlockTableRecord btr, Point2d p1, Point2d p2)
        {
            var line = new Line(new Point3d(p1.X, p1.Y, 0), new Point3d(p2.X, p2.Y, 0));
            btr.AppendEntity(line);
            tr.AddNewlyCreatedDBObject(line, true);
        }

        /// <summary>
        /// Geometria LOCAL del codo (alrededor del origen): se entra por (0,0,0) en
        /// direccion +X, y el codo gira hacia la IZQUIERDA angDeg grados. Los giros a
        /// la derecha se consiguen espejando el bloque al insertarlo (ScaleFactors Y
        /// negativo), no con un bloque distinto -ver InsertElbow-.
        /// </summary>
        private static void BuildCircularElbowGeometry(Transaction tr, BlockTableRecord btr, double dim, double angDeg)
        {
            double R = RadiusFactor * dim;
            double angRad = angDeg * Math.PI / 180.0;
            double half = dim / 2.0;
            var center = new Point3d(0, R, 0);
            double startAng = 1.5 * Math.PI;
            double endAng = startAng + angRad;

            var outerArc = new Arc(center, R + half, startAng, endAng);
            btr.AppendEntity(outerArc);
            tr.AddNewlyCreatedDBObject(outerArc, true);

            var innerArc = new Arc(center, R - half, startAng, endAng);
            btr.AppendEntity(innerArc);
            tr.AddNewlyCreatedDBObject(innerArc, true);

            double tTan = R * Math.Tan(angRad / 2.0);
            double attH = Math.Max(1.0, dim * 0.12);
            AddAttDef(tr, btr, "DIAM", "Diametro", dim.ToString("0", CultureInfo.InvariantCulture),
                new Point3d(tTan + dim * 0.1, -dim * 0.1, 0), attH);
            AddAttDef(tr, btr, "ANG", "Angulo", angDeg.ToString("0.0", CultureInfo.InvariantCulture),
                new Point3d(tTan + dim * 0.1, -dim * 0.1 - attH * 1.4, 0), attH);
            AddAttDef(tr, btr, "TIPO", "Tipo", "CIRCULAR",
                new Point3d(tTan + dim * 0.1, -dim * 0.1 - attH * 2.8, 0), attH);
        }

        private static void BuildRectElbowGeometry(Transaction tr, BlockTableRecord btr, double dim, double angDeg)
        {
            double angRad = angDeg * Math.PI / 180.0;
            double legLen = RectElbowLegFactor * dim;
            double half = dim / 2.0;
            double cosA = Math.Cos(angRad), sinA = Math.Sin(angRad);

            foreach (double s in new[] { 1.0, -1.0 })
            {
                var nearPt = new Point2d(0, s * half);
                var vOffset = new Point2d(legLen - s * half * sinA, s * half * cosA);
                var corner = GeometryUtil.LineIntersect(nearPt, 0.0, vOffset, angRad);
                if (corner == null) continue; // no deberia pasar para un angulo de deflexion real
                var farPt = new Point2d(vOffset.X + legLen * cosA, vOffset.Y + legLen * sinA);
                AddLine(tr, btr, nearPt, corner.Value);
                AddLine(tr, btr, corner.Value, farPt);
            }

            double attH = Math.Max(1.0, dim * 0.12);
            AddAttDef(tr, btr, "ANCHO", "Ancho", dim.ToString("0", CultureInfo.InvariantCulture),
                new Point3d(legLen + dim * 0.1, -dim * 0.1, 0), attH);
            AddAttDef(tr, btr, "ANG", "Angulo", angDeg.ToString("0.0", CultureInfo.InvariantCulture),
                new Point3d(legLen + dim * 0.1, -dim * 0.1 - attH * 1.4, 0), attH);
            AddAttDef(tr, btr, "TIPO", "Tipo", "RECTANGULAR",
                new Point3d(legLen + dim * 0.1, -dim * 0.1 - attH * 2.8, 0), attH);
        }

        /// <summary>
        /// Devuelve el ObjectId de la definicion de bloque del codo (circular o
        /// rectangular) para dim/angDeg, creandola (o reconstruyendola si el nombre ya
        /// existia pero estaba vacio, de un intento anterior) si hace falta.
        /// </summary>
        public static ObjectId EnsureElbowBlock(Transaction tr, Database db, string tipo, double dim, double angDeg)
        {
            string name = ElbowBlockName(tipo, dim, angDeg);
            var bt = (BlockTable)tr.GetObject(db.BlockTableId, OpenMode.ForRead);

            if (bt.Has(name))
            {
                var existing = (BlockTableRecord)tr.GetObject(bt[name], OpenMode.ForWrite);
                if (HasContent(existing)) return existing.ObjectId;
                ClearBlockContents(tr, existing);
                if (tipo == "Circular") BuildCircularElbowGeometry(tr, existing, dim, angDeg);
                else BuildRectElbowGeometry(tr, existing, dim, angDeg);
                return existing.ObjectId;
            }

            bt.UpgradeOpen();
            var btr = new BlockTableRecord { Name = name };
            bt.Add(btr);
            tr.AddNewlyCreatedDBObject(btr, true);
            if (tipo == "Circular") BuildCircularElbowGeometry(tr, btr, dim, angDeg);
            else BuildRectElbowGeometry(tr, btr, dim, angDeg);
            return btr.ObjectId;
        }

        /// <summary>
        /// Inserta una instancia del bloque de codo en insPt, girada rotAng (radianes,
        /// el eje +X local pasa a coincidir con la direccion de entrada real) y
        /// espejada (ScaleFactors Y = -1) si isLeft es false -los bloques se
        /// construyen siempre para giro a la izquierda-, con sus atributos rellenos a
        /// partir de las ATTDEF del bloque.
        /// </summary>
        public static BlockReference InsertElbow(Transaction tr, BlockTableRecord owner, ObjectId blockDefId, Point2d insPt, double rotAng, bool isLeft)
        {
            var br = new BlockReference(new Point3d(insPt.X, insPt.Y, 0), blockDefId)
            {
                Rotation = rotAng,
                ScaleFactors = new Scale3d(1.0, isLeft ? 1.0 : -1.0, 1.0),
            };
            owner.AppendEntity(br);
            tr.AddNewlyCreatedDBObject(br, true);

            var btr = (BlockTableRecord)tr.GetObject(blockDefId, OpenMode.ForRead);
            foreach (ObjectId id in btr)
            {
                var ent = tr.GetObject(id, OpenMode.ForRead);
                if (ent is AttributeDefinition attDef && !attDef.Constant)
                {
                    var attRef = new AttributeReference();
                    attRef.SetAttributeFromBlock(attDef, br.BlockTransform);
                    attRef.TextString = attDef.TextString;
                    br.AttributeCollection.AppendAttribute(attRef);
                    tr.AddNewlyCreatedDBObject(attRef, true);
                }
            }
            return br;
        }
    }
}
