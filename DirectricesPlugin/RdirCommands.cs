using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.EditorInput;
using Autodesk.AutoCAD.Geometry;
using Autodesk.AutoCAD.Runtime;
using AcApp = Autodesk.AutoCAD.ApplicationServices.Core.Application;

[assembly: CommandClass(typeof(DirectricesPlugin.RdirCommands))]

namespace DirectricesPlugin
{
    // ==========================================================
    // RDIR - Reconstruye una directriz EXPLOTADA (texto + lineas/polilineas +
    // flecha sueltas) como una directriz multiple (MLEADER) real.
    //
    // A diferencia de RDIRX.lsp, no adivina nada: se reconstruye UNA directriz
    // por seleccion, con EXACTAMENTE las piezas que el usuario selecciona:
    //   - un unico texto (TEXT o MTEXT),
    //   - todas las lineas/polilineas seleccionadas, unidas en una sola cadena
    //     por sus extremos mas proximos, sin anadir ni quitar ninguna,
    //   - la flecha seleccionada (SOLID o bloque), si la hay, de la que se toma
    //     la punta, el tamano y, si es un bloque, el mismo simbolo de flecha.
    // Despues vuelve a pedir la siguiente directriz, hasta pulsar Intro.
    //
    // Orientacion del texto:
    //   - Original (por defecto): el texto nuevo conserva el plano y el angulo
    //     del texto original, y se coloca en el mismo sitio.
    //   - Scp: el texto queda horizontal en el SCP actual.
    //
    // Toda la directriz se construye en un sistema local (X = direccion del
    // texto, Z = normal del texto o del SCP) sobre el plano XY universal, con
    // el texto a 0 grados, y al final se lleva a su sitio real con un unico
    // TransformBy: asi la orientacion no depende del SCU ni del estilo.
    // ==========================================================
    public class RdirCommands
    {
        private static bool _keepOriginalAngle = true;

        [CommandMethod("RDIR", CommandFlags.Modal)]
        public void Rdir()
        {
            Document doc = AcApp.DocumentManager.MdiActiveDocument;
            if (doc == null) return;
            Database db = doc.Database;
            Editor ed = doc.Editor;

            string def = _keepOriginalAngle ? "Original" : "Scp";
            var pko = new PromptKeywordOptions($"\nRDIR: orientacion del texto [Original/Scp] <{def}>: ")
            {
                AllowNone = true,
                AppendKeywordsToMessage = false,
            };
            pko.Keywords.Add("Original");
            pko.Keywords.Add("Scp");
            pko.Keywords.Default = def;
            PromptResult pkr = ed.GetKeywords(pko);
            if (pkr.Status == PromptStatus.Cancel) return;
            if (pkr.Status == PromptStatus.OK && !string.IsNullOrEmpty(pkr.StringResult))
                _keepOriginalAngle = pkr.StringResult == "Original";

            var filter = new SelectionFilter(new[]
            {
                new TypedValue((int)DxfCode.Start, "TEXT,MTEXT,LINE,LWPOLYLINE,POLYLINE,LEADER,SOLID,INSERT"),
            });

            int done = 0;
            while (true)
            {
                var pso = new PromptSelectionOptions
                {
                    MessageForAdding = "\nRDIR: selecciona las piezas de UNA directriz (su texto, sus lineas y su flecha), o Intro para terminar: ",
                    RejectObjectsOnLockedLayers = true,
                };
                PromptSelectionResult psr = ed.GetSelection(pso, filter);
                if (psr.Status != PromptStatus.OK) break;

                try
                {
                    if (Rebuild(db, ed, psr.Value.GetObjectIds(), _keepOriginalAngle))
                    {
                        done++;
                        ed.WriteMessage("\nRDIR: directriz reconstruida.");
                    }
                }
                catch (System.Exception ex)
                {
                    ed.WriteMessage($"\nRDIR: no se pudo reconstruir esta directriz ({ex.Message}). No se ha cambiado nada.");
                }
            }

            ed.WriteMessage($"\nRDIR: {done} directriz(es) reconstruida(s). U deshace todo el comando.");
        }

