using System;
using System.Globalization;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.Colors;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.EditorInput;
using Autodesk.AutoCAD.Geometry;
using Autodesk.AutoCAD.Runtime;
using AcApp = Autodesk.AutoCAD.ApplicationServices.Core.Application;

namespace ConductosPlugin
{
    // ==========================================================
    // CVENT / CVENTT - Traza conductos de ventilacion circular en planta
    // (representacion a dos lineas), con codos CURVOS, reducciones, y
    // derivaciones en T o en cruz que se acoplan a un conducto ya existente.
    // Traduccion 1:1 de ConductoVentilacionCircular_CVENT.lsp, con una
    // diferencia deliberada: en vez de depender de una libreria de bloques
    // externa (.dwg) construida a mano -algo que AutoLISP no puede generar-,
    // este plugin CREA el mismo contrato de bloques (CVENT_TRAMO_RECTO,
    // CVENT_REDUCCION, CVENT_CODO_<angulo>) la primera vez que hace falta,
    // vease BlockFactory.
    //
    // CVENT  - traza un conducto nuevo desde cero, punto a punto.
    // CVENTT - arranca una derivacion (T o cruz) desde un punto de un
    //          conducto YA DIBUJADO con CVENT, y a partir de ahi se traza
    //          igual que con CVENT.
    //
    // Cada giro se ajusta al multiplo de 15 grados mas cercano (hasta un
    // maximo de 90). Se puede desactivar sobre la marcha con "Libre".
    // ==========================================================

    internal static class CventConfig
    {
        // Longitud de la reduccion = TransitionFactor x la diferencia de
        // diametros, con un minimo para que nunca salga una reduccion
        // degenerada entre diametros muy parecidos.
        public const double TransitionFactor = 2.5;
        public const double TransitionMinFactor = 0.5;

        // Incremento de angulo de giro admitido, y tope maximo (grados).
        public const double AngleStep = 15.0;
        public const double AngleMax = 90.0;

        // Por debajo de este angulo (grados) un giro se considera "recto", sin codo.
        public const double AngleEpsilonDeg = 1.0;

        // Radio de eje del codo = este factor x el diametro del conducto (SMACNA).
        public const double ElbowRadiusFactor = 1.5;

        // Diametro de referencia al que se construye cada bloque de codo (luego se
        // inserta escalado uniformemente al diametro real).
        public const double ElbowReferenceDiameter = 100.0;

        public const string WallLayer = "MEP-CONDUCTOS";
        public const string AxisLayer = "MEP-CONDUCTOS-EJE";
        public const short WallColor = 5;  // azul
        public const short AxisColor = 8;  // gris
    }

    /// <summary>Pure math helpers: no tocan la base de datos de AutoCAD.</summary>
    internal static class GeometryUtil
    {
        public static double Dtr(double deg) => deg * Math.PI / 180.0;
        public static double Rtd(double rad) => rad * 180.0 / Math.PI;

        public static double NormPi(double a)
        {
            while (a > Math.PI) a -= 2.0 * Math.PI;
            while (a <= -Math.PI) a += 2.0 * Math.PI;
            return a;
        }

        public static double AngleTo(Point2d from, Point2d to) => Math.Atan2(to.Y - from.Y, to.X - from.X);
        public static double VectorAngle(Vector2d v) => Math.Atan2(v.Y, v.X);

        /// <summary>Vector unitario p1->p2; si p1==p2, (1,0) como valor de reserva.</summary>
        public static Vector2d UnitVector(Point2d p1, Point2d p2)
        {
            double dx = p2.X - p1.X, dy = p2.Y - p1.Y;
            double len = Math.Sqrt(dx * dx + dy * dy);
            return len > 1e-9 ? new Vector2d(dx / len, dy / len) : new Vector2d(1.0, 0.0);
        }

        public static Vector2d LeftNormal(Vector2d d) => new Vector2d(-d.Y, d.X);
        public static Vector2d RightNormal(Vector2d d) => new Vector2d(d.Y, -d.X);

        /// <summary>Punto = base + (normal izquierda de dir, normalizada) * dist.</summary>
        public static Point2d OffsetPoint(Point2d basePt, Vector2d dir, double dist)
        {
            Vector2d perp = new Vector2d(-dir.Y, dir.X);
            double len = perp.Length;
            if (len < 1e-9) len = 1.0;
            return new Point2d(basePt.X + (perp.X / len) * dist, basePt.Y + (perp.Y / len) * dist);
        }

        public static bool DirsParallel(Vector2d d1, Vector2d d2) => Math.Abs(d1.X * d2.Y - d1.Y * d2.X) < 1e-6;

        /// <summary>Interseccion de la recta (p1 + t*d1) con la recta (p2 + s*d2). Si son
        /// practicamente paralelas, se devuelve "fallback" -en ese caso coincide con la
        /// interseccion real (tramo seguido de otro en la misma direccion).</summary>
        public static Point2d LineIntersect(Point2d p1, Vector2d d1, Point2d p2, Vector2d d2, Point2d fallback)
        {
            double denom = d1.X * d2.Y - d1.Y * d2.X;
            if (Math.Abs(denom) < 1e-6) return fallback;
            double t = ((p2.X - p1.X) * d2.Y - (p2.Y - p1.Y) * d2.X) / denom;
            return new Point2d(p1.X + t * d1.X, p1.Y + t * d1.Y);
        }

        public static double RoundTo(double value, double increment) => Math.Round(value / increment) * increment;
    }

    /// <summary>Todo lo que dibuja entidades sueltas (lineas/arcos) y gestiona capas.</summary>
    internal static class DrawingUtil
    {
        public static void EnsureLayer(Transaction tr, Database db, string name, short colorIndex)
        {
            var lt = (LayerTable)tr.GetObject(db.LayerTableId, OpenMode.ForRead);
            if (lt.Has(name)) return;
            lt.UpgradeOpen();
            var ltr = new LayerTableRecord { Name = name, Color = Color.FromColorIndex(ColorMethod.ByAci, colorIndex) };
            lt.Add(ltr);
            tr.AddNewlyCreatedDBObject(ltr, true);
        }

