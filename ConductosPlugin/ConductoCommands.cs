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
    /// linea y a escala real. Solo admite giros a escuadra (90 grados): un vertice con
    /// cualquier otro angulo hace que el recorrido ENTERO se rechace, sin crear nada,
    /// antes de dibujar. En cada codo no se inserta ningun bloque ni texto: las dos
    /// paredes siguen el recorrido con una esquina a inglete (offset de la polilinea
    /// completa) y se marcan solo con dos lineas delimitadoras perpendiculares -una
    /// donde empieza el codo y otra donde termina-, cruzando de pared a pared. El eje
    /// (linea CENTER gris) sigue el recorrido real, vertice a vertice.
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

            // Solo se admiten codos a escuadra (90 grados), asi que se activa ORTHO
            // mientras se traza para que el angulo salga normalizado solo (se puede
            // saltar puntualmente con MAYUS, y se restaura el ORTHO que hubiera al
            // terminar).
            object oldOrtho = AcApp.GetSystemVariable("ORTHOMODE");
            AcApp.SetSystemVariable("ORTHOMODE", 1);

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

            // Validacion de angulos ANTES de crear nada: solo se admiten codos a
            // escuadra (90 grados) -un vertice con cualquier otro angulo no llega a
            // dibujarse, se rechaza el recorrido ENTERO y hay que corregirlo y volver
            // a ejecutar CONDUCTO-.
            var badVertices = new List<(int idx, double ang)>();
            for (int i = 1; i < n - 1; i++)
            {
                double defl = GeometryUtil.DeflectionDeg(pts[i - 1], pts[i], pts[i + 1]);
                if (Math.Abs(defl - 90.0) > GeometryUtil.AngleWarnTolDeg) badVertices.Add((i + 1, defl));
            }
            if (badVertices.Count > 0)
            {
                ed.WriteMessage("\n[CONDUCTO] Recorrido RECHAZADO: hay codo(s) sin angulo a escuadra (solo se admiten 90 grados):");
                foreach (var bv in badVertices) ed.WriteMessage($"\n  - vertice {bv.idx}: {bv.ang:0.0} grados");
                ed.WriteMessage("\n[CONDUCTO] No se ha creado ningun tramo ni codo. Corrige el recorrido (usa ORTHO/polar) y vuelve a ejecutar CONDUCTO.");
                return;
            }

            int nElbows = 0, warnCount = 0;

            using (Transaction tr = db.TransactionManager.StartTransaction())
            {
                var bt = (BlockTable)tr.GetObject(db.BlockTableId, OpenMode.ForRead);
                var ms = (BlockTableRecord)tr.GetObject(bt[BlockTableRecord.ModelSpace], OpenMode.ForWrite);

                // Eje de referencia: el recorrido real, vertice a vertice (los giros
                // son todos a escuadra, asi que no hace falta arco/bulge).
                Polyline axisPl = DrawingUtil.BuildPolyline(pts);
                ms.AppendEntity(axisPl);
                tr.AddNewlyCreatedDBObject(axisPl, true);
                DrawingUtil.MarkAsAxis(tr, db, axisPl, dim / 20.0);

                // Las dos paredes del conducto: se desfasa la polilinea COMPLETA de una
                // sola vez (no tramo a tramo), asi cada esquina sale a inglete de forma
                // automatica -sin gaps ni piezas sueltas en los codos-.
                List<Curve> wallsOuter = DrawingUtil.OffsetPolyline(tr, ms, axisPl, half);
                List<Curve> wallsInner = DrawingUtil.OffsetPolyline(tr, ms, axisPl, -half);
                int nSegs = wallsOuter.Count + wallsInner.Count;
                if (wallsOuter.Count == 0 || wallsInner.Count == 0)
                    ed.WriteMessage("\n[CONDUCTO] Aviso: fallo al generar las paredes del conducto.");

                // En cada codo interior: dos lineas delimitadoras perpendiculares al
                // tramo -donde empieza y donde termina el codo-, sin bloque ni texto.
                double tlen = tipo == "Circular" ? DrawingUtil.RadiusFactor * dim : DrawingUtil.RectElbowLegFactor * dim;
                for (int i = 1; i < n - 1; i++)
                {
                    Point2d a = pts[i - 1], v = pts[i], c = pts[i + 1];

                    if (tlen > a.GetDistanceTo(v) || tlen > v.GetDistanceTo(c))
                    {
                        ed.WriteMessage($"\n[CONDUCTO] Aviso: el tramo junto al vertice {i + 1} puede ser demasiado corto para el codo (necesita {tlen:0.0} a cada lado).");
                        warnCount++;
                    }

                    double angIn = GeometryUtil.AngleTo(a, v);
                    double angOut = GeometryUtil.AngleTo(v, c);
                    Point2d p1 = GeometryUtil.Polar(v, GeometryUtil.AngleTo(v, a), tlen);
                    Point2d p2 = GeometryUtil.Polar(v, GeometryUtil.AngleTo(v, c), tlen);

                    DrawingUtil.AddElbowDelimiter(tr, ms, p1, angIn, dim);
                    DrawingUtil.AddElbowDelimiter(tr, ms, p2, angOut, dim);
                    nElbows++;
                }

                tr.Commit();

                ed.Regen();
                ed.WriteMessage(
                    $"\n[CONDUCTO] Conducto {tipo} creado: {nSegs} tramo(s) de pared y {nElbows} codo(s) a 90 grados delimitado(s)" +
                    (warnCount > 0 ? $", {warnCount} con aviso de tramo corto" : "") +
                    ". Eje central conservado.");
            }
        }
    }
}