        /// <summary>Rectangulo en coordenadas locales (plano XY).</summary>
        private struct Box
        {
            public double MinX, MinY, MaxX, MaxY;
            public Box(IEnumerable<Point3d> pts)
            {
                MinX = MinY = double.MaxValue;
                MaxX = MaxY = double.MinValue;
                foreach (Point3d p in pts)
                {
                    MinX = Math.Min(MinX, p.X); MaxX = Math.Max(MaxX, p.X);
                    MinY = Math.Min(MinY, p.Y); MaxY = Math.Max(MaxY, p.Y);
                }
            }
            public double Width => MaxX - MinX;
            public double DistanceTo(Point2d p)
            {
                double dx = Math.Max(0.0, Math.Max(MinX - p.X, p.X - MaxX));
                double dy = Math.Max(0.0, Math.Max(MinY - p.Y, p.Y - MaxY));
                return Math.Sqrt(dx * dx + dy * dy);
            }
        }

        private static bool Rebuild(Database db, Editor ed, ObjectId[] ids, bool keepAngle)
        {
            using (Transaction tr = db.TransactionManager.StartTransaction())
            {
                // ---------- 1. Clasificar exactamente lo seleccionado ----------
                Entity textEnt = null;
                var curves = new List<Curve>();
                var arrows = new List<Entity>();
                foreach (ObjectId id in ids)
                {
                    var ent = (Entity)tr.GetObject(id, OpenMode.ForWrite);
                    if (ent is DBText || ent is MText)
                    {
                        if (textEnt != null)
                        {
                            ed.WriteMessage("\nRDIR: has seleccionado mas de un texto. Selecciona solo las piezas de una directriz.");
                            return false;
                        }
                        textEnt = ent;
                    }
                    else if (ent is Curve c) curves.Add(c);
                    else arrows.Add(ent);
                }
                if (textEnt == null || curves.Count == 0)
                {
                    ed.WriteMessage("\nRDIR: la seleccion debe incluir un texto y al menos una linea.");
                    return false;
                }

                // ---------- 2. Datos del texto original ----------
                string contents;
                double height, mtextWidth = 0.0;
                ObjectId styleId;
                Vector3d textNormal, textXDir;
                Point3d textOrigin;
                if (textEnt is DBText dt)
                {
                    contents = DbTextToMText(dt.TextString);
                    if (Math.Abs(dt.WidthFactor - 1.0) > 1e-6)
                        contents = "{\\W" + dt.WidthFactor.ToString("0.####", CultureInfo.InvariantCulture) + ";" + contents + "}";
                    height = dt.Height;
                    styleId = dt.TextStyleId;
                    textNormal = dt.Normal;
                    textXDir = Vector3d.XAxis.RotateBy(dt.Rotation, Vector3d.ZAxis).TransformBy(Matrix3d.PlaneToWorld(dt.Normal));
                    textOrigin = dt.Position;
                }
                else
                {
                    var omt = (MText)textEnt;
                    contents = omt.Contents;
                    height = omt.TextHeight;
                    styleId = omt.TextStyleId;
                    textNormal = omt.Normal;
                    textXDir = omt.Direction;
                    textOrigin = omt.Location;
                    mtextWidth = omt.Width;
                }

                // ---------- 3. Sistema local ----------
                Vector3d zAxis, xAxis;
                if (keepAngle)
                {
                    zAxis = textNormal.GetNormal();
                    xAxis = textXDir;
                }
                else
                {
                    CoordinateSystem3d ucs = ed.CurrentUserCoordinateSystem.CoordinateSystem3d;
                    zAxis = ucs.Zaxis.GetNormal();
                    xAxis = ucs.Xaxis;
                }
                xAxis = (xAxis - zAxis * xAxis.DotProduct(zAxis)).GetNormal();
                Vector3d yAxis = zAxis.CrossProduct(xAxis).GetNormal();
                Matrix3d toWorld = Matrix3d.AlignCoordinateSystem(
                    Point3d.Origin, Vector3d.XAxis, Vector3d.YAxis, Vector3d.ZAxis,
                    textOrigin, xAxis, yAxis, zAxis);
                Matrix3d toLocal = toWorld.Inverse();

                // Rectangulo del texto en el sistema local (el texto original se
                // transforma aqui mismo: se borra al final de todos modos).
                textEnt.TransformBy(toLocal);
                Box textBox;
                if (textEnt is MText lmt)
                    textBox = new Box(lmt.GetBoundingPoints().Cast<Point3d>());
                else
                {
                    Extents3d ext = textEnt.GeometricExtents;
                    textBox = new Box(new[] { ext.MinPoint, ext.MaxPoint });
                }

                // ---------- 4. Cadena con EXACTAMENTE las lineas seleccionadas ----------
                var pieces = curves.Select(GetVertices).Where(p => p.Count >= 2).ToList();
                if (pieces.Count == 0)
                {
                    ed.WriteMessage("\nRDIR: las lineas seleccionadas no tienen longitud.");
                    return false;
                }
                List<Point2d> pts = JoinPieces(pieces)
                    .Select(p => p.TransformBy(toLocal))
                    .Select(p => new Point2d(p.X, p.Y))
                    .ToList();
                pts = Simplify(pts);
                if (pts.Count < 2)
                {
                    ed.WriteMessage("\nRDIR: las lineas seleccionadas no forman una directriz.");
                    return false;
                }
                // pts va del apoyo (extremo junto al texto) a la punta
                if (textBox.DistanceTo(pts[pts.Count - 1]) < textBox.DistanceTo(pts[0])) pts.Reverse();

                // ---------- 5. Flecha seleccionada: punta, tamano y simbolo ----------
                double? arrowSize = null;
                ObjectId? arrowBlock = null;
                Point2d prev = pts[pts.Count - 2];
                Point2d tip = pts[pts.Count - 1];
                foreach (Entity a in arrows)
                {
                    if (a is Solid so)
                    {
                        var v = new List<Point2d>();
                        for (short i = 0; i < 4; i++)
                        {
                            Point3d w = so.GetPointAt(i).TransformBy(toLocal);
                            var q = new Point2d(w.X, w.Y);
                            if (!v.Any(x => x.GetDistanceTo(q) < 1e-9)) v.Add(q);
                        }
                        if (v.Count < 3) continue;
                        Point2d sTip = v.OrderByDescending(x => x.GetDistanceTo(prev)).First();
                        var baseV = v.Where(x => x.GetDistanceTo(sTip) > 1e-9).ToList();
                        var mid = new Point2d(baseV.Average(x => x.X), baseV.Average(x => x.Y));
                        arrowSize = sTip.GetDistanceTo(mid);
                        if (sTip.GetDistanceTo(prev) > tip.GetDistanceTo(prev)) tip = sTip;
                    }
                    else if (a is BlockReference br)
                    {
                        Point3d w = br.Position.TransformBy(toLocal);
                        var q = new Point2d(w.X, w.Y);
                        arrowSize = Math.Abs(br.ScaleFactors.X);
                        arrowBlock = br.IsDynamicBlock ? br.DynamicBlockTableRecord : br.BlockTableRecord;
                        if (q.GetDistanceTo(prev) > tip.GetDistanceTo(prev)) tip = q;
                    }
                }
                pts[pts.Count - 1] = tip;

                // ---------- 6. Rellano: tramo horizontal junto al texto ----------
                bool dogleg = false, underline = false;
                double doglegLength = 0.0, doglegDir = 1.0;
                if (pts.Count >= 3)
                {
                    Point2d land = pts[0], knee = pts[1];
                    double dx = land.X - knee.X, dy = land.Y - knee.Y;
                    if (Math.Abs(dx) > 1e-9 && Math.Abs(dy) <= 0.1 * Math.Abs(dx))
                    {
                        dogleg = true;
                        doglegDir = dx > 0 ? 1.0 : -1.0;
                        double segMin = Math.Min(land.X, knee.X), segMax = Math.Max(land.X, knee.X);
                        double overlap = Math.Min(segMax, textBox.MaxX) - Math.Max(segMin, textBox.MinX);
                        double lineY = 0.5 * (land.Y + knee.Y);
                        // texto escrito ENCIMA de la raya -> texto subrayado
                        underline = overlap > 0.5 * textBox.Width && lineY <= textBox.MinY + 0.5 * height;
                        doglegLength = underline
                            ? Math.Max(0.0, doglegDir > 0 ? textBox.MinX - knee.X : knee.X - textBox.MaxX)
                            : Math.Abs(dx);
                        pts.RemoveAt(0);
                    }
                }

                // ---------- 7. Crear el MLEADER en el sistema local ----------
                var owner = (BlockTableRecord)tr.GetObject(textEnt.BlockId, OpenMode.ForWrite);
                var ml = new MLeader();
                ml.SetDatabaseDefaults(db);
                if (!db.MLeaderstyle.IsNull) ml.MLeaderStyle = db.MLeaderstyle;
                ml.Annotative = AnnotativeStates.False;

                // Todo en unidades reales del dibujo (escala 1), para que la altura
                // del texto sea exactamente la del original.
                double styleScale = ml.Scale > 0 ? ml.Scale : 1.0;
                double styleArrow = ml.ArrowSize * styleScale;
                double gap = ml.LandingGap * styleScale;
                ml.Scale = 1.0;
                ml.ContentType = ContentType.MTextContent;
                ml.TextStyleId = styleId;
                ml.TextHeight = height;
                ml.TextAngleType = TextAngleType.InsertAngle;
                ml.ArrowSize = arrowSize ?? styleArrow;
                if (arrowBlock.HasValue) ml.ArrowSymbolId = arrowBlock.Value;
                ml.LandingGap = gap;
                ml.Layer = textEnt.Layer;
                ml.Color = textEnt.Color;

                var mt = new MText();
                mt.SetDatabaseDefaults(db);
                mt.Contents = contents;
                mt.TextStyleId = styleId;
                mt.TextHeight = height;
                mt.Width = mtextWidth;
                mt.Attachment = AttachmentPoint.TopLeft;
                mt.Location = new Point3d(textBox.MinX, textBox.MaxY, 0.0);
                mt.Rotation = 0.0;
                ml.MText = mt;

                // pts[0] = conexion con el texto ... pts[n-1] = punta de flecha
                int lineIdx = ml.AddLeaderLine(new Point3d(pts[0].X, pts[0].Y, 0.0));
                for (int i = 1; i < pts.Count; i++)
                    ml.AddFirstVertex(lineIdx, new Point3d(pts[i].X, pts[i].Y, 0.0));

                int leaderIdx = ml.GetLeaderIndex(lineIdx);
                if (dogleg)
                {
                    ml.EnableLanding = true;
                    ml.EnableDogleg = true;
                    ml.SetDogleg(leaderIdx, new Vector3d(doglegDir, 0.0, 0.0));
                    ml.DoglegLength = doglegLength;
                    if (underline)
                    {
                        ml.SetTextAttachmentType(TextAttachmentType.AttachmentAllLine, LeaderDirectionType.LeftLeader);
                        ml.SetTextAttachmentType(TextAttachmentType.AttachmentAllLine, LeaderDirectionType.RightLeader);
                    }
                }
                else
                {
                    ml.EnableDogleg = false;
                    ml.EnableLanding = false;
                }

                owner.AppendEntity(ml);
                tr.AddNewlyCreatedDBObject(ml, true);

                // Texto en el mismo sitio que el original (esquina superior izquierda)
                PlaceText(ml, textBox);

                // ---------- 8. Llevar el MLEADER a su sitio real ----------
                ml.TransformBy(toWorld);

                // ---------- 9. Borrar las piezas sueltas ----------
                textEnt.Erase();
                foreach (Curve c in curves) c.Erase();
                foreach (Entity a in arrows) a.Erase();

                tr.Commit();
                return true;
            }
        }