        public static Line DrawLine(Transaction tr, BlockTableRecord owner, Point2d p1, Point2d p2, string layer)
        {
            var line = new Line(new Point3d(p1.X, p1.Y, 0), new Point3d(p2.X, p2.Y, 0)) { Layer = layer };
            owner.AppendEntity(line);
            tr.AddNewlyCreatedDBObject(line, true);
            return line;
        }

        public static Arc DrawArc(Transaction tr, BlockTableRecord owner, Point2d center, double radius, double startAng, double endAng, string layer)
        {
            var arc = new Arc(new Point3d(center.X, center.Y, 0), radius, startAng, endAng) { Layer = layer };
            owner.AppendEntity(arc);
            tr.AddNewlyCreatedDBObject(arc, true);
            return arc;
        }
    }

    /// <summary>
    /// Genera (la primera vez que hace falta) y despues inserta los bloques del
    /// contrato CVENT: CVENT_TRAMO_RECTO_D&lt;diam&gt;, CVENT_REDUCCION_D&lt;d1&gt;_D&lt;d2&gt;,
    /// CVENT_CODO_A&lt;angulo&gt;. El LSP original necesitaba que estos bloques existieran
    /// ya en una libreria .dwg construida a mano (AutoLISP no puede crear bloques
    /// dinamicos); en C# se generan directamente, como bloques normales (no
    /// dinamicos): el tramo recto y la reduccion usan un cuerpo de longitud UNIDAD
    /// que se estira en X al insertarse (ScaleFactors), y el codo se construye a un
    /// diametro de referencia y se inserta escalado uniformemente al diametro real.
    /// </summary>
    internal static class BlockFactory
    {
        private static string Tag(double x) => x.ToString("0.##", CultureInfo.InvariantCulture).Replace('.', '_').Replace('-', 'n');

        public static string StraightBlockName(double diameter) => $"CVENT_TRAMO_RECTO_D{Tag(diameter)}";
        public static string ReductionBlockName(double d1, double d2) => $"CVENT_REDUCCION_D{Tag(d1)}_D{Tag(d2)}";
        public static string ElbowBlockName(double angleDegAbs) => $"CVENT_CODO_A{Tag(Math.Round(angleDegAbs / CventConfig.AngleStep) * CventConfig.AngleStep)}";

        private static bool HasContent(BlockTableRecord btr)
        {
            foreach (ObjectId id in btr) return true;
            return false;
        }

        /// <summary>Da de alta el bloque "name" si no existe (o lo deja listo para
        /// reconstruir si existia pero vacio, de un intento anterior fallido).
        /// Devuelve null si ya existia CON contenido -no hace falta reconstruirlo-.</summary>
        private static BlockTableRecord GetOrCreateEmptyBlock(Transaction tr, Database db, string name)
        {
            var bt = (BlockTable)tr.GetObject(db.BlockTableId, OpenMode.ForRead);
            if (bt.Has(name))
            {
                var existing = (BlockTableRecord)tr.GetObject(bt[name], OpenMode.ForWrite);
                return HasContent(existing) ? null : existing;
            }
            bt.UpgradeOpen();
            var btr = new BlockTableRecord { Name = name };
            bt.Add(btr);
            tr.AddNewlyCreatedDBObject(btr, true);
            return btr;
        }

        private static ObjectId ExistingId(Transaction tr, Database db, string name) =>
            ((BlockTable)tr.GetObject(db.BlockTableId, OpenMode.ForRead))[name];

        /// <summary>Tramo recto de longitud UNIDAD (1): dos lineas paralelas de (0,+-r)
        /// a (1,+-r) en la capa "0" (para heredar la capa de la insercion). Al
        /// insertarse se estira en X = longitud real.</summary>
        public static ObjectId EnsureStraightBlock(Transaction tr, Database db, double diameter)
        {
            string name = StraightBlockName(diameter);
            BlockTableRecord btr = GetOrCreateEmptyBlock(tr, db, name);
            if (btr == null) return ExistingId(tr, db, name);

            double r = diameter / 2.0;
            DrawingUtil.DrawLine(tr, btr, new Point2d(0, r), new Point2d(1, r), "0");
            DrawingUtil.DrawLine(tr, btr, new Point2d(0, -r), new Point2d(1, -r), "0");
            return btr.ObjectId;
        }

        /// <summary>Reduccion de longitud UNIDAD (1): radio r1 en x=0 a radio r2 en
        /// x=1. Al insertarse se estira en X = longitud real.</summary>
        public static ObjectId EnsureReductionBlock(Transaction tr, Database db, double d1, double d2)
        {
            string name = ReductionBlockName(d1, d2);
            BlockTableRecord btr = GetOrCreateEmptyBlock(tr, db, name);
            if (btr == null) return ExistingId(tr, db, name);

            double r1 = d1 / 2.0, r2 = d2 / 2.0;
            DrawingUtil.DrawLine(tr, btr, new Point2d(0, r1), new Point2d(1, r2), "0");
            DrawingUtil.DrawLine(tr, btr, new Point2d(0, -r1), new Point2d(1, -r2), "0");
            return btr.ObjectId;
        }

