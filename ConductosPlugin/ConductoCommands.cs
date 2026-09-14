using System;
using System.Collections.Generic;
using System.Linq;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.EditorInput;
using Autodesk.AutoCAD.Geometry;
using Autodesk.AutoCAD.Runtime;
using AcApp = Autodesk.AutoCAD.ApplicationServices.Core.Application;

namespace ConductosPlugin
{
    /// <summary>
    /// CONDUCTO - traza un recorrido de conducto (circular o rectangular) a doble
    /// linea y a escala real, insertando en cada cambio de direccion un BLOQUE de
    /// codo normalizado (con atributos DIAM/ANCHO, ANG, TIPO), reutilizado entre
    /// codos con el mismo tipo/dimension/angulo. El eje trazado se conserva como
    /// referencia, en gris con linea CENTER, siguiendo la forma real del conducto
    /// (con el arco de cada codo circular, o pasando por el vertice en rectangular).
    /// Un codo con un angulo que no sea uno de los normalizados hace que el
    /// recorrido ENTERO se rechace, sin crear nada, antes de dibujar.
    /// </summary>
    public class ConductoCommands
    {
        [CommandMethod("CONDUCTO")]
        public void Conducto()
        {
            Document doc = AcApp.DocumentManager.MdiActiveDocument;
            Database db = doc.Database;
            Editor ed = doc.Editor;

            var pko = new PromptKeywordOptions("\n[CONDUCTO] Tipo de conducto [Circular/Rectangular] <Circular>: ")
            {
                AllowNone = true,
            };
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

            // Para rectangular, el unico codo que se genera es a escuadra (90), asi
            // que se activa ORTHO mientras se traza para que el angulo salga
            // normalizado solo (se puede saltar puntualmente con MAYUS, y se
            // restaura el ORTHO que hubiera al terminar). Para circular no se fuerza
            // -los codos normalizados admitidos (45/30/22.5/15) no son solo 90-.
            object oldOrtho = AcApp.GetSystemVariable("ORTHOMODE");
            if (tipo == "Rectangular") AcApp.SetSystemVariable("ORTHOMODE", 1);

            var pts3d = new List<Point3d>();
            var pprFirst = ed.GetPoint(new PromptPointOptions("\n[CONDUCTO] Punto inicial del recorrido: "));
            if (pprFirst.Status != PromptStatus.OK)
            {
                AcApp.SetSystemVariable("ORTHOMODE", oldOrtho);
                ed.WriteMessage("\n[CONDUCTO] Cancelado.");
                return;
            }
            pts3d.Add(pprFirst.Value);

            while (true)
            {
                var ppo = new PromptPointOptions("\n[CONDUCTO] Punto siguiente, solo tramos rectos (Intro para terminar): ")
                {
                    UseBasePoint = true,
                    BasePoint = pts3d[pts3d.Count - 1],
                    AllowNone = true,
                };
                var ppr = ed.GetPoint(ppo);
                if (ppr.Status != PromptStatus.OK) break; // Intro (None) o Escape: termina el trazado
                pts3d.Add(ppr.Value);
            }

            AcApp.SetSystemVariable("ORTHOMODE", oldOrtho);

            if (pts3d.Count < 2)
            {
                ed.WriteMessage("\n[CONDUCTO] El recorrido necesita al menos dos puntos. Cancelado.");
                return;
            }

            var rawPts = pts3d.Select(p => new Point2d(p.X, p.Y)).ToList();
            List<Point2d> pts = GeometryUtil.SimplifyPoints(rawPts, 1e-6);
            int n = pts.Count;

            // Validacion de angulos ANTES de crear nada: un codo con un angulo que no
            // sea uno de los normalizados no llega a dibujarse -se rechaza el
            // recorrido ENTERO y hay que corregirlo y volver a ejecutar CONDUCTO-.
            var badVertices = new List<(int idx, double ang)>();
            for (int i = 1; i < n - 1; i++)
            {
                double defl = GeometryUtil.DeflectionDeg(pts[i - 1], pts[i], pts[i + 1]);
                if (tipo == "Circular")
                {
                    var (_, diff) = GeometryUtil.NearestStandardAngle(defl);
                    if (diff > GeometryUtil.AngleWarnTolDeg) badVertices.Add((i + 1, defl));
                }
                else if (Math.Abs(defl - 90.0) > GeometryUtil.AngleWarnTolDeg)
                {
                    badVertices.Add((i + 1, defl));
                }
            }
            if (badVertices.Count > 0)
            {
                string validos = tipo == "Circular"
                    ? $" (validos: {string.Join(", ", GeometryUtil.StandardAnglesDeg.Select(a => a.ToString("0.#")))})"
                    : " (solo se admite 90 en rectangular)";
                ed.WriteMessage($"\n[CONDUCTO] Recorrido RECHAZADO: hay codo(s) sin angulo normalizado{validos}:");
                foreach (var bv in badVertices) ed.WriteMessage($"\n  - vertice {bv.idx}: {bv.ang:0.0} grados");
                ed.WriteMessage("\n[CONDUCTO] No se ha creado ningun tramo ni codo. Corrige el recorrido (usa ORTHO/polar) y vuelve a ejecutar CONDUCTO.");
                return;
            }

            int nSegs = 0, nElbows = 0, warnCount = 0;

            using (Transaction tr = db.TransactionManager.StartTransaction())
            {
                var bt = (BlockTable)tr.GetObject(db.BlockTableId, OpenMode.ForRead);
                var ms = (BlockTableRecord)tr.GetObject(bt[BlockTableRecord.ModelSpace], OpenMode.ForWrite);

                // "boundaries": inicio/fin del recorrido y, por cada codo interior,
                // sus dos puntos de conexion (tangencia en circular, union a inglete
                // en rectangular) con los tramos rectos vecinos -en vez del vertice
                // en bruto-.
                var boundaries = new List<Point2d> { pts[0] };

                // "axisData": el eje de referencia SI sigue la forma real del
                // conducto en cada codo (arco/bulge en circular, o pasando por el
                // vertice real en rectangular), a diferencia de "boundaries".
                var axisData = new List<(Point2d pt, double bulge)> { (pts[0], 0.0) };

                for (int i = 1; i < n - 1; i++)
                {
                    Point2d a = pts[i - 1], v = pts[i], c = pts[i + 1];
                    double defl = GeometryUtil.DeflectionDeg(a, v, c);

                    double tlen = tipo == "Circular"
                        ? DrawingUtil.RadiusFactor * dim * Math.Tan(defl * Math.PI / 180.0 / 2.0)
                        : DrawingUtil.RectElbowLegFactor * dim;

                    if (tlen > a.GetDistanceTo(v) || tlen > v.GetDistanceTo(c))
                    {
                        ed.WriteMessage($"\n[CONDUCTO] Aviso: el tramo junto al vertice {i + 1} puede ser demasiado corto para el codo (necesita {tlen:0.0} a cada lado).");
                        warnCount++;
                    }

                    Point2d p1 = GeometryUtil.Polar(v, GeometryUtil.AngleTo(v, a), tlen);
                    Point2d p2 = GeometryUtil.Polar(v, GeometryUtil.AngleTo(v, c), tlen);
                    boundaries.Add(p1);

                    double angIn = GeometryUtil.AngleTo(a, v);
                    double angOut = GeometryUtil.AngleTo(v, c);
                    var inDir = new Vector2d(Math.Cos(angIn), Math.Sin(angIn));
                    var outDir = new Vector2d(Math.Cos(angOut), Math.Sin(angOut));
                    double crossSign = GeometryUtil.Cross2D(inDir, outDir);
                    bool isLeft = crossSign >= 0.0;

                    if (tipo == "Circular")
                    {
                        double bulge = Math.Tan(defl * Math.PI / 180.0 / 4.0);
                        if (!isLeft) bulge = -bulge;
                        axisData.Add((p1, bulge));
                        axisData.Add((p2, 0.0));
                    }
                    else
                    {
                        axisData.Add((p1, 0.0));
                        axisData.Add((v, 0.0));
                        axisData.Add((p2, 0.0));
                    }

                    ObjectId blockId = DrawingUtil.EnsureElbowBlock(tr, db, tipo, dim, defl);
                    DrawingUtil.InsertElbow(tr, ms, blockId, p1, angIn, isLeft);
                    nElbows++;

                    boundaries.Add(p2);
                }

                boundaries.Add(pts[n - 1]);
                axisData.Add((pts[n - 1], 0.0));

                Polyline axisPl = DrawingUtil.BuildPolylineWithBulge(axisData);
                ms.AppendEntity(axisPl);
                tr.AddNewlyCreatedDBObject(axisPl, true);
                DrawingUtil.MarkAsAxis(tr, db, axisPl, dim / 20.0);

                // Tramos rectos de pared: los pares que EMPIEZAN en indice PAR de
                // "boundaries" (0,2,4...) son tramo recto; los que empiezan en indice
                // IMPAR son el hueco que ya ocupa el bloque del codo -ahi no se
                // dibuja nada, o saldria una pared diagonal atravesando el codo-.
                for (int i = 0; i < boundaries.Count - 1; i += 2)
                {
                    Point2d a = boundaries[i], v = boundaries[i + 1];
                    if (a.GetDistanceTo(v) <= 1e-6) continue;

                    Polyline segPl = DrawingUtil.BuildPolyline(new List<Point2d> { a, v });
                    ms.AppendEntity(segPl);
                    tr.AddNewlyCreatedDBObject(segPl, true);

                    List<Curve> off1 = DrawingUtil.OffsetPolyline(tr, ms, segPl, half);
                    List<Curve> off2 = DrawingUtil.OffsetPolyline(tr, ms, segPl, -half);
                    segPl.Erase();

                    if (off1.Count > 0 && off2.Count > 0) nSegs++;
                    else ed.WriteMessage("\n[CONDUCTO] Aviso: fallo al generar un tramo recto de pared.");
                }

                tr.Commit();
            }

            ed.Regen();
            ed.WriteMessage(
                $"\n[CONDUCTO] Conducto {tipo} creado: {nSegs} tramo(s) recto(s) y {nElbows} codo(s) normalizado(s) insertado(s) como bloque" +
                (warnCount > 0 ? $", {warnCount} con aviso de tramo corto" : "") +
                ". Eje central conservado.");
        }
    }
}
