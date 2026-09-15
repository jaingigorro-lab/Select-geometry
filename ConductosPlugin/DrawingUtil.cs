using System.Collections.Generic;
using Autodesk.AutoCAD.Colors;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.Geometry;

namespace ConductosPlugin
{
    /// <summary>
    /// Everything that touches the AutoCAD database: axis styling, wall offsetting and
    /// the elbow delimiter ticks. Every method here is strongly typed against the real
    /// AutoCAD .NET API (Autodesk.AutoCAD.DatabaseServices), so there is no VARIANT
    /// coercion, no missing DXF subclass markers, no ambiguous point-list-vs-variant
    /// guessing - the compiler already caught anything of that shape before this ever
    /// runs.
    /// </summary>
    internal static class DrawingUtil
    {
        public const double RadiusFactor = 1.5; // codo circular: longitud de zona = este factor x diametro (SMACNA)
        public const double RectElbowLegFactor = 1.0; // codo rectangular: longitud de zona = este factor x ancho

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

        /// <summary>
        /// Marca visualmente el inicio o el fin de un codo: una linea recta perpendicular
        /// al tramo, centrada en "center" y con longitud "width" (el ancho/diametro del
        /// conducto), sin ningun texto ni bloque asociado -es solo un elemento
        /// delimitador que cruza de pared a pared.
        /// </summary>
        public static void AddElbowDelimiter(Transaction tr, BlockTableRecord owner, Point2d center, double dirAng, double width)
        {
            double perp = dirAng + System.Math.PI / 2.0;
            Point2d p1 = GeometryUtil.Polar(center, perp, width / 2.0);
            Point2d p2 = GeometryUtil.Polar(center, perp, -width / 2.0);
            var line = new Line(new Point3d(p1.X, p1.Y, 0), new Point3d(p2.X, p2.Y, 0));
            owner.AppendEntity(line);
            tr.AddNewlyCreatedDBObject(line, true);
        }
    }
}