        /// <summary>
        /// Codo para un angulo normalizado (magnitud, redondeada al multiplo de
        /// AngleStep), a diametro de referencia, girando siempre hacia la IZQUIERDA
        /// -para un giro a la derecha se inserta reflejado (XScale negativo); para
        /// otro diametro, escalado uniformemente-. Tres arcos concentricos (pared
        /// interior, eje, pared exterior); origen = punto de tangencia de entrada,
        /// eje +X = direccion de entrada.
        /// </summary>
        public static ObjectId EnsureElbowBlock(Transaction tr, Database db, double angleDegAbs)
        {
            double snapped = Math.Round(angleDegAbs / CventConfig.AngleStep) * CventConfig.AngleStep;
            string name = ElbowBlockName(snapped);
            BlockTableRecord btr = GetOrCreateEmptyBlock(tr, db, name);
            if (btr == null) return ExistingId(tr, db, name);

            double radius = CventConfig.ElbowReferenceDiameter / 2.0;
            double bendRadius = CventConfig.ElbowRadiusFactor * CventConfig.ElbowReferenceDiameter;

            var t1 = new Point2d(0, 0);
            var center = new Point2d(0, bendRadius);
            double angleT1 = GeometryUtil.AngleTo(center, t1);
            double angleT2 = angleT1 + GeometryUtil.Dtr(snapped);

            double innerRadius = Math.Max(bendRadius - radius, radius * 0.05);
            double outerRadius = bendRadius + radius;

            DrawingUtil.DrawArc(tr, btr, center, innerRadius, angleT1, angleT2, "0");
            DrawingUtil.DrawArc(tr, btr, center, bendRadius, angleT1, angleT2, "0");
            DrawingUtil.DrawArc(tr, btr, center, outerRadius, angleT1, angleT2, "0");

            return btr.ObjectId;
        }

        public static BlockReference InsertStraight(Transaction tr, Database db, BlockTableRecord owner, Point2d startPt, double dirAngle, double length, double diameter)
        {
            ObjectId id = EnsureStraightBlock(tr, db, diameter);
            var br = new BlockReference(new Point3d(startPt.X, startPt.Y, 0), id)
            {
                Rotation = dirAngle,
                ScaleFactors = new Scale3d(length, 1.0, 1.0),
                Layer = CventConfig.WallLayer,
            };
            owner.AppendEntity(br);
            tr.AddNewlyCreatedDBObject(br, true);
            return br;
        }

        public static BlockReference InsertReduction(Transaction tr, Database db, BlockTableRecord owner, Point2d startPt, double dirAngle, double length, double d1, double d2)
        {
            ObjectId id = EnsureReductionBlock(tr, db, d1, d2);
            var br = new BlockReference(new Point3d(startPt.X, startPt.Y, 0), id)
            {
                Rotation = dirAngle,
                ScaleFactors = new Scale3d(length, 1.0, 1.0),
                Layer = CventConfig.WallLayer,
            };
            owner.AppendEntity(br);
            tr.AddNewlyCreatedDBObject(br, true);
            return br;
        }

        public static BlockReference InsertElbow(Transaction tr, Database db, BlockTableRecord owner, Point2d t1, double dirInAngle, double turnAngleDeg, double diameter)
        {
            ObjectId id = EnsureElbowBlock(tr, db, Math.Abs(turnAngleDeg));
            double scaleF = diameter / CventConfig.ElbowReferenceDiameter;
            // El bloque se construye siempre para un giro a la IZQUIERDA, con el
            // punto de tangencia de entrada en el origen y la direccion de entrada
            // en +X local. Para un giro a la DERECHA hay que reflejar el bloque
            // conservando esa direccion de entrada -por eso el reflejo es en Y (el
            // eje de la propia direccion de entrada), NO en X: reflejar en X
            // invertiria tambien la direccion de entrada 180 grados (el vector local
            // (1,0) pasaria a (-1,0) tras el reflejo), dejando el codo insertado al
            // reves respecto al tramo recto que lo precede.
            double yScale = turnAngleDeg < 0.0 ? -scaleF : scaleF;
            var br = new BlockReference(new Point3d(t1.X, t1.Y, 0), id)
            {
                Rotation = dirInAngle,
                ScaleFactors = new Scale3d(scaleF, yScale, 1.0),
                Layer = CventConfig.WallLayer,
            };
            owner.AppendEntity(br);
            tr.AddNewlyCreatedDBObject(br, true);
            return br;
        }
    }

    /// <summary>
    /// Estado "pendiente" de una pieza (tramo recto, reduccion, o el tramo de salida
    /// de un codo) cuyas paredes/eje aun no se han dibujado del todo -solo se
    /// dibujan cuando se sabe exactamente donde deben terminar (inglete con la
    /// siguiente pieza, o tangencia con el siguiente codo)-.
    /// </summary>
    internal sealed class PendingPiece
    {
        public Point2d FinalStartL;   // ya cerrado contra la pieza anterior
        public Point2d FinalStartR;
        public Point2d NaiveEndL;     // extremo sin cerrar, a falta de saber que viene despues
        public Point2d NaiveEndR;
        public Vector2d LeftDir;      // direccion de las dos lineas de pared
        public Vector2d RightDir;
        public Point2d CenterStart;   // eje: donde empieza el tramo (aun sin dibujar)
        public Point2d CenterEnd;
        public Vector2d Dir;          // direccion de avance de esta pieza
        public double Radius;         // radio en el extremo final -el que alimenta al siguiente codo-

        /// <summary>Si esta pieza ya se dibujo entera como bloque, sus paredes NO hay
        /// que volver a dibujarlas al cerrar la union con la siguiente pieza -solo se
        /// usa su informacion geometrica (direccion, radio, punto de eje) para
        /// calcular esa union-. El eje (capa aparte) SI se dibuja siempre, con o sin
        /// bloque.</summary>
        public bool WallsAlreadyDrawn;
    }