        /// <summary>Mueve el texto del MLEADER para que su esquina superior izquierda
        /// coincida con la del texto original (en el sistema local).</summary>
        private static void PlaceText(MLeader ml, Box target)
        {
            for (int pass = 0; pass < 2; pass++)
            {
                Box cur;
                try
                {
                    using (MText m = ml.MText)
                        cur = new Box(m.GetBoundingPoints().Cast<Point3d>());
                }
                catch (System.Exception) { return; }

                var delta = new Vector3d(target.MinX - cur.MinX, target.MaxY - cur.MaxY, 0.0);
                if (delta.Length < 1e-9) return;
                ml.TextLocation = ml.TextLocation + delta;
            }
        }

        /// <summary>Vertices (WCS) de una linea, polilinea o LEADER, en orden.</summary>
        private static List<Point3d> GetVertices(Curve c)
        {
            var r = new List<Point3d>();
            if (c is Line ln)
            {
                r.Add(ln.StartPoint);
                r.Add(ln.EndPoint);
            }
            else if (c is Polyline pl)
            {
                for (int i = 0; i < pl.NumberOfVertices; i++) r.Add(pl.GetPoint3dAt(i));
                if (pl.Closed && pl.NumberOfVertices > 0) r.Add(pl.GetPoint3dAt(0));
            }
            else if (c is Leader ld)
            {
                for (int i = 0; i < ld.NumVertices; i++) r.Add(ld.VertexAt(i));
            }
            else
            {
                int n = (int)Math.Round(c.EndParam);
                for (int i = 0; i <= n; i++) r.Add(c.GetPointAtParameter(i));
            }
            var clean = new List<Point3d>();
            foreach (Point3d p in r)
                if (clean.Count == 0 || clean[clean.Count - 1].DistanceTo(p) > 1e-9) clean.Add(p);
            return clean;
        }

