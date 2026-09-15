using System;
using System.Collections.Generic;
using System.Linq;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.Colors;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.EditorInput;
using Autodesk.AutoCAD.Geometry;
using Autodesk.AutoCAD.GraphicsInterface;
using Autodesk.AutoCAD.Runtime;
using AcApp = Autodesk.AutoCAD.ApplicationServices.Core.Application;

namespace ConductosPlugin
{
    /// <summary>
    /// Pure math helpers shared by CONDUCTO, CONDUCTORAMAL y el jig de trazado: no
    /// tocan la base de datos de AutoCAD, solo puntos/angulos.
    /// </summary>
    internal static class GeometryUtil
    {
        // Angulos de codo normalizados (SMACNA). 0 = seguir recto (no es un codo real,
        // se incluye para que el trazado pueda continuar en linea sin forzar un giro).
        public static readonly double[] StandardTurnsCircularDeg = { 0.0, 15.0, 22.5, 30.0, 45.0, 90.0 };
        public static readonly double[] StandardTurnsRectangularDeg = { 0.0, 90.0 };

        public static double[] StandardTurnsDeg(string tipo) =>
            tipo == "Circular" ? StandardTurnsCircularDeg : StandardTurnsRectangularDeg;

        /// <summary>Angulo de codo normalizado (magnitud, sin signo) mas cercano a una deflexion dada.</summary>
        public static double NearestStandardTurn(double deflDeg, string tipo)
        {
            double[] opts = StandardTurnsDeg(tipo);
            double best = opts[0];
            double bestDiff = Math.Abs(deflDeg - best);
            foreach (double a in opts)
            {
                double d = Math.Abs(deflDeg - a);
                if (d < bestDiff) { bestDiff = d; best = a; }
            }
            return best;
        }

        public static double NormPi(double a)
        {
            while (a > Math.PI) a -= 2.0 * Math.PI;
            while (a <= -Math.PI) a += 2.0 * Math.PI;
            return a;
        }

        public static double AngleTo(Point2d from, Point2d to) => Math.Atan2(to.Y - from.Y, to.X - from.X);

        public static Point2d Polar(Point2d p, double ang, double dist) =>
            new Point2d(p.X + dist * Math.Cos(ang), p.Y + dist * Math.Sin(ang));

        /// <summary>Intersection of the infinite line through p1 (direction dir1) and through p2 (direction dir2). Null if parallel.</summary>
        public static Point2d? LineIntersect(Point2d p1, double dir1, Point2d p2, double dir2)
        {
            double dx1 = Math.Cos(dir1), dy1 = Math.Sin(dir1);
            double dx2 = Math.Cos(dir2), dy2 = Math.Sin(dir2);
            double denom = dx1 * dy2 - dy1 * dx2;
            if (Math.Abs(denom) < 1e-9) return null;
            double t = ((p2.X - p1.X) * dy2 - (p2.Y - p1.Y) * dx2) / denom;
            return new Point2d(p1.X + t * dx1, p1.Y + t * dy1);
        }
    }