    /// <summary>
    /// El algoritmo de trazado propiamente dicho: cierre a inglete entre piezas,
    /// codos curvos con marcas delimitadoras, y el remate final del recorrido.
    /// </summary>
    internal static class DuctTracer
    {
        public static PendingPiece ProcessNextPiece(Transaction tr, BlockTableRecord ms, PendingPiece oldPending, Point2d startPt, Point2d endPt, double startRadius, double endRadius)
        {
            Vector2d cDir = GeometryUtil.UnitVector(startPt, endPt);
            Point2d naiveStartL = GeometryUtil.OffsetPoint(startPt, cDir, startRadius);
            Point2d naiveStartR = GeometryUtil.OffsetPoint(startPt, cDir, -startRadius);
            Point2d naiveEndL = GeometryUtil.OffsetPoint(endPt, cDir, endRadius);
            Point2d naiveEndR = GeometryUtil.OffsetPoint(endPt, cDir, -endRadius);
            Vector2d leftDir = GeometryUtil.UnitVector(naiveStartL, naiveEndL);
            Vector2d rightDir = GeometryUtil.UnitVector(naiveStartR, naiveEndR);

            Point2d finalStartL, finalStartR;
            if (oldPending != null)
            {
                Point2d jointL = GeometryUtil.LineIntersect(oldPending.NaiveEndL, oldPending.LeftDir, naiveStartL, leftDir, naiveStartL);
                Point2d jointR = GeometryUtil.LineIntersect(oldPending.NaiveEndR, oldPending.RightDir, naiveStartR, rightDir, naiveStartR);

                if (!oldPending.WallsAlreadyDrawn)
                {
                    DrawingUtil.DrawLine(tr, ms, oldPending.FinalStartL, jointL, CventConfig.WallLayer);
                    DrawingUtil.DrawLine(tr, ms, oldPending.FinalStartR, jointR, CventConfig.WallLayer);
                }
                DrawingUtil.DrawLine(tr, ms, oldPending.CenterStart, startPt, CventConfig.AxisLayer);
                if (!GeometryUtil.DirsParallel(oldPending.LeftDir, leftDir))
                    DrawingUtil.DrawLine(tr, ms, jointL, jointR, CventConfig.WallLayer);

                finalStartL = jointL;
                finalStartR = jointR;
            }
            else
            {
                finalStartL = naiveStartL;
                finalStartR = naiveStartR;
            }

            return new PendingPiece
            {
                FinalStartL = finalStartL,
                FinalStartR = finalStartR,
                NaiveEndL = naiveEndL,
                NaiveEndR = naiveEndR,
                LeftDir = leftDir,
                RightDir = rightDir,
                CenterStart = startPt,
                CenterEnd = endPt,
                Dir = cDir,
                Radius = endRadius,
                WallsAlreadyDrawn = false,
            };
        }

        /// <summary>Dibuja un tramo (recto o conico) como bloque si useBlocks; remata
        /// primero la pieza pendiente anterior (si la habia) mediante
        /// ProcessNextPiece -esto pasa siempre, dibuje esta pieza un bloque o no-.
        /// Devuelve el nuevo estado pendiente, marcado WallsAlreadyDrawn si esta
        /// pieza se dibujo como bloque (sus paredes no haran falta dibujarlas de
        /// nuevo al cerrar la union con la siguiente).</summary>
        public static PendingPiece DrawPiece(Transaction tr, Database db, BlockTableRecord ms, PendingPiece oldPending, Point2d startPt, Point2d endPt, double startRadius, double endRadius, bool useBlocks)
        {
            bool drewBlock = false;
            if (useBlocks)
            {
                Vector2d dir = GeometryUtil.UnitVector(startPt, endPt);
                double dirAngle = GeometryUtil.VectorAngle(dir);
                double length = startPt.GetDistanceTo(endPt);
                if (Math.Abs(startRadius - endRadius) < 1e-9)
                    BlockFactory.InsertStraight(tr, db, ms, startPt, dirAngle, length, 2.0 * startRadius);
                else
                    BlockFactory.InsertReduction(tr, db, ms, startPt, dirAngle, length, 2.0 * startRadius, 2.0 * endRadius);
                drewBlock = true;
            }

            PendingPiece pending = ProcessNextPiece(tr, ms, oldPending, startPt, endPt, startRadius, endRadius);
            pending.WallsAlreadyDrawn = drewBlock;
            return pending;
        }