        /// <summary>Une TODAS las piezas en una sola cadena, enganchando cada vez la
        /// pieza cuyo extremo esta mas cerca de uno de los extremos de la cadena (si
        /// hay un hueco, se salva con un tramo recto; no se descarta ninguna pieza).</summary>
        private static List<Point3d> JoinPieces(List<List<Point3d>> pieces)
        {
            const double tol = 1e-6;
            var chain = new List<Point3d>(pieces[0]);
            var rest = pieces.Skip(1).ToList();
            while (rest.Count > 0)
            {
                double best = double.MaxValue;
                int bi = -1;
                bool atEnd = true, reverse = false;
                Point3d head = chain[0], tail = chain[chain.Count - 1];
                for (int i = 0; i < rest.Count; i++)
                {
                    List<Point3d> p = rest[i];
                    Point3d first = p[0], last = p[p.Count - 1];
                    // (distancia, enganchar al final de la cadena, invertir la pieza)
                    double[] d = { tail.DistanceTo(first), tail.DistanceTo(last), head.DistanceTo(last), head.DistanceTo(first) };
                    bool[] end = { true, true, false, false };
                    bool[] rev = { false, true, false, true };
                    for (int k = 0; k < 4; k++)
                        if (d[k] < best) { best = d[k]; bi = i; atEnd = end[k]; reverse = rev[k]; }
                }

                var piece = new List<Point3d>(rest[bi]);
                rest.RemoveAt(bi);
                if (reverse) piece.Reverse();
                if (atEnd)
                {
                    if (chain[chain.Count - 1].DistanceTo(piece[0]) < tol) piece.RemoveAt(0);
                    chain.AddRange(piece);
                }
                else
                {
                    if (piece[piece.Count - 1].DistanceTo(chain[0]) < tol) piece.RemoveAt(piece.Count - 1);
                    chain.InsertRange(0, piece);
                }
            }
            return chain;
        }