    /// <summary>
    /// Everything that touches the AutoCAD database: axis styling, paredes de doble
    /// linea y los delimitadores de codo. Cada metodo esta tipado contra la API real de
    /// AutoCAD (Autodesk.AutoCAD.DatabaseServices), sin VARIANT ni ambiguedad.
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
            double perp = dirAng + Math.PI / 2.0;
            Point2d p1 = GeometryUtil.Polar(center, perp, width / 2.0);
            Point2d p2 = GeometryUtil.Polar(center, perp, -width / 2.0);
            var line = new Line(new Point3d(p1.X, p1.Y, 0), new Point3d(p2.X, p2.Y, 0));
            owner.AppendEntity(line);
            tr.AddNewlyCreatedDBObject(line, true);
        }

        /// <summary>Tramo recto de pared de doble linea entre a y b (offset +-half). No dibuja nada si a==b. Devuelve si tuvo exito.</summary>
        public static bool DrawWallSegment(Transaction tr, BlockTableRecord owner, Point2d a, Point2d b, double half)
        {
            if (a.GetDistanceTo(b) <= 1e-6) return false;
            Polyline segPl = BuildPolyline(new List<Point2d> { a, b });
            owner.AppendEntity(segPl);
            tr.AddNewlyCreatedDBObject(segPl, true);
            List<Curve> off1 = OffsetPolyline(tr, owner, segPl, half);
            List<Curve> off2 = OffsetPolyline(tr, owner, segPl, -half);
            segPl.Erase();
            return off1.Count > 0 && off2.Count > 0;
        }

        /// <summary>Tramo de eje (linea CENTER gris) entre a y b. No dibuja nada si a==b.</summary>
        public static void DrawAxisSegment(Transaction tr, Database db, BlockTableRecord owner, Point2d a, Point2d b, double ltScale)
        {
            if (a.GetDistanceTo(b) <= 1e-6) return;
            Polyline pl = BuildPolyline(new List<Point2d> { a, b });
            owner.AppendEntity(pl);
            tr.AddNewlyCreatedDBObject(pl, true);
            MarkAsAxis(tr, db, pl, ltScale);
        }
    }

    /// <summary>
    /// Jig interactivo para el siguiente punto de CONDUCTO. Si ya hay una direccion de
    /// entrada (heading), ajusta la direccion del segmento candidato al angulo de codo
    /// normalizado mas cercano (0 = seguir recto, o uno de los angulos SMACNA
    /// disponibles para el tipo de conducto) y dibuja en vivo un abanico con TODAS las
    /// rutas/angulos posibles desde el punto pivote, con el segmento activo resaltado.
    /// Asi el angulo resultante SIEMPRE es uno valido -no hace falta validar (ni
    /// rechazar el recorrido) despues de trazarlo-.
    /// </summary>
    internal sealed class DuctTurnJig : DrawJig
    {
        private readonly Point3d _pivot;
        private readonly bool _hasHeading;
        private readonly double _heading;
        private readonly string _tipo;
        private readonly double _fanLen;

        private Point3d _current;

        public bool Finished { get; private set; }
        public Point3d Result => _current;
        public double ResultTurnDeg { get; private set; }

        public DuctTurnJig(Point3d pivot, bool hasHeading, double heading, string tipo, double fanLen)
        {
            _pivot = pivot;
            _hasHeading = hasHeading;
            _heading = heading;
            _tipo = tipo;
            _fanLen = fanLen;
            _current = pivot;
        }

        protected override SamplerStatus Sampler(JigPrompts prompts)
        {
            var opts = new JigPromptPointOptions(_hasHeading
                ? "\n[CONDUCTO] Punto siguiente, se ajusta al codo normalizado mas cercano (Intro para terminar): "
                : "\n[CONDUCTO] Punto siguiente (Intro para terminar): ")
            {
                UseBasePoint = true,
                BasePoint = _pivot,
                UserInputControls = UserInputControls.NullResponseAccepted | UserInputControls.Accept3dCoordinates,
            };

            PromptPointResult res = prompts.AcquirePoint(opts);
            if (res.Status == PromptStatus.None) { Finished = true; return SamplerStatus.Cancel; }
            if (res.Status != PromptStatus.OK) return SamplerStatus.Cancel;

            Point3d snapped = Snap(res.Value);
            if (snapped.DistanceTo(_current) < 1e-9) return SamplerStatus.NoChange;
            _current = snapped;
            return SamplerStatus.OK;
        }

        private Point3d Snap(Point3d raw)
        {
            var pivot2 = new Point2d(_pivot.X, _pivot.Y);
            var raw2 = new Point2d(raw.X, raw.Y);
            double dist = pivot2.GetDistanceTo(raw2);
            if (dist < 1e-6) { ResultTurnDeg = 0.0; return _pivot; }

            if (!_hasHeading)
            {
                // Primer tramo: cualquier direccion es valida, no hay heading de
                // referencia contra el que ajustar un angulo de codo.
                ResultTurnDeg = 0.0;
                return raw;
            }

            double rawAng = GeometryUtil.AngleTo(pivot2, raw2);
            double rawTurnDeg = GeometryUtil.NormPi(rawAng - _heading) * 180.0 / Math.PI; // -180..180
            double sign = rawTurnDeg < 0 ? -1.0 : 1.0;
            double mag = GeometryUtil.NearestStandardTurn(Math.Abs(rawTurnDeg), _tipo);
            ResultTurnDeg = mag;

            double snappedAng = _heading + sign * mag * Math.PI / 180.0;
            Point2d snapped2 = GeometryUtil.Polar(pivot2, snappedAng, dist);
            return new Point3d(snapped2.X, snapped2.Y, 0);
        }

        protected override bool WorldDraw(WorldDraw draw)
        {
            if (_hasHeading)
            {
                // Abanico: una marca corta por cada angulo de codo disponible (a
                // izquierda y a derecha), para ver de un vistazo las rutas posibles.
                var pivot2 = new Point2d(_pivot.X, _pivot.Y);
                draw.SubEntityTraits.Color = 8; // gris
                foreach (double mag in GeometryUtil.StandardTurnsDeg(_tipo))
                {
                    if (mag <= 1e-9) continue; // "seguir recto" no necesita marca aparte
                    foreach (double sign in new[] { 1.0, -1.0 })
                    {
                        double ang = _heading + sign * mag * Math.PI / 180.0;
                        Point2d tip2 = GeometryUtil.Polar(pivot2, ang, _fanLen);
                        draw.Geometry.WorldLine(_pivot, new Point3d(tip2.X, tip2.Y, 0));
                    }
                }
            }

            // Segmento candidato activo (el que se creara si se hace clic ahora), resaltado.
            draw.SubEntityTraits.Color = 3; // verde
            draw.Geometry.WorldLine(_pivot, _current);
            return true;
        }
    }

    /// <summary>
    /// CONDUCTO - traza un recorrido de conducto (circular o rectangular) a doble linea
    /// y a escala real, de forma INTERACTIVA: la pared, el eje y los codos se van
    /// dibujando tramo a tramo segun se hace clic en cada punto, no al final. Cada punto
    /// (a partir del segundo tramo) se ajusta en vivo al angulo de codo normalizado
    /// SMACNA mas cercano (90/45/30/22.5/15 en circular, solo 90 en rectangular, o 0
    /// para seguir recto), mostrando en pantalla un abanico con todas las rutas
    /// disponibles desde ese punto -por construccion el angulo resultante siempre es
    /// valido, asi que nunca hace falta rechazar el recorrido despues de trazarlo-. Cada
    /// codo se marca solo con dos lineas delimitadoras perpendiculares al tramo -donde
    /// empieza y donde termina la zona del codo-, sin bloque ni texto.
    /// </summary>
    public class ConductoCommands
    {
        [CommandMethod("CONDUCTO")]
        public void Conducto()
        {
            Document doc = AcApp.DocumentManager.MdiActiveDocument;
            Database db = doc.Database;
            Editor ed = doc.Editor;

            var pko = new PromptKeywordOptions("\n[CONDUCTO] Tipo de conducto [Circular/Rectangular] <Circular>: ") { AllowNone = true };
            pko.Keywords.Add("Circular");
            pko.Keywords.Add("Rectangular");
            pko.Keywords.Default = "Circular";
            var pkr = ed.GetKeywords(pko);
            if (pkr.Status == PromptStatus.Cancel) { ed.WriteMessage("\n[CONDUCTO] Cancelado."); return; }
            string tipo = (pkr.Status == PromptStatus.OK && !string.IsNullOrEmpty(pkr.StringResult)) ? pkr.StringResult : "Circular";

            string dimPrompt = tipo == "Circular"
                ? "\n[CONDUCTO] Diametro del conducto: "
                : "\n[CONDUCTO] Ancho del conducto (dimension en planta): ";
            var pdo = new PromptDistanceOptions(dimPrompt) { AllowNegative = false, AllowZero = false };
            var pdr = ed.GetDistance(pdo);
            if (pdr.Status != PromptStatus.OK) { ed.WriteMessage("\n[CONDUCTO] Cancelado."); return; }
            double dim = pdr.Value;
            double half = dim / 2.0;

            string angulosTxt = string.Join(", ", GeometryUtil.StandardTurnsDeg(tipo).Where(a => a > 0).Select(a => a.ToString("0.#")));
            ed.WriteMessage($"\n[CONDUCTO] Angulos de codo disponibles: {angulosTxt} (y recto); cada punto se ajusta solo al mas cercano.");

            var pprFirst = ed.GetPoint(new PromptPointOptions("\n[CONDUCTO] Punto inicial del recorrido: "));
            if (pprFirst.Status != PromptStatus.OK) { ed.WriteMessage("\n[CONDUCTO] Cancelado."); return; }

            Point2d start = new Point2d(pprFirst.Value.X, pprFirst.Value.Y);
            Point2d prevBoundary = start;
            Point2d lastVertex = start;
            bool hasHeading = false;
            double heading = 0.0;
            int nLegs = 0, nElbows = 0, warnCount = 0, pointCount = 0;

            while (true)
            {
                var jig = new DuctTurnJig(new Point3d(lastVertex.X, lastVertex.Y, 0), hasHeading, heading, tipo, dim * 2.0);
                PromptResult dragRes = ed.Drag(jig);

                if (dragRes.Status != PromptStatus.OK)
                {
                    if (jig.Finished) break; // Intro: termina el trazado con normalidad
                    ed.WriteMessage("\n[CONDUCTO] Trazado interrumpido; se conserva lo ya dibujado.");
                    break;
                }

                Point2d newVertex = new Point2d(jig.Result.X, jig.Result.Y);
                double turnMagDeg = jig.ResultTurnDeg;

                using (Transaction tr = db.TransactionManager.StartTransaction())
                {
                    var bt = (BlockTable)tr.GetObject(db.BlockTableId, OpenMode.ForRead);
                    var ms = (BlockTableRecord)tr.GetObject(bt[BlockTableRecord.ModelSpace], OpenMode.ForWrite);

                    if (hasHeading && turnMagDeg > 1e-6)
                    {
                        double tlen = tipo == "Circular"
                            ? DrawingUtil.RadiusFactor * dim * Math.Tan(turnMagDeg * Math.PI / 180.0 / 2.0)
                            : DrawingUtil.RectElbowLegFactor * dim;

                        double angIn = heading;
                        double angOut = GeometryUtil.AngleTo(lastVertex, newVertex);

                        if (tlen > prevBoundary.GetDistanceTo(lastVertex))
                        {
                            ed.WriteMessage($"\n[CONDUCTO] Aviso: el tramo antes de un codo puede ser demasiado corto (necesita {tlen:0.0}).");
                            warnCount++;
                        }

                        Point2d p1 = GeometryUtil.Polar(lastVertex, angIn + Math.PI, tlen);
                        Point2d p2 = GeometryUtil.Polar(lastVertex, angOut, tlen);

                        if (DrawingUtil.DrawWallSegment(tr, ms, prevBoundary, p1, half)) nLegs++;
                        DrawingUtil.DrawAxisSegment(tr, db, ms, prevBoundary, p1, dim / 20.0);
                        DrawingUtil.AddElbowDelimiter(tr, ms, p1, angIn, dim);
                        DrawingUtil.AddElbowDelimiter(tr, ms, p2, angOut, dim);
                        nElbows++;

                        prevBoundary = p2;
                    }

                    tr.Commit();
                }

                heading = GeometryUtil.AngleTo(lastVertex, newVertex);
                lastVertex = newVertex;
                hasHeading = true;
                pointCount++;
                ed.Regen();
            }

            if (pointCount == 0)
            {
                ed.WriteMessage("\n[CONDUCTO] El recorrido necesita al menos dos puntos. No se ha creado nada.");
                return;
            }

            using (Transaction tr = db.TransactionManager.StartTransaction())
            {
                var bt = (BlockTable)tr.GetObject(db.BlockTableId, OpenMode.ForRead);
                var ms = (BlockTableRecord)tr.GetObject(bt[BlockTableRecord.ModelSpace], OpenMode.ForWrite);

                if (DrawingUtil.DrawWallSegment(tr, ms, prevBoundary, lastVertex, half)) nLegs++;
                DrawingUtil.DrawAxisSegment(tr, db, ms, prevBoundary, lastVertex, dim / 20.0);

                tr.Commit();
            }

            ed.Regen();
            ed.WriteMessage(
                $"\n[CONDUCTO] Conducto {tipo} creado: {nLegs} tramo(s) de pared y {nElbows} codo(s) delimitado(s)" +
                (warnCount > 0 ? $", {warnCount} con aviso de tramo corto" : "") +
                ". Eje central conservado.");
        }
    }

    /// <summary>
    /// CONDUCTORAMAL - inserta una union en T (un ramal) o en cruz (dos ramales
    /// opuestos) sobre un conducto principal YA EXISTENTE (dos paredes paralelas
    /// seleccionadas). El conducto principal no se modifica: solo se lee para saber
    /// por donde pasa. Cada ramal se recorta automaticamente donde alcanza la pared
    /// del conducto principal mas cercana a el. Solo valido sobre un tramo RECTO del
    /// conducto principal, no sobre un codo.
    /// </summary>
    public class RamalCommands
    {
        [CommandMethod("CONDUCTORAMAL")]
        public void ConductoRamal()
        {
            Document doc = AcApp.DocumentManager.MdiActiveDocument;
            Database db = doc.Database;
            Editor ed = doc.Editor;

            var pko = new PromptKeywordOptions("\n[CONDUCTORAMAL] Tipo de union [Te/Cruz] <Te>: ") { AllowNone = true };
            pko.Keywords.Add("Te");
            pko.Keywords.Add("Cruz");
            pko.Keywords.Default = "Te";
            var pkr = ed.GetKeywords(pko);
            if (pkr.Status == PromptStatus.Cancel) { ed.WriteMessage("\n[CONDUCTORAMAL] Cancelado."); return; }
            string tipoUnion = (pkr.Status == PromptStatus.OK && !string.IsNullOrEmpty(pkr.StringResult)) ? pkr.StringResult : "Te";

            var per1 = ed.GetEntity("\n[CONDUCTORAMAL] Selecciona la primera pared del conducto principal: ");
            if (per1.Status != PromptStatus.OK) { ed.WriteMessage("\n[CONDUCTORAMAL] Cancelado."); return; }
            var per2 = ed.GetEntity("\n[CONDUCTORAMAL] Selecciona la segunda pared (la opuesta): ");
            if (per2.Status != PromptStatus.OK) { ed.WriteMessage("\n[CONDUCTORAMAL] Cancelado."); return; }

            var pctrRes = ed.GetPoint("\n[CONDUCTORAMAL] Punto aproximado de conexion sobre el conducto principal: ");
            if (pctrRes.Status != PromptStatus.OK) { ed.WriteMessage("\n[CONDUCTORAMAL] Cancelado."); return; }
            Point3d pctr = pctrRes.Value;

            using (Transaction tr = db.TransactionManager.StartTransaction())
            {
                var bt = (BlockTable)tr.GetObject(db.BlockTableId, OpenMode.ForRead);
                var ms = (BlockTableRecord)tr.GetObject(bt[BlockTableRecord.ModelSpace], OpenMode.ForWrite);

                var wall1 = (Curve)tr.GetObject(per1.ObjectId, OpenMode.ForRead);
                var wall2 = (Curve)tr.GetObject(per2.ObjectId, OpenMode.ForRead);

                Point3d p1_3d = wall1.GetClosestPointTo(pctr, false);
                Point3d p2_3d = wall2.GetClosestPointTo(pctr, false);
                var p1 = new Point2d(p1_3d.X, p1_3d.Y);
                var p2 = new Point2d(p2_3d.X, p2_3d.Y);
                var centerPt = new Point2d((p1.X + p2.X) / 2.0, (p1.Y + p2.Y) / 2.0);
                // p1-p2 es, en un tramo recto, perpendicular al eje del conducto
                // principal -sirve tal cual para comprobar si un ramal sale
                // perpendicular.
                double crossDir = GeometryUtil.AngleTo(p1, p2);

                int nBranches = tipoUnion == "Cruz" ? 2 : 1;
                Point2d far1 = default;

                for (int k = 1; k <= nBranches; k++)
                {
                    var pkoB = new PromptKeywordOptions($"\n[CONDUCTORAMAL] Tipo del ramal {k} [Circular/Rectangular] <Circular>: ") { AllowNone = true };
                    pkoB.Keywords.Add("Circular");
                    pkoB.Keywords.Add("Rectangular");
                    pkoB.Keywords.Default = "Circular";
                    var pkrB = ed.GetKeywords(pkoB);
                    if (pkrB.Status == PromptStatus.Cancel) { ed.WriteMessage("\n[CONDUCTORAMAL] Ramal cancelado."); tr.Commit(); return; }
                    string branchTipo = (pkrB.Status == PromptStatus.OK && !string.IsNullOrEmpty(pkrB.StringResult)) ? pkrB.StringResult : "Circular";
                    _ = branchTipo; // el tipo del ramal no cambia como se recorta, solo su dimension

                    var pdoB = new PromptDistanceOptions($"\n[CONDUCTORAMAL] Dimension del ramal {k} (diametro, o ancho en planta): ")
                    {
                        AllowNegative = false,
                        AllowZero = false,
                    };
                    var pdrB = ed.GetDistance(pdoB);
                    if (pdrB.Status != PromptStatus.OK) { ed.WriteMessage("\n[CONDUCTORAMAL] Ramal cancelado."); tr.Commit(); return; }
                    double branchDim = pdrB.Value;

                    Point2d farPt;
                    if (tipoUnion == "Cruz" && k == 2)
                    {
                        // El segundo ramal de una cruz sale automaticamente hacia el
                        // lado opuesto al primero, misma distancia.
                        farPt = new Point2d(2.0 * centerPt.X - far1.X, 2.0 * centerPt.Y - far1.Y);
                    }
                    else
                    {
                        var ppoB = new PromptPointOptions($"\n[CONDUCTORAMAL] Punto final del ramal {k}: ")
                        {
                            UseBasePoint = true,
                            BasePoint = new Point3d(centerPt.X, centerPt.Y, 0),
                        };
                        var pprB = ed.GetPoint(ppoB);
                        if (pprB.Status != PromptStatus.OK) { ed.WriteMessage("\n[CONDUCTORAMAL] Ramal cancelado."); tr.Commit(); return; }
                        farPt = new Point2d(pprB.Value.X, pprB.Value.Y);
                        far1 = farPt;
                    }

                    double branchDirAng = GeometryUtil.AngleTo(centerPt, farPt);

                    double dev1 = Math.Abs(GeometryUtil.NormPi(branchDirAng - crossDir));
                    double dev2 = Math.Abs(GeometryUtil.NormPi(branchDirAng - (crossDir + Math.PI)));
                    double defl = Math.Min(dev1, dev2) * 180.0 / Math.PI;
                    if (defl > 2.0)
                        ed.WriteMessage($"\n[CONDUCTORAMAL] Aviso: el ramal {k} no sale perpendicular al conducto principal ({defl:0.0} grados de desviacion).");

                    // La pared del conducto principal mas cercana al ramal: contra
                    // esa se recortan sus dos paredes.
                    Point2d nearPt;
                    double tanDir;
                    if (farPt.GetDistanceTo(p1) < farPt.GetDistanceTo(p2))
                    {
                        nearPt = p1;
                        tanDir = TangentAngleAt(wall1, p1_3d);
                    }
                    else
                    {
                        nearPt = p2;
                        tanDir = TangentAngleAt(wall2, p2_3d);
                    }

                    Polyline branchCl = DrawingUtil.BuildPolyline(new List<Point2d> { centerPt, farPt });
                    ms.AppendEntity(branchCl);
                    tr.AddNewlyCreatedDBObject(branchCl, true);

                    var wallEnts = new List<Curve>();
                    wallEnts.AddRange(DrawingUtil.OffsetPolyline(tr, ms, branchCl, branchDim / 2.0));
                    wallEnts.AddRange(DrawingUtil.OffsetPolyline(tr, ms, branchCl, -branchDim / 2.0));

                    foreach (Curve w in wallEnts)
                    {
                        var wStart = new Point2d(w.StartPoint.X, w.StartPoint.Y);
                        var wEnd = new Point2d(w.EndPoint.X, w.EndPoint.Y);
                        Point2d wNear, wFar;
                        if (wStart.GetDistanceTo(centerPt) < wEnd.GetDistanceTo(centerPt)) { wNear = wStart; wFar = wEnd; }
                        else { wNear = wEnd; wFar = wStart; }

                        Point2d? ip = GeometryUtil.LineIntersect(nearPt, tanDir, wNear, branchDirAng);
                        if (ip != null)
                        {
                            w.Erase();
                            Polyline trimmed = DrawingUtil.BuildPolyline(new List<Point2d> { ip.Value, wFar });
                            ms.AppendEntity(trimmed);
                            tr.AddNewlyCreatedDBObject(trimmed, true);
                        }
                        else
                        {
                            ed.WriteMessage($"\n[CONDUCTORAMAL] Aviso: no se ha podido recortar una pared del ramal {k} contra el conducto principal; se deja sin recortar.");
                        }
                    }

                    DrawingUtil.MarkAsAxis(tr, db, branchCl, branchDim / 20.0);
                }

                tr.Commit();
            }

            ed.Regen();
            ed.WriteMessage("\n[CONDUCTORAMAL] Union creada. El conducto principal no se ha modificado.");
        }

        /// <summary>Direccion (angulo, radianes) tangente a la curva en un punto que ya esta sobre ella.</summary>
        private static double TangentAngleAt(Curve curve, Point3d pointOnCurve)
        {
            Vector3d deriv = curve.GetFirstDerivative(pointOnCurve);
            return Math.Atan2(deriv.Y, deriv.X);
        }
    }
}