        /// <summary>Codo curvo entre el final de la pieza pendiente y el inicio de la
        /// pieza siguiente, dado el giro turnAngle (radianes, con signo: + = izquierda,
        /// - = derecha) en el vertice compartido. Remata la pieza pendiente en el
        /// punto de tangencia de entrada, dibuja el codo (bloque o tres arcos) y las
        /// dos marcas perpendiculares de inicio/fin. Devuelve la pieza siguiente,
        /// arrancando en el punto de tangencia de salida.</summary>
        public static PendingPiece ProcessElbow(Transaction tr, Database db, BlockTableRecord ms, PendingPiece oldPending, Point2d vertexPt, Point2d newEndPt, double turnAngle, bool useBlocks)
        {
            Vector2d dirIn = oldPending.Dir;
            double radius = oldPending.Radius;
            Vector2d dirOut = GeometryUtil.UnitVector(vertexPt, newEndPt);

            // limite defensivo: un giro casi en U dispararia el radio de tangencia al infinito.
            if (turnAngle > 0.0) turnAngle = Math.Min(turnAngle, GeometryUtil.Dtr(170.0));
            else turnAngle = Math.Max(turnAngle, -GeometryUtil.Dtr(170.0));

            double bendRadius = CventConfig.ElbowRadiusFactor * (2.0 * radius);
            double halfAngle = Math.Abs(turnAngle) / 2.0;
            double idealD = Math.Cos(halfAngle) > 1e-6 ? bendRadius * Math.Tan(halfAngle) : bendRadius;

            double pendLen = oldPending.CenterStart.GetDistanceTo(vertexPt);
            double newLen = vertexPt.GetDistanceTo(newEndPt);
            double d = Math.Min(idealD, Math.Min(pendLen, newLen));
            if (d < 1e-6) d = 0.5 * Math.Min(pendLen, newLen);

            double actualBend = halfAngle > 1e-6 ? d / Math.Tan(halfAngle) : bendRadius;
            double innerRadius = Math.Max(actualBend - radius, radius * 0.05);

            Point2d t1 = new Point2d(vertexPt.X - dirIn.X * d, vertexPt.Y - dirIn.Y * d);
            Point2d t2 = new Point2d(vertexPt.X + dirOut.X * d, vertexPt.Y + dirOut.Y * d);

            Vector2d normalVec = turnAngle > 0.0 ? GeometryUtil.LeftNormal(dirIn) : GeometryUtil.RightNormal(dirIn);
            Point2d center = new Point2d(t1.X + normalVec.X * actualBend, t1.Y + normalVec.Y * actualBend);

            double angleT1 = GeometryUtil.AngleTo(center, t1);
            double angleT2 = GeometryUtil.AngleTo(center, t2);
            double startAng, endAng;
            if (turnAngle > 0.0) { startAng = angleT1; endAng = angleT2; }
            else { startAng = angleT2; endAng = angleT1; }
            if (endAng <= startAng) endAng += 2.0 * Math.PI;

            // --- rematar la pieza pendiente hasta el punto de tangencia de entrada ---
            Point2d t1L = GeometryUtil.OffsetPoint(t1, dirIn, radius);
            Point2d t1R = GeometryUtil.OffsetPoint(t1, dirIn, -radius);
            if (!oldPending.WallsAlreadyDrawn)
            {
                DrawingUtil.DrawLine(tr, ms, oldPending.FinalStartL, t1L, CventConfig.WallLayer);
                DrawingUtil.DrawLine(tr, ms, oldPending.FinalStartR, t1R, CventConfig.WallLayer);
            }
            DrawingUtil.DrawLine(tr, ms, oldPending.CenterStart, t1, CventConfig.AxisLayer);
            DrawingUtil.DrawLine(tr, ms, t1L, t1R, CventConfig.WallLayer); // marca perpendicular: inicio del codo

            // --- el codo en si: como bloque si useBlocks, o como tres arcos sueltos ---
            if (useBlocks)
            {
                BlockFactory.InsertElbow(tr, db, ms, t1, GeometryUtil.VectorAngle(dirIn), GeometryUtil.Rtd(turnAngle), 2.0 * radius);
            }
            else
            {
                DrawingUtil.DrawArc(tr, ms, center, innerRadius, startAng, endAng, CventConfig.WallLayer);
                DrawingUtil.DrawArc(tr, ms, center, actualBend, startAng, endAng, CventConfig.AxisLayer);
                DrawingUtil.DrawArc(tr, ms, center, actualBend + radius, startAng, endAng, CventConfig.WallLayer);
            }

            // --- marca perpendicular: fin del codo ---
            Point2d t2L = GeometryUtil.OffsetPoint(t2, dirOut, radius);
            Point2d t2R = GeometryUtil.OffsetPoint(t2, dirOut, -radius);
            DrawingUtil.DrawLine(tr, ms, t2L, t2R, CventConfig.WallLayer);

            // --- pieza nueva: arranca en el punto de tangencia de salida ---
            Point2d newNaiveEndL = GeometryUtil.OffsetPoint(newEndPt, dirOut, radius);
            Point2d newNaiveEndR = GeometryUtil.OffsetPoint(newEndPt, dirOut, -radius);
            Vector2d newLeftDir = GeometryUtil.UnitVector(t2L, newNaiveEndL);
            Vector2d newRightDir = GeometryUtil.UnitVector(t2R, newNaiveEndR);

            return new PendingPiece
            {
                FinalStartL = t2L,
                FinalStartR = t2R,
                NaiveEndL = newNaiveEndL,
                NaiveEndR = newNaiveEndR,
                LeftDir = newLeftDir,
                RightDir = newRightDir,
                CenterStart = t2,
                CenterEnd = newEndPt,
                Dir = dirOut,
                Radius = radius,
                WallsAlreadyDrawn = false,
            };
        }

        /// <summary>Dibuja la ultima pieza pendiente (el extremo abierto del
        /// conducto): no hay tramo siguiente con el que empalmar, asi que se usa su
        /// final tal cual se calculo.</summary>
        public static void FlushPending(Transaction tr, BlockTableRecord ms, PendingPiece pending)
        {
            if (pending == null) return;
            if (!pending.WallsAlreadyDrawn)
            {
                DrawingUtil.DrawLine(tr, ms, pending.FinalStartL, pending.NaiveEndL, CventConfig.WallLayer);
                DrawingUtil.DrawLine(tr, ms, pending.FinalStartR, pending.NaiveEndR, CventConfig.WallLayer);
            }
            DrawingUtil.DrawLine(tr, ms, pending.CenterStart, pending.CenterEnd, CventConfig.AxisLayer);
        }

        /// <summary>Calcula el punto siguiente ajustado (si restrictMode y hay una
        /// direccion anterior) y el angulo de giro final con signo: + = izquierda, -
        /// = derecha. Si es el primer tramo del recorrido (lastDir nulo), angulo =
        /// 0.</summary>
        public static (Point2d point, double turnAngleRad) ResolveNextPoint(Point2d p0, Point2d pt, Vector2d? lastDir, bool restrictMode)
        {
            if (lastDir == null) return (pt, 0.0);

            Vector2d rawDir = GeometryUtil.UnitVector(p0, pt);
            double rawLen = p0.GetDistanceTo(pt);
            double lastAngleAbs = GeometryUtil.VectorAngle(lastDir.Value);
            double rawAngleAbs = GeometryUtil.VectorAngle(rawDir);
            double deflection = GeometryUtil.NormPi(rawAngleAbs - lastAngleAbs);

            double finalRad;
            if (restrictMode)
            {
                double snappedDeg = GeometryUtil.RoundTo(GeometryUtil.Rtd(deflection), CventConfig.AngleStep);
                snappedDeg = Math.Max(-CventConfig.AngleMax, Math.Min(CventConfig.AngleMax, snappedDeg));
                finalRad = GeometryUtil.Dtr(snappedDeg);
            }
            else
            {
                finalRad = deflection;
            }

            double newAngleAbs = lastAngleAbs + finalRad;
            Vector2d newDir = new Vector2d(Math.Cos(newAngleAbs), Math.Sin(newAngleAbs));
            Point2d newPt = new Point2d(p0.X + newDir.X * rawLen, p0.Y + newDir.Y * rawLen);
            return (newPt, finalRad);
        }
    }