        /// <summary>Quita puntos repetidos y vertices intermedios alineados (dos
        /// tramos rectos seguidos en la misma direccion se quedan en uno).</summary>
        private static List<Point2d> Simplify(List<Point2d> pts)
        {
            var r = new List<Point2d>();
            foreach (Point2d p in pts)
                if (r.Count == 0 || r[r.Count - 1].GetDistanceTo(p) > 1e-9) r.Add(p);
            for (int i = r.Count - 2; i >= 1; i--)
            {
                Vector2d a = r[i] - r[i - 1], b = r[i + 1] - r[i];
                if (Math.Abs(a.X * b.Y - a.Y * b.X) <= 1e-9 * a.Length * b.Length && a.DotProduct(b) > 0)
                    r.RemoveAt(i);
            }
            return r;
        }

        /// <summary>Texto de un TEXT -> contenido de MTEXT: escapa \ { } y convierte
        /// los conmutadores %%u (subrayado) y %%o (sobrerrayado), que MTEXT no
        /// entiende; %%c, %%d, %%p y %%nnn se dejan tal cual (MTEXT si los entiende).</summary>
        private static string DbTextToMText(string s)
        {
            var sb = new StringBuilder();
            bool under = false, over = false;
            for (int i = 0; i < s.Length; i++)
            {
                char c = s[i];
                if (c == '%' && i + 2 < s.Length && s[i + 1] == '%')
                {
                    char k = char.ToLowerInvariant(s[i + 2]);
                    if (k == 'u') { under = !under; sb.Append(under ? "\\L" : "\\l"); i += 2; continue; }
                    if (k == 'o') { over = !over; sb.Append(over ? "\\O" : "\\o"); i += 2; continue; }
                }
                if (c == '\\') sb.Append("\\\\");
                else if (c == '{') sb.Append("\\{");
                else if (c == '}') sb.Append("\\}");
                else sb.Append(c);
            }
            return sb.ToString();
        }
    }
}
