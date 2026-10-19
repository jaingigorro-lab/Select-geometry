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
    // flecha(s) sueltas) como una directriz multiple (MLEADER) real.
    //
    // A diferencia de RDIRX.lsp, no adivina nada: se reconstruye UNA directriz
    // por seleccion, con EXACTAMENTE las piezas que el usuario selecciona:
    //   - un unico texto (TEXT o MTEXT),
    //   - todas las lineas/polilineas seleccionadas, sin anadir ni quitar
    //     ninguna. Pueden formar una sola linea o RAMIFICARSE (varias flechas
    //     que salen del mismo codo): cada rama es una linea de directriz del
    //     mismo MLEADER, todas unidas en el codo, como en una directriz nativa,
    //   - las flechas seleccionadas (SOLID o bloque): cada una se asigna a la
    //     rama cuya punta tiene mas cerca, y de ella se toman la punta, el
    //     tamano y, si es un bloque, el mismo simbolo de flecha.
    // Despues vuelve a pedir la siguiente directriz, hasta pulsar Intro.
    //
    // Orientacion del texto, siempre en el plano del SCP actual:
    //   - Original (por defecto): el angulo con el que se VE el texto original.
    //   - Scp: horizontal en el SCP.
    // En los dos casos el texto queda LEGIBLE: si el angulo lo dejaria boca
    // abajo (leyendose de arriba abajo o de derecha a izquierda), se gira 180
    // grados. Asi da igual como estuviera guardado el texto original (girado
    // 180, reflejado por una simetria, con la normal invertida...).
    //
    // El MLEADER se construye directamente en su sitio, con su PLANO apoyado
    // en la direccion del texto (MLeader.SetPlane): el rellano y el subrayado
    // van en esa direccion, no en la horizontal del SCU. El texto se coloca
    // dejando que AutoCAD lo enganche a su rellano, y se desplaza hasta que el
    // final de las lineas de directriz cae EXACTAMENTE en el codo original.
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
                    MessageForAdding = "\nRDIR: selecciona las piezas de UNA directriz (su texto, sus lineas y sus flechas), o Intro para terminar: ",
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
            public double Height => MaxY - MinY;
            public double DistanceTo(Point2d p)
            {
                double dx = Math.Max(0.0, Math.Max(MinX - p.X, p.X - MaxX));
                double dy = Math.Max(0.0, Math.Max(MinY - p.Y, p.Y - MaxY));
                return Math.Sqrt(dx * dx + dy * dy);
            }
        }

        /// <summary>Tramo del grafo de lineas: de un nudo A a un nudo B.</summary>
        private sealed class Edge
        {
            public int A, B;
            public List<Point2d> Pts;
            public int Other(int n) => n == A ? B : A;
            public List<Point2d> From(int n)
            {
                var r = new List<Point2d>(Pts);
                if (n != A) r.Reverse();
                return r;
            }
        }

        /// <summary>Flecha seleccionada, en coordenadas locales.</summary>
        private sealed class Arrow
        {
            public Point2d Ref;          // punto para asignarla a una rama
            public bool IsSolid;
            public List<Point2d> Verts;  // vertices del SOLID
            public double Size;
            public ObjectId Symbol = ObjectId.Null;
        }

        private static bool Rebuild(Database db, Editor ed, ObjectId[] ids, bool keepAngle)
        {
            using (Transaction tr = db.TransactionManager.StartTransaction())
            {
                // ---------- 1. Clasificar exactamente lo seleccionado ----------
                Entity textEnt = null;
                var curves = new List<Curve>();
                var arrowEnts = new List<Entity>();
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
                    else arrowEnts.Add(ent);
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
                Vector3d textXDir;
                Point3d textOrigin;
                if (textEnt is DBText dt)
                {
                    contents = DbTextToMText(dt.TextString);
                    if (Math.Abs(dt.WidthFactor - 1.0) > 1e-6)
                        contents = "{\\W" + dt.WidthFactor.ToString("0.####", CultureInfo.InvariantCulture) + ";" + contents + "}";
                    height = dt.Height;
                    styleId = dt.TextStyleId;
                    textXDir = Vector3d.XAxis.RotateBy(dt.Rotation, Vector3d.ZAxis).TransformBy(Matrix3d.PlaneToWorld(dt.Normal));
                    textOrigin = dt.Position;
                }
                else
                {
                    var omt = (MText)textEnt;
                    contents = omt.Contents;
                    height = omt.TextHeight;
                    styleId = omt.TextStyleId;
                    textXDir = omt.Direction;
                    textOrigin = omt.Location;
                    mtextWidth = omt.Width;
                }

                // ---------- 3. Sistema del texto nuevo: plano del SCP, legible ----------
                CoordinateSystem3d ucs = ed.CurrentUserCoordinateSystem.CoordinateSystem3d;
                Vector3d zAxis = ucs.Zaxis.GetNormal();
                Vector3d ux = ucs.Xaxis.GetNormal(), uy = ucs.Yaxis.GetNormal();
                Vector3d xAxis = keepAngle ? textXDir : ux;
                xAxis = xAxis - zAxis * xAxis.DotProduct(zAxis);   // proyectado al plano del SCP
                xAxis = xAxis.Length > 1e-9 ? xAxis.GetNormal() : ux;
                double angInUcs = Math.Atan2(xAxis.DotProduct(uy), xAxis.DotProduct(ux));
                if (angInUcs > Math.PI / 2.0 + 1e-6 || angInUcs <= -Math.PI / 2.0 + 1e-6)
                    xAxis = -xAxis;                                // si no, se leeria boca abajo
                Vector3d yAxis = zAxis.CrossProduct(xAxis).GetNormal();
                Matrix3d toWorld = Matrix3d.AlignCoordinateSystem(
                    Point3d.Origin, Vector3d.XAxis, Vector3d.YAxis, Vector3d.ZAxis,
                    textOrigin, xAxis, yAxis, zAxis);
                Matrix3d toLocal = toWorld.Inverse();

                // Rectangulo que ocupaba el texto original, en ese sistema (el
                // original se transforma aqui mismo: se borra al final de todos modos).
                textEnt.TransformBy(toLocal);
                Box oldBox;
                if (textEnt is MText lmt)
                    oldBox = new Box(lmt.GetBoundingPoints().Cast<Point3d>());
                else
                {
                    Extents3d ext = textEnt.GeometricExtents;
                    oldBox = new Box(new[] { ext.MinPoint, ext.MaxPoint });
                }

                // ---------- 4. Lineas de directriz con EXACTAMENTE lo seleccionado ----------
                var pieces = curves
                    .Select(c => Simplify(GetVertices(c).Select(p => ToLocal2d(p, toLocal)).ToList()))
                    .Where(p => p.Count >= 2)
                    .ToList();
                if (pieces.Count == 0)
                {
                    ed.WriteMessage("\nRDIR: las lineas seleccionadas no tienen longitud.");
                    return false;
                }

                // trunk = del apoyo (junto al texto) al codo; lines = cada rama, de su
                // punta al apoyo (cabeza -> cola, como las quiere el MLEADER)
                List<Point2d> trunk;
                List<List<Point2d>> lines;
                double tol = Math.Max(1e-6, height * 1e-3);
                if (!BuildTree(pieces, oldBox, tol, out trunk, out lines))
                {
                    // las lineas no se tocan: se unen por los extremos mas proximos
                    ed.WriteMessage("\nRDIR: aviso, las lineas seleccionadas no se tocan; se unen por sus extremos mas cercanos.");
                    List<Point2d> chain = Simplify(JoinPieces(pieces));
                    if (oldBox.DistanceTo(chain[chain.Count - 1]) < oldBox.DistanceTo(chain[0])) chain.Reverse();
                    trunk = chain;
                    var single = new List<Point2d>(chain);
                    single.Reverse();
                    lines = new List<List<Point2d>> { single };
                }

                // ---------- 5. Rellano: primer tramo del tronco, paralelo al texto ----------
                // underline: la raya va a lo largo del texto (texto escrito sobre ella)
                // side: la raya acaba junto al texto (rellano normal)
                bool dogleg = false, underline = false;
                double doglegDir = 1.0, landLen = 0.0;
                Point2d land = trunk[0];
                Point2d tail = trunk[0];
                if (trunk.Count >= 2 && lines.All(l => l.Count >= 3))
                {
                    Point2d knee = trunk[1];
                    double dx = land.X - knee.X, dy = land.Y - knee.Y;
                    if (Math.Abs(dx) > 1e-9 && Math.Abs(dy) <= 0.1 * Math.Abs(dx))
                    {
                        dogleg = true;
                        doglegDir = dx > 0 ? 1.0 : -1.0;
                        landLen = Math.Abs(dx);
                        double segMin = Math.Min(land.X, knee.X), segMax = Math.Max(land.X, knee.X);
                        double overlap = Math.Min(segMax, oldBox.MaxX) - Math.Max(segMin, oldBox.MinX);
                        underline = overlap > 0.5 * oldBox.Width;
                        tail = knee;
                        foreach (List<Point2d> l in lines) l.RemoveAt(l.Count - 1);   // quitar el apoyo
                    }
                }

                // ---------- 6. Flechas: cada una a la rama de punta mas cercana ----------
                var arrows = arrowEnts.Select(a => ReadArrow(a, toLocal)).Where(a => a != null).ToList();
                var lineArrow = new Arrow[lines.Count];
                foreach (Arrow a in arrows)
                {
                    int best = -1;
                    double bestD = double.MaxValue;
                    for (int i = 0; i < lines.Count; i++)
                    {
                        double d = a.Ref.GetDistanceTo(lines[i][0]);
                        if (d < bestD) { bestD = d; best = i; }
                    }
                    if (best >= 0 && (lineArrow[best] == null || bestD < lineArrow[best].Ref.GetDistanceTo(lines[best][0])))
                        lineArrow[best] = a;
                }
                for (int i = 0; i < lines.Count; i++)
                {
                    Arrow a = lineArrow[i];
                    if (a == null) continue;
                    Point2d prev = lines[i][1];
                    Point2d tip = a.IsSolid ? a.Verts.OrderByDescending(x => x.GetDistanceTo(prev)).First() : a.Ref;
                    if (tip.GetDistanceTo(prev) > lines[i][0].GetDistanceTo(prev)) lines[i][0] = tip;
                }

                // ---------- 7. Crear el MLEADER directamente en su sitio ----------
                var owner = (BlockTableRecord)tr.GetObject(textEnt.BlockId, OpenMode.ForWrite);
                var ml = new MLeader();
                ml.SetDatabaseDefaults(db);
                if (!db.MLeaderstyle.IsNull) ml.MLeaderStyle = db.MLeaderstyle;
                ml.Annotative = AnnotativeStates.False;
                // plano del MLEADER con su eje X a lo largo del texto: el rellano y
                // el subrayado siguen esa direccion
                ml.SetPlane(new Plane(textOrigin, xAxis, yAxis));

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
                Arrow firstArrow = lineArrow.FirstOrDefault(a => a != null);
                ml.ArrowSize = firstArrow != null ? firstArrow.Size : styleArrow;
                if (firstArrow != null) ml.ArrowSymbolId = firstArrow.Symbol;
                ml.LandingGap = gap;
                ml.Layer = textEnt.Layer;
                ml.Color = textEnt.Color;

                // posicion inicial del texto: del lado del rellano (luego se ajusta)
                double ix, iy;
                if (dogleg && underline)
                {
                    ix = doglegDir > 0 ? tail.X + gap : tail.X - gap - oldBox.Width;
                    iy = tail.Y + oldBox.Height + gap;
                }
                else if (dogleg)
                {
                    ix = doglegDir > 0 ? land.X + gap : land.X - gap - oldBox.Width;
                    iy = tail.Y + 0.5 * oldBox.Height;
                }
                else
                {
                    ix = oldBox.MinX;
                    iy = oldBox.MaxY;
                }

                var mt = new MText();
                mt.SetDatabaseDefaults(db);
                mt.Contents = contents;
                mt.TextStyleId = styleId;
                mt.TextHeight = height;
                mt.Width = mtextWidth;
                mt.Normal = zAxis;
                mt.Direction = xAxis;
                mt.Attachment = AttachmentPoint.TopLeft;
                mt.Location = World(new Point2d(ix, iy), toWorld);
                ml.MText = mt;

                // un solo grupo de directriz; una linea por rama, de la punta al codo
                int leaderIdx = ml.AddLeader();
                var lineIdx = new List<int>();
                for (int i = 0; i < lines.Count; i++)
                {
                    int ln = ml.AddLeaderLine(leaderIdx);
                    ml.AddFirstVertex(ln, World(lines[i][0], toWorld));
                    for (int k = 1; k < lines[i].Count; k++)
                        ml.AddLastVertex(ln, World(lines[i][k], toWorld));
                    if (lineArrow[i] != null)
                    {
                        // SOLID -> flecha cerrada rellena (simbolo nulo); bloque -> el mismo bloque
                        ml.SetArrowSize(ln, lineArrow[i].Size);
                        ml.SetArrowSymbolId(ln, lineArrow[i].Symbol);
                    }
                    lineIdx.Add(ln);
                }

                if (dogleg)
                {
                    ml.EnableLanding = true;
                    ml.EnableDogleg = true;
                    TextAttachmentType att = underline ? TextAttachmentType.AttachmentAllLine : TextAttachmentType.AttachmentMiddle;
                    ml.SetTextAttachmentType(att, LeaderDirectionType.LeftLeader);
                    ml.SetTextAttachmentType(att, LeaderDirectionType.RightLeader);
                    SetDoglegLength(ml, leaderIdx, xAxis * doglegDir, underline ? 0.0 : landLen, height);
                }
                else
                {
                    ml.EnableDogleg = false;
                    ml.EnableLanding = false;
                }

                owner.AppendEntity(ml);
                tr.AddNewlyCreatedDBObject(ml, true);

                // Subrayado: rellano + separacion + texto = largo de la raya original
                if (dogleg && underline)
                {
                    double w = ContentWidth(ml, toLocal) ?? oldBox.Width;
                    SetDoglegLength(ml, leaderIdx, xAxis * doglegDir, landLen - w - gap, height);
                }

                // ---------- 8. Enganchar: el final de las lineas, en el codo exacto ----------
                Point3d wantTail = World(tail, toWorld);
                for (int pass = 0; pass < 4; pass++)
                {
                    Vector3d delta = wantTail - ml.GetLastVertex(lineIdx[0]);
                    if (delta.Length < 1e-9) break;
                    ml.TextLocation = ml.TextLocation + delta;
                }

                // ---------- 9. Borrar las piezas sueltas ----------
                textEnt.Erase();
                foreach (Curve c in curves) c.Erase();
                foreach (Entity a in arrowEnts) a.Erase();

                tr.Commit();
                return true;
            }
        }

        /// <summary>Longitud y direccion del rellano (nunca cero, para no perder la direccion).</summary>
        private static void SetDoglegLength(MLeader ml, int leaderIdx, Vector3d dir, double length, double textHeight)
        {
            double len = Math.Max(length, 0.01 * textHeight);
            ml.SetDogleg(leaderIdx, dir.GetNormal() * len);
            ml.SetDoglegLength(leaderIdx, len);
            ml.DoglegLength = len;
        }

        /// <summary>
        /// Grafo con los tramos seleccionados (nudos = extremos que coinciden). El
        /// apoyo es el extremo mas cercano al texto; el tronco va del apoyo al primer
        /// cruce (o a la punta, si no hay ramas), y cada rama del cruce a una punta.
        /// Devuelve false si los tramos no forman un unico conjunto conectado.
        /// </summary>
        private static bool BuildTree(List<List<Point2d>> pieces, Box textBox, double tol,
            out List<Point2d> trunk, out List<List<Point2d>> lines)
        {
            trunk = null;
            lines = null;
            var nodes = new List<Point2d>();
            var edges = new List<Edge>();
            foreach (List<Point2d> p in pieces)
                edges.Add(new Edge { A = NodeOf(nodes, p[0], tol), B = NodeOf(nodes, p[p.Count - 1], tol), Pts = p });
            var adj = nodes.Select(_ => new List<int>()).ToList();
            for (int i = 0; i < edges.Count; i++)
            {
                adj[edges[i].A].Add(i);
                if (edges[i].B != edges[i].A) adj[edges[i].B].Add(i);
            }

            // apoyo: el extremo libre mas cercano al texto (o el nudo mas cercano)
            var leaves = Enumerable.Range(0, nodes.Count).Where(n => adj[n].Count == 1).ToList();
            var candidates = leaves.Count > 0 ? leaves : Enumerable.Range(0, nodes.Count).ToList();
            int landNode = candidates.OrderBy(n => textBox.DistanceTo(nodes[n])).First();

            // todos los tramos deben estar conectados con el apoyo
            var seen = new HashSet<int> { landNode };
            var queue = new Queue<int>();
            queue.Enqueue(landNode);
            int reachedEdges = 0;
            var edgeSeen = new HashSet<int>();
            while (queue.Count > 0)
            {
                int n = queue.Dequeue();
                foreach (int ei in adj[n])
                {
                    if (edgeSeen.Add(ei)) reachedEdges++;
                    int o = edges[ei].Other(n);
                    if (seen.Add(o)) queue.Enqueue(o);
                }
            }
            if (reachedEdges != edges.Count) return false;

            // tronco: del apoyo mientras no haya cruce
            var used = new HashSet<int>();
            trunk = new List<Point2d> { nodes[landNode] };
            int cur = landNode;
            while (true)
            {
                if (cur != landNode && adj[cur].Count != 2) break;
                var next = adj[cur].Where(ei => !used.Contains(ei)).ToList();
                if (next.Count != 1) break;
                used.Add(next[0]);
                trunk.AddRange(edges[next[0]].From(cur).Skip(1));
                cur = edges[next[0]].Other(cur);
            }

            // ramas: todos los caminos desde el cruce hasta una punta
            var branches = new List<List<Point2d>>();
            CollectBranches(edges, adj, cur, new List<Point2d> { nodes[cur] }, used, branches);

            lines = new List<List<Point2d>>();
            if (branches.Count == 0)
            {
                // una sola linea: el tronco entero, de la punta al apoyo
                var l = new List<Point2d>(trunk);
                l.Reverse();
                lines.Add(Simplify(l));
            }
            else
            {
                var back = new List<Point2d>(trunk);
                back.Reverse();                               // cruce -> apoyo
                foreach (List<Point2d> b in branches)
                {
                    var l = new List<Point2d>(b);
                    l.Reverse();                              // punta -> cruce
                    l.AddRange(back.Skip(1));                 // ... -> apoyo
                    lines.Add(Simplify(l));
                }
            }
            return lines.All(l => l.Count >= 2);
        }

        private static void CollectBranches(List<Edge> edges, List<List<int>> adj, int node,
            List<Point2d> path, HashSet<int> used, List<List<Point2d>> result)
        {
            var next = adj[node].Where(ei => !used.Contains(ei)).ToList();
            if (next.Count == 0)
            {
                if (path.Count >= 2) result.Add(new List<Point2d>(path));
                return;
            }
            foreach (int ei in next)
            {
                used.Add(ei);
                var np = new List<Point2d>(path);
                np.AddRange(edges[ei].From(node).Skip(1));
                CollectBranches(edges, adj, edges[ei].Other(node), np, used, result);
                used.Remove(ei);
            }
        }

        private static int NodeOf(List<Point2d> nodes, Point2d p, double tol)
        {
            for (int i = 0; i < nodes.Count; i++)
                if (nodes[i].GetDistanceTo(p) <= tol) return i;
            nodes.Add(p);
            return nodes.Count - 1;
        }

        /// <summary>Lee una flecha seleccionada (SOLID o bloque), o null si no lo es.</summary>
        private static Arrow ReadArrow(Entity e, Matrix3d toLocal)
        {
            if (e is Solid so)
            {
                var v = new List<Point2d>();
                for (short i = 0; i < 4; i++)
                {
                    Point2d q = ToLocal2d(so.GetPointAt(i), toLocal);
                    if (!v.Any(x => x.GetDistanceTo(q) < 1e-9)) v.Add(q);
                }
                if (v.Count < 3) return null;
                // tamano: de la punta (el vertice mas alejado del centro de la base)
                // a la base; la punta definitiva se elige luego segun la rama
                var c = new Point2d(v.Average(x => x.X), v.Average(x => x.Y));
                Point2d tip = v.OrderByDescending(x => x.GetDistanceTo(c)).First();
                var baseV = v.Where(x => x.GetDistanceTo(tip) > 1e-9).ToList();
                var mid = new Point2d(baseV.Average(x => x.X), baseV.Average(x => x.Y));
                return new Arrow { Ref = c, IsSolid = true, Verts = v, Size = tip.GetDistanceTo(mid) };
            }
            if (e is BlockReference br)
            {
                return new Arrow
                {
                    Ref = ToLocal2d(br.Position, toLocal),
                    IsSolid = false,
                    Size = Math.Abs(br.ScaleFactors.X),
                    Symbol = br.IsDynamicBlock ? br.DynamicBlockTableRecord : br.BlockTableRecord,
                };
            }
            return null;
        }

        private static Point2d ToLocal2d(Point3d p, Matrix3d toLocal)
        {
            Point3d q = p.TransformBy(toLocal);
            return new Point2d(q.X, q.Y);
        }

        private static Point3d World(Point2d p, Matrix3d toWorld) =>
            new Point3d(p.X, p.Y, 0.0).TransformBy(toWorld);

        /// <summary>Ancho del texto del MLEADER, en el sistema local.</summary>
        private static double? ContentWidth(MLeader ml, Matrix3d toLocal)
        {
            try
            {
                using (MText m = ml.MText)
                    return new Box(m.GetBoundingPoints().Cast<Point3d>().Select(p => p.TransformBy(toLocal))).Width;
            }
            catch (System.Exception) { return null; }
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
            return r;
        }

        /// <summary>Une TODAS las piezas en una sola cadena, enganchando cada vez la
        /// pieza cuyo extremo esta mas cerca de uno de los extremos de la cadena (si
        /// hay un hueco, se salva con un tramo recto; no se descarta ninguna pieza).
        /// Solo se usa si las lineas seleccionadas no se tocan entre si.</summary>
        private static List<Point2d> JoinPieces(List<List<Point2d>> pieces)
        {
            var chain = new List<Point2d>(pieces[0]);
            var rest = pieces.Skip(1).ToList();
            while (rest.Count > 0)
            {
                double best = double.MaxValue;
                int bi = -1;
                bool atEnd = true, reverse = false;
                Point2d head = chain[0], tail = chain[chain.Count - 1];
                for (int i = 0; i < rest.Count; i++)
                {
                    List<Point2d> p = rest[i];
                    Point2d first = p[0], last = p[p.Count - 1];
                    // (distancia, enganchar al final de la cadena, invertir la pieza)
                    double[] d = { tail.GetDistanceTo(first), tail.GetDistanceTo(last), head.GetDistanceTo(last), head.GetDistanceTo(first) };
                    bool[] end = { true, true, false, false };
                    bool[] rev = { false, true, false, true };
                    for (int k = 0; k < 4; k++)
                        if (d[k] < best) { best = d[k]; bi = i; atEnd = end[k]; reverse = rev[k]; }
                }

                var piece = new List<Point2d>(rest[bi]);
                rest.RemoveAt(bi);
                if (reverse) piece.Reverse();
                if (atEnd) chain.AddRange(piece);
                else chain.InsertRange(0, piece);
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