    /// <summary>
    /// Bucle interactivo comun a CVENT y a cada rama de CVENTT: parte de un punto p0
    /// ya establecido (con su diametro, su pieza "pendiente" -null si es un arranque
    /// libre- y su direccion anterior -null si no hay ninguna con la que medir el
    /// primer giro-), y va pidiendo puntos hasta Salir. Cada punto se dibuja de
    /// inmediato (no se espera a terminar todo el recorrido).
    /// </summary>
    internal static class DuctRunner
    {
        public static void TraceDuctRun(Database db, Editor ed, double diam, Point2d p0, PendingPiece pending, Vector2d? lastDir, bool restrictAngles, string cmdTag)
        {
            const bool useBlocks = true; // los bloques se generan solos, vease BlockFactory
            double? pendDiam = null;
            int segCount = 0, redCount = 0, elbowCount = 0;
            bool done = false;

            while (!done)
            {
                var pko = new PromptPointOptions($"\n[{cmdTag}] Punto siguiente [Diametro/Libre/Salir] <Salir>: ")
                {
                    UseBasePoint = true,
                    BasePoint = new Point3d(p0.X, p0.Y, 0),
                    AllowNone = true,
                };
                pko.Keywords.Add("Diametro");
                pko.Keywords.Add("Libre");
                pko.Keywords.Add("Salir");
                var ppr = ed.GetPoint(pko);

                if (ppr.Status == PromptStatus.None) { done = true; continue; }
                if (ppr.Status == PromptStatus.Keyword)
                {
                    switch (ppr.StringResult)
                    {
                        case "Diametro":
                        {
                            double def = pendDiam ?? diam;
                            var pdo = new PromptDistanceOptions($"\n[{cmdTag}] Nuevo diametro: ")
                            {
                                AllowNegative = false,
                                AllowZero = false,
                                DefaultValue = def,
                                UseDefaultValue = true,
                            };
                            var pdr = ed.GetDistance(pdo);
                            pendDiam = pdr.Status == PromptStatus.OK ? pdr.Value : def;
                            break;
                        }
                        case "Libre":
                            restrictAngles = !restrictAngles;
                            ed.WriteMessage(restrictAngles
                                ? $"\n[{cmdTag}] Giros restringidos a multiplos de 15 grados."
                                : $"\n[{cmdTag}] Giros libres (sin restriccion de angulo).");
                            break;
                        case "Salir":
                            done = true;
                            break;
                    }
                    continue;
                }
                if (ppr.Status != PromptStatus.OK) { done = true; continue; }

                Point2d pt = new Point2d(ppr.Value.X, ppr.Value.Y);
                (Point2d resolvedPt, double turnAngle) = DuctTracer.ResolveNextPoint(p0, pt, lastDir, restrictAngles);
                pt = resolvedPt;
                if (restrictAngles && Math.Abs(GeometryUtil.Rtd(turnAngle)) > 1e-6)
                    ed.WriteMessage($"\n[{cmdTag}] Giro ajustado a {GeometryUtil.Rtd(turnAngle):0} grados.");

                using (Transaction tr = db.TransactionManager.StartTransaction())
                {
                    var bt = (BlockTable)tr.GetObject(db.BlockTableId, OpenMode.ForRead);
                    var ms = (BlockTableRecord)tr.GetObject(bt[BlockTableRecord.ModelSpace], OpenMode.ForWrite);

                    Point2d effectiveStart = p0;
                    if (pending != null && Math.Abs(GeometryUtil.Rtd(turnAngle)) > CventConfig.AngleEpsilonDeg)
                    {
                        pending = DuctTracer.ProcessElbow(tr, db, ms, pending, p0, pt, turnAngle, useBlocks);
                        effectiveStart = pending.CenterStart;
                        elbowCount++;
                    }

                    if (pendDiam.HasValue && Math.Abs(pendDiam.Value - diam) > 1e-9)
                    {
                        Vector2d dirv = GeometryUtil.UnitVector(effectiveStart, pt);
                        double segLen = effectiveStart.GetDistanceTo(pt);
                        double transLen = Math.Min(segLen, Math.Max(
                            CventConfig.TransitionFactor * Math.Abs(pendDiam.Value - diam),
                            CventConfig.TransitionMinFactor * Math.Min(diam, pendDiam.Value)));
                        Point2d pMid = new Point2d(effectiveStart.X + dirv.X * transLen, effectiveStart.Y + dirv.Y * transLen);

                        pending = DuctTracer.DrawPiece(tr, db, ms, pending, effectiveStart, pMid, diam / 2.0, pendDiam.Value / 2.0, useBlocks);
                        redCount++;

                        if (pMid.GetDistanceTo(pt) > 1e-6)
                        {
                            pending = DuctTracer.DrawPiece(tr, db, ms, pending, pMid, pt, pendDiam.Value / 2.0, pendDiam.Value / 2.0, useBlocks);
                            segCount++;
                        }
                        diam = pendDiam.Value;
                        pendDiam = null;
                    }
                    else
                    {
                        pending = DuctTracer.DrawPiece(tr, db, ms, pending, effectiveStart, pt, diam / 2.0, diam / 2.0, useBlocks);
                        segCount++;
                    }

                    tr.Commit();
                }

                lastDir = GeometryUtil.UnitVector(p0, pt);
                p0 = pt;
                ed.Regen();
            }

            using (Transaction tr = db.TransactionManager.StartTransaction())
            {
                var bt = (BlockTable)tr.GetObject(db.BlockTableId, OpenMode.ForRead);
                var ms = (BlockTableRecord)tr.GetObject(bt[BlockTableRecord.ModelSpace], OpenMode.ForWrite);
                DuctTracer.FlushPending(tr, ms, pending);
                tr.Commit();
            }

            ed.Regen();
            ed.WriteMessage($"\n[{cmdTag}] Trazado completo: {segCount} tramo(s), {redCount} reduccion(es), {elbowCount} codo(s).");
        }
    }

