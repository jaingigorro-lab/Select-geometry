using System;
using System.Collections.Generic;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.EditorInput;
using Autodesk.AutoCAD.Geometry;
using Autodesk.AutoCAD.Runtime;
using AcApp = Autodesk.AutoCAD.ApplicationServices.Core.Application;

namespace ConductosPlugin
{
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