    public class CventCommands
    {
        [CommandMethod("CVENT")]
        public void Cvent()
        {
            Document doc = AcApp.DocumentManager.MdiActiveDocument;
            Database db = doc.Database;
            Editor ed = doc.Editor;

            using (Transaction tr = db.TransactionManager.StartTransaction())
            {
                DrawingUtil.EnsureLayer(tr, db, CventConfig.WallLayer, CventConfig.WallColor);
                DrawingUtil.EnsureLayer(tr, db, CventConfig.AxisLayer, CventConfig.AxisColor);
                tr.Commit();
            }

            var pdo = new PromptDistanceOptions("\n[CVENT] Diametro inicial del conducto: ")
            {
                AllowNegative = false,
                AllowZero = false,
                DefaultValue = 200.0,
                UseDefaultValue = true,
            };
            var pdr = ed.GetDistance(pdo);
            double diam = pdr.Status == PromptStatus.OK ? pdr.Value : 200.0;

            var pprFirst = ed.GetPoint("\n[CVENT] Punto inicial del conducto: ");
            if (pprFirst.Status != PromptStatus.OK) { ed.WriteMessage("\n[CVENT] Cancelado."); return; }
            Point2d p0 = new Point2d(pprFirst.Value.X, pprFirst.Value.Y);

            ed.WriteMessage("\n[CVENT] Giros restringidos a multiplos de 15 grados (maximo 90). Escribe \"Libre\" para alternar.");

            DuctRunner.TraceDuctRun(db, ed, diam, p0, null, null, true, "CVENT");
        }
    }

    public class CventBranchCommands
    {
        [CommandMethod("CVENTT")]
        public void Cventt()
        {
            Document doc = AcApp.DocumentManager.MdiActiveDocument;
            Database db = doc.Database;
            Editor ed = doc.Editor;

            using (Transaction tr0 = db.TransactionManager.StartTransaction())
            {
                DrawingUtil.EnsureLayer(tr0, db, CventConfig.WallLayer, CventConfig.WallColor);
                DrawingUtil.EnsureLayer(tr0, db, CventConfig.AxisLayer, CventConfig.AxisColor);
                tr0.Commit();
            }

            var per = ed.GetEntity("\n[CVENTT] Selecciona el EJE del conducto principal donde se acopla la derivacion: ");
            if (per.Status != PromptStatus.OK) { ed.WriteMessage("\n[CVENTT] Cancelado."); return; }

            Point2d mainAxisPt;
            Vector2d mainDir;
            using (Transaction tr = db.TransactionManager.StartTransaction())
            {
                var ent = (Entity)tr.GetObject(per.ObjectId, OpenMode.ForRead);
                if (!(ent is Curve curve) || !(ent is Line || ent is Arc) ||
                    !string.Equals(ent.Layer, CventConfig.AxisLayer, StringComparison.OrdinalIgnoreCase))
                {
                    ed.WriteMessage($"\n[CVENTT] Esa entidad no es un eje de conducto de CVENT (capa {CventConfig.AxisLayer}, recta o arco).");
                    return;
                }

                Point3d onCurve3d = curve.GetClosestPointTo(per.PickedPoint, true);
                Vector3d deriv = curve.GetFirstDerivative(onCurve3d);
                mainAxisPt = new Point2d(onCurve3d.X, onCurve3d.Y);
                mainDir = new Vector2d(deriv.X, deriv.Y).GetNormal();
                tr.Commit();
            }

            var pdoMain = new PromptDistanceOptions("\n[CVENTT] Diametro del conducto principal en ese punto: ")
            {
                AllowNegative = false,
                AllowZero = false,
                DefaultValue = 200.0,
                UseDefaultValue = true,
            };
            var pdrMain = ed.GetDistance(pdoMain);
            double mainDiam = pdrMain.Status == PromptStatus.OK ? pdrMain.Value : 200.0;
            double mainRadius = mainDiam / 2.0;

            var pdoBranch = new PromptDistanceOptions("\n[CVENTT] Diametro de la derivacion: ")
            {
                AllowNegative = false,
                AllowZero = false,
                DefaultValue = mainDiam,
                UseDefaultValue = true,
            };
            var pdrBranch = ed.GetDistance(pdoBranch);
            double branchDiam = pdrBranch.Status == PromptStatus.OK ? pdrBranch.Value : mainDiam;
            double branchRadius = branchDiam / 2.0;

            if (branchDiam > mainDiam)
                ed.WriteMessage("\n[CVENTT] Aviso: en un injerto real el ramal no deberia ser mas ancho que el conducto principal.");

            var pko = new PromptKeywordOptions("\n[CVENTT] Tipo de derivacion [Te/Cruz] <Te>: ") { AllowNone = true };
            pko.Keywords.Add("Te");
            pko.Keywords.Add("Cruz");
            pko.Keywords.Default = "Te";
            var pkr = ed.GetKeywords(pko);
            string kind = (pkr.Status == PromptStatus.OK && !string.IsNullOrEmpty(pkr.StringResult)) ? pkr.StringResult : "Te";

            var ppoSide = new PromptPointOptions("\n[CVENTT] Indica hacia donde sale la derivacion (clic): ")
            {
                UseBasePoint = true,
                BasePoint = new Point3d(mainAxisPt.X, mainAxisPt.Y, 0),
            };
            var pprSide = ed.GetPoint(ppoSide);
            if (pprSide.Status != PromptStatus.OK) { ed.WriteMessage("\n[CVENTT] Cancelado."); return; }
            Point2d sidePt = new Point2d(pprSide.Value.X, pprSide.Value.Y);

            Vector2d branchDir = ResolveBranchDirection(mainDir, sidePt, mainAxisPt, true, ed);

            if (kind == "Te")
            {
                Point2d edgePoint = MainDuctEdgePoint(mainAxisPt, mainDir, mainRadius, branchDir);
                DrawBranchStartMarkTx(db, edgePoint, branchDir, branchRadius);

                ed.WriteMessage("\n[CVENTT] --- Trazando la derivacion ---");
                DuctRunner.TraceDuctRun(db, ed, branchDiam, edgePoint, null, branchDir, true, "CVENTT");
            }
            else
            {
                Point2d edgePoint1 = MainDuctEdgePoint(mainAxisPt, mainDir, mainRadius, branchDir);
                DrawBranchStartMarkTx(db, edgePoint1, branchDir, branchRadius);
                ed.WriteMessage("\n[CVENTT] --- Trazando la primera derivacion (lado 1) ---");
                DuctRunner.TraceDuctRun(db, ed, branchDiam, edgePoint1, null, branchDir, true, "CVENTT");

                Vector2d branchDir2 = new Vector2d(-branchDir.X, -branchDir.Y);
                Point2d edgePoint2 = MainDuctEdgePoint(mainAxisPt, mainDir, mainRadius, branchDir2);
                DrawBranchStartMarkTx(db, edgePoint2, branchDir2, branchRadius);
                ed.WriteMessage("\n[CVENTT] --- Trazando la segunda derivacion (lado 2) ---");
                DuctRunner.TraceDuctRun(db, ed, branchDiam, edgePoint2, null, branchDir2, true, "CVENTT");
            }
        }

        /// <summary>Angulo de la derivacion respecto al conducto principal, ajustado
        /// (si restrictMode) al multiplo de AngleStep mas cercano, igual que un giro
        /// de CVENT -no obliga a ser perpendicular, admite 90 (Te), 45, u otro
        /// multiplo de 15-.</summary>
        private static Vector2d ResolveBranchDirection(Vector2d mainDir, Point2d sidePt, Point2d mainAxisPt, bool restrictMode, Editor ed)
        {
            Vector2d toSide = GeometryUtil.UnitVector(mainAxisPt, sidePt);
            double mainAngleAbs = GeometryUtil.VectorAngle(mainDir);
            double sideAngleAbs = GeometryUtil.VectorAngle(toSide);
            double deflection = GeometryUtil.NormPi(sideAngleAbs - mainAngleAbs);

            double finalRad;
            if (restrictMode)
            {
                double snappedDeg = GeometryUtil.RoundTo(GeometryUtil.Rtd(deflection), CventConfig.AngleStep);
                snappedDeg = Math.Max(-CventConfig.AngleMax, Math.Min(CventConfig.AngleMax, snappedDeg));
                finalRad = GeometryUtil.Dtr(snappedDeg);
                ed.WriteMessage($"\n[CVENTT] Angulo de la derivacion respecto al principal: {snappedDeg:0} grados.");
            }
            else
            {
                finalRad = deflection;
            }

            double ang = mainAngleAbs + finalRad;
            return new Vector2d(Math.Cos(ang), Math.Sin(ang));
        }

        /// <summary>Punto real donde el eje de la derivacion cruza la pared del
        /// conducto principal -el lado (izquierda/derecha de mainDir) se elige segun
        /// hacia donde apunta branchDir-. Para cualquier angulo (no solo
        /// perpendicular) es la interseccion real, asi la derivacion se acopla
        /// exactamente en la pared.</summary>
        private static Point2d MainDuctEdgePoint(Point2d mainAxisPt, Vector2d mainDir, double mainRadius, Vector2d branchDir)
        {
            Vector2d leftN = GeometryUtil.LeftNormal(mainDir);
            double dotLeft = branchDir.X * leftN.X + branchDir.Y * leftN.Y;
            double sideRadius = dotLeft >= 0.0 ? mainRadius : -mainRadius;
            Point2d wallPt = GeometryUtil.OffsetPoint(mainAxisPt, mainDir, sideRadius);
            return GeometryUtil.LineIntersect(mainAxisPt, branchDir, wallPt, mainDir, mainAxisPt);
        }

        /// <summary>Marca perpendicular en el punto de arranque de UNA derivacion,
        /// sobre su propio eje: delimita donde el ramal se injerta en el conducto
        /// principal (que NO se modifica ni se corta) y donde empieza el tramo recto
        /// de la derivacion propiamente dicha.</summary>
        private static void DrawBranchStartMarkTx(Database db, Point2d edgePoint, Vector2d branchDir, double branchRadius)
        {
            using (Transaction tr = db.TransactionManager.StartTransaction())
            {
                var bt = (BlockTable)tr.GetObject(db.BlockTableId, OpenMode.ForRead);
                var ms = (BlockTableRecord)tr.GetObject(bt[BlockTableRecord.ModelSpace], OpenMode.ForWrite);
                Point2d p1 = GeometryUtil.OffsetPoint(edgePoint, branchDir, branchRadius);
                Point2d p2 = GeometryUtil.OffsetPoint(edgePoint, branchDir, -branchRadius);
                DrawingUtil.DrawLine(tr, ms, p1, p2, CventConfig.WallLayer);
                tr.Commit();
            }
        }
    }
}
