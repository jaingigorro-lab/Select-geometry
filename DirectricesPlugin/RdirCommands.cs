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

        /// <summary>RDIRINFO: diagnostico. Dice que es cada objeto que tocas (por
        /// ejemplo, cada raya de un subrayado doble: si es parte de una directriz o
        /// una linea suelta) y, si es una directriz multiple, su estilo, enganche,
        /// rellano, lineas y texto.</summary>
        [CommandMethod("RDIRINFO", CommandFlags.Modal)]
        public void RdirInfo()
        {
            Document doc = AcApp.DocumentManager.MdiActiveDocument;
            if (doc == null) return;
            Editor ed = doc.Editor;
            while (true)
            {
                var peo = new PromptEntityOptions("\nRDIRINFO: toca un objeto (Intro para terminar): ") { AllowNone = true };
                PromptEntityResult per = ed.GetEntity(peo);
                if (per.Status != PromptStatus.OK) break;
                using (Transaction tr = doc.Database.TransactionManager.StartTransaction())
                {
                    var ent = (Entity)tr.GetObject(per.ObjectId, OpenMode.ForRead);
                    ed.WriteMessage($"\n  Tipo: {ent.GetType().Name}   Capa: {ent.Layer}");
                    if (ent is MLeader ml)
                    {
                        string style = "?";
                        try { style = ((MLeaderStyle)tr.GetObject(ml.MLeaderStyle, OpenMode.ForRead)).Name; }
                        catch (System.Exception) { }
                        ed.WriteMessage($"\n  Estilo: {style}   Escala: {ml.Scale}   Altura de texto: {ml.TextHeight}");
                        ed.WriteMessage($"\n  Rellano: {(ml.EnableLanding ? "si" : "no")}   Quiebro: {(ml.EnableDogleg ? "si" : "no")}   Largo del quiebro: {ml.DoglegLength}   Separacion: {ml.LandingGap}");
                        try
                        {
                            ed.WriteMessage($"\n  Enganche izquierda / derecha: {ml.GetTextAttachmentType(LeaderDirectionType.LeftLeader)} / {ml.GetTextAttachmentType(LeaderDirectionType.RightLeader)}");
                        }
                        catch (System.Exception) { }
                        ed.WriteMessage($"\n  Lineas de directriz: {ml.LeaderLineCount}");
                        try
                        {
                            using (MText m = ml.MText) ed.WriteMessage($"\n  Contenido del texto: {m.Contents}");
                        }
                        catch (System.Exception) { }
                    }
                    else if (ent is MText mt) ed.WriteMessage($"\n  Contenido: {mt.Contents}");
                    else if (ent is DBText t) ed.WriteMessage($"\n  Texto: {t.TextString}");
                    else ed.WriteMessage("\n  Es un objeto suelto: no forma parte de ninguna directriz.");
                    tr.Commit();
                }
            }
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
            string step = "leer la seleccion";
            var warnings = new List<string>();
            // Pasos no imprescindibles: si AutoCAD rechaza alguno, se avisa y se sigue
            void Soft(string what, Action a) => SoftTo(warnings, what, a);

            using (Transaction tr = db.TransactionManager.StartTransaction())
            {
                try
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
                    step = "leer el texto";
                    string contents;
                    bool textUnderlined;
                    double height, mtextWidth = 0.0;
                    ObjectId styleId;
                    Vector3d textXDir;
                    Point3d textOrigin;
                    if (textEnt is DBText dt)
                    {
                        contents = DbTextToMText(dt.TextString, out textUnderlined);
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
                        contents = StripMTextUnderline(omt.Contents, out textUnderlined);
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

                    step = "medir el texto";
                    Box oldBox = MeasureText(textEnt, toLocal);

                    // ---------- 4. Lineas de directriz con EXACTAMENTE lo seleccionado ----------
                    step = "unir las lineas";
                    var pieces = curves
                        .Select(c => Simplify(GetVertices(c).Select(p => ToLocal2d(p, toLocal)).ToList()))
                        .Where(p => p.Count >= 2)
                        .ToList();
                    if (pieces.Count == 0)
                    {
                        ed.WriteMessage("\nRDIR: las lineas seleccionadas no tienen longitud.");
                        return false;
                    }

                    // trunk = del apoyo (junto al texto) al cruce, o a la punta si no hay
                    // ramas; branches = del cruce a cada punta
                    List<Point2d> trunk;
                    List<List<Point2d>> branches;
                    double tol = Math.Max(1e-6, height * 1e-3);
                    if (!BuildTree(pieces, oldBox, tol, 0.5 * height, out trunk, out branches))
                    {
                        warnings.Add("las lineas seleccionadas no se tocan; se han unido por sus extremos mas cercanos");
                        List<Point2d> chain = JoinPieces(pieces);
                        if (oldBox.DistanceTo(chain[chain.Count - 1]) < oldBox.DistanceTo(chain[0])) chain.Reverse();
                        trunk = chain;
                        branches = new List<List<Point2d>>();
                    }
                    trunk = Simplify(trunk);
                    branches = branches.Select(Simplify).ToList();

                    // ---------- 5. Estilo, rellano y subrayado ----------
                    step = "leer el estilo de directriz";
                    // Todo se hace en unidades reales del dibujo (escala 1), para que la
                    // altura del texto sea exactamente la del original.
                    double styleScale, styleArrow, gap;
                    using (var probe = new MLeader())
                    {
                        probe.SetDatabaseDefaults(db);
                        if (!db.MLeaderstyle.IsNull) Soft("aplicar el estilo de directriz actual", () => probe.MLeaderStyle = db.MLeaderstyle);
                        styleScale = probe.Scale > 0 ? probe.Scale : 1.0;
                        styleArrow = probe.ArrowSize * styleScale;
                        gap = probe.LandingGap * styleScale;
                    }

                    // core = del codo (cola de las lineas) al cruce o a la punta
                    bool dogleg = false, underline = false;
                    double doglegDir = 1.0, landLen = 0.0;
                    List<Point2d> core = trunk;
                    if (trunk.Count >= 2 && IsAlongText(trunk[0], trunk[1]))
                    {
                        Point2d a = trunk[0], b = trunk[1];    // a = apoyo, b = siguiente vertice
                        double overlap = Math.Min(Math.Max(a.X, b.X), oldBox.MaxX) - Math.Max(Math.Min(a.X, b.X), oldBox.MinX);
                        bool underText = overlap > 0.5 * oldBox.Width;
                        double dir = a.X > b.X ? 1.0 : -1.0;   // de b hacia el apoyo (hacia el texto)
                        if (trunk.Count >= 3 || branches.Count > 0)
                        {
                            // raya + codo real: la raya es el rellano
                            dogleg = true;
                            underline = underText || textUnderlined;
                            doglegDir = dir;
                            landLen = Math.Abs(a.X - b.X);
                            core = trunk.Skip(1).ToList();
                        }
                        else if (underText || textUnderlined)
                        {
                            // una sola recta que sigue por debajo del texto: el codo va en
                            // el borde del texto, y lo que queda bajo el texto es el subrayado
                            double nearEdge = dir > 0 ? oldBox.MinX : oldBox.MaxX;
                            double kx = nearEdge - dir * gap;
                            kx = Math.Max(Math.Min(a.X, b.X), Math.Min(Math.Max(a.X, b.X), kx));
                            double ky = b.Y + (a.Y - b.Y) * (kx - b.X) / (a.X - b.X);
                            var knee = new Point2d(kx, ky);
                            if (knee.GetDistanceTo(b) > 1e-9)
                            {
                                dogleg = true;
                                underline = true;
                                doglegDir = dir;
                                landLen = Math.Abs(a.X - kx);
                                core = new List<Point2d> { knee, b };
                            }
                        }
                    }
                    if (!dogleg && textUnderlined)
                    {
                        // texto subrayado por formato, sin raya propia: el subrayado lo
                        // dibuja la directriz, saliendo del final de la linea
                        Point2d t0 = trunk[0];
                        dogleg = true;
                        underline = true;
                        doglegDir = oldBox.MinX + oldBox.MaxX >= 2.0 * t0.X ? 1.0 : -1.0;
                        landLen = doglegDir > 0 ? oldBox.MaxX - t0.X : t0.X - oldBox.MinX;
                    }
                    Point2d tail = core[0];

                    // lineas del MLEADER, cada una de su punta a la cola (el codo)
                    var coreBack = Enumerable.Reverse(core).ToList();
                    var lines = new List<List<Point2d>>();
                    if (branches.Count == 0) lines.Add(Simplify(coreBack));
                    else
                        foreach (List<Point2d> br in branches)
                        {
                            var l = Enumerable.Reverse(br).ToList();
                            l.AddRange(coreBack.Skip(1));
                            lines.Add(Simplify(l));
                        }
                    if (lines.Any(l => l.Count < 2))
                    {
                        ed.WriteMessage("\nRDIR: las lineas seleccionadas no forman una directriz.");
                        return false;
                    }

                    // ---------- 6. Flechas: cada una a la rama de punta mas cercana ----------
                    step = "leer las flechas";
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
                    step = "crear la directriz";
                    var owner = (BlockTableRecord)tr.GetObject(textEnt.BlockId, OpenMode.ForWrite);
                    Arrow firstArrow = lineArrow.FirstOrDefault(a => a != null);

                    // posicion inicial del texto, del lado del rellano (luego se ajusta)
                    double ix, iy;
                    if (dogleg && underline)
                    {
                        ix = doglegDir > 0 ? tail.X + gap : tail.X - gap - oldBox.Width;
                        iy = tail.Y + oldBox.Height + gap;
                    }
                    else if (dogleg)
                    {
                        ix = doglegDir > 0 ? tail.X + landLen + gap : tail.X - landLen - gap - oldBox.Width;
                        iy = tail.Y + 0.5 * oldBox.Height;
                    }
                    else
                    {
                        ix = oldBox.MinX;
                        iy = oldBox.MaxY;
                    }
                    // subrayado solo si el original lo tenia; si no, enganche al centro,
                    // diga lo que diga el estilo. "Subrayar linea inferior" deja una sola
                    // raya bajo el texto (con "Subrayar todo el texto" AutoCAD puede
                    // dibujar el subrayado y el rellano por separado: doble raya).
                    TextAttachmentType att = underline ? TextAttachmentType.AttachmentBottomLine : TextAttachmentType.AttachmentMiddle;

                    // Cada linea de directriz lleva solo SUS vertices (la punta y los quiebros
                    // intermedios), NUNCA el codo: el final de las lineas es el punto de
                    // enganche del rellano, que gestiona AutoCAD y que viaja con el texto.
                    // Si el codo se anadiera como vertice, quedaria fijo al mover el texto
                    // (las lineas se doblarian en el sitio viejo) y AutoCAD rechaza una
                    // segunda linea que acabe en el (eInvalidContext). Se prueban varias
                    // formas documentadas de crear las lineas, cada una sobre un MLEADER
                    // nuevo, y se usa la primera que AutoCAD acepta.
                    step = "anadir las lineas de directriz";
                    MLeader ml = null;
                    List<int> lineIdx = null, clusters = null;
                    var failures = new List<string>();
                    for (int strategy = 1; strategy <= 3 && ml == null; strategy++)
                    {
                        if (lines.Count == 1 && strategy == 2) continue;
                        var aw = new List<string>();
                        MLeader cand = null;
                        try
                        {
                            cand = new MLeader();
                            cand.SetDatabaseDefaults(db);
                            if (!db.MLeaderstyle.IsNull) SoftTo(aw, "aplicar el estilo de directriz actual", () => cand.MLeaderStyle = db.MLeaderstyle);
                            SoftTo(aw, "dejarla no anotativa", () => cand.Annotative = AnnotativeStates.False);
                            // plano con su eje X a lo largo del texto: el rellano y el
                            // subrayado siguen esa direccion
                            SoftTo(aw, "orientar el plano de la directriz", () => cand.SetPlane(new Plane(textOrigin, xAxis, yAxis)));
                            SoftTo(aw, "poner la escala general a 1", () => cand.Scale = 1.0);
                            cand.ContentType = ContentType.MTextContent;
                            cand.TextStyleId = styleId;
                            cand.TextHeight = height;
                            SoftTo(aw, "respetar el angulo del texto", () => cand.TextAngleType = TextAngleType.InsertAngle);
                            SoftTo(aw, "ajustar la flecha", () =>
                            {
                                cand.ArrowSize = firstArrow != null ? firstArrow.Size : styleArrow;
                                if (firstArrow != null) cand.ArrowSymbolId = firstArrow.Symbol;
                            });
                            SoftTo(aw, "ajustar la separacion del rellano", () => cand.LandingGap = gap);
                            cand.Layer = textEnt.Layer;
                            cand.Color = textEnt.Color;

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
                            cand.MText = mt;

                            var li = new List<int>();
                            var cl = new List<int>();
                            if (strategy == 1)
                            {
                                // un grupo; cada linea se crea y se rellena por orden
                                int ld = cand.AddLeader();
                                cl.Add(ld);
                                foreach (List<Point2d> l in lines)
                                {
                                    int ln = cand.AddLeaderLine(ld);
                                    AddVertices(cand, ln, l, toWorld);
                                    li.Add(ln);
                                }
                            }
                            else if (strategy == 2)
                            {
                                // un grupo; primero todas las lineas, luego sus vertices
                                int ld = cand.AddLeader();
                                cl.Add(ld);
                                foreach (List<Point2d> l in lines) li.Add(cand.AddLeaderLine(ld));
                                for (int i = 0; i < lines.Count; i++) AddVertices(cand, li[i], lines[i], toWorld);
                            }
                            else if (strategy == 3)
                            {
                                // cada linea se crea por su punta y AutoCAD la asigna al grupo
                                foreach (List<Point2d> l in lines)
                                {
                                    int own = l.Count - 1;   // vertices propios: todos menos el codo
                                    int ln = cand.AddLeaderLine(World(l[0], toWorld));
                                    for (int k = 1; k < own; k++) cand.AddLastVertex(ln, World(l[k], toWorld));
                                    // si AutoCAD anadio un vertice propio, se dejan exactamente los nuestros
                                    while (cand.VerticesCount(ln) > own) cand.RemoveLastVertex(ln);
                                    for (int k = 0; k < own; k++) cand.SetVertex(ln, k, World(l[k], toWorld));
                                    li.Add(ln);
                                    int ld = cand.GetLeaderIndex(ln);
                                    if (!cl.Contains(ld)) cl.Add(ld);
                                }
                            }

                            for (int i = 0; i < lines.Count; i++)
                            {
                                Arrow la = lineArrow[i];
                                int ln = li[i];
                                if (la == null) continue;
                                // SOLID -> flecha cerrada rellena (simbolo nulo); bloque -> el mismo bloque
                                SoftTo(aw, "ajustar la flecha de una rama", () =>
                                {
                                    cand.SetArrowSize(ln, la.Size);
                                    cand.SetArrowSymbolId(ln, la.Symbol);
                                });
                            }

                            SoftTo(aw, "ajustar el enganche del texto", () =>
                            {
                                cand.SetTextAttachmentType(att, LeaderDirectionType.LeftLeader);
                                cand.SetTextAttachmentType(att, LeaderDirectionType.RightLeader);
                            });
                            if (dogleg)
                            {
                                cand.EnableLanding = true;
                                cand.EnableDogleg = true;
                                foreach (int ld in cl)
                                    SoftTo(aw, "ajustar el rellano", () => SetDoglegLength(cand, ld, xAxis * doglegDir, underline ? 0.0 : landLen, height));
                            }
                            else
                            {
                                cand.EnableDogleg = false;
                                cand.EnableLanding = false;
                            }

                            ml = cand;
                            lineIdx = li;
                            clusters = cl;
                            warnings.AddRange(aw);
                        }
                        catch (System.Exception ex)
                        {
                            failures.Add($"forma {strategy}: {ex.Message}");
                            try { cand?.Dispose(); } catch (System.Exception) { }
                        }
                    }
                    if (ml == null) throw new System.Exception(string.Join("; ", failures));

                    step = "anadir la directriz al dibujo";
                    owner.AppendEntity(ml);
                    tr.AddNewlyCreatedDBObject(ml, true);

                    // Subrayado: rellano + separacion + texto = largo de la raya original
                    if (dogleg && underline)
                    {
                        double w = ContentWidth(ml, toLocal) ?? oldBox.Width;
                        foreach (int ld in clusters)
                            Soft("ajustar el largo del rellano", () => SetDoglegLength(ml, ld, xAxis * doglegDir, landLen - w - gap, height));
                    }

                    // ---------- 8. Enganchar: el rellano, en el codo exacto ----------
                    // Se mide donde DIBUJA AutoCAD el final de la primera linea (el enganche
                    // del rellano) y se desplaza el texto, que arrastra al rellano, hasta
                    // que ese punto cae en el codo original.
                    step = "colocar el texto";
                    Point3d wantTail = World(tail, toWorld);
                    List<Point2d> l0 = lines[0];
                    Point3d lastOwn = World(l0[l0.Count - 2], toWorld);
                    Point3d? prevOwn = l0.Count >= 3 ? World(l0[l0.Count - 3], toWorld) : (Point3d?)null;
                    double arrow0 = lineArrow[0] != null ? lineArrow[0].Size : styleArrow;
                    // si el ultimo vertice propio es la punta, la linea puede empezar
                    // recortada por la flecha: se acepta esa holgura
                    double nearTol = (l0.Count == 2 ? 1.5 * arrow0 : 0.0) + Math.Max(1e-6, 1e-3 * height);
                    bool placed = false;
                    for (int pass = 0; pass < 4; pass++)
                    {
                        Point3d? at = DrawnConnection(ml, lastOwn, prevOwn, nearTol);
                        if (!at.HasValue) break;
                        Vector3d delta = wantTail - at.Value;
                        if (delta.Length < Math.Max(1e-6, 1e-4 * height)) { placed = true; break; }
                        Point3d loc = ml.TextLocation;
                        ml.TextLocation = loc + delta;
                        Point3d? after = DrawnConnection(ml, lastOwn, prevOwn, nearTol);
                        if (!after.HasValue || (after.Value - at.Value).Length < 1e-9)
                        {
                            ml.TextLocation = loc;   // el rellano no acompana al texto: se deja
                            break;
                        }
                    }
                    if (!placed) warnings.Add("ajustar el texto para que el rellano caiga exactamente en el codo original (revisa su posicion)");

                    // ---------- 9. Borrar las piezas sueltas ----------
                    step = "borrar las piezas sueltas";
                    textEnt.Erase();
                    foreach (Curve c in curves) c.Erase();
                    foreach (Entity a in arrowEnts) a.Erase();

                    tr.Commit();
                }
                catch (System.Exception ex)
                {
                    throw new System.Exception($"al {step}: {ex.Message}", ex);
                }
            }

            foreach (string w in warnings)
                ed.WriteMessage($"\nRDIR: aviso, no se pudo {w}.");
            return true;
        }

        /// <summary>Ejecuta un paso no imprescindible: si AutoCAD lo rechaza, lo anota
        /// como aviso en lugar de cancelar la directriz.</summary>
        private static void SoftTo(List<string> warnings, string what, Action a)
        {
            try { a(); }
            catch (System.Exception ex) { warnings.Add($"{what} ({ex.Message})"); }
        }

        /// <summary>Vertices PROPIOS de una linea de directriz recien creada: la punta
        /// como cabeza y los quiebros intermedios, por orden. El ultimo punto (el codo)
        /// no se anade: es el enganche del rellano, que pone AutoCAD.</summary>
        private static void AddVertices(MLeader ml, int ln, List<Point2d> l, Matrix3d toWorld)
        {
            ml.AddFirstVertex(ln, World(l[0], toWorld));
            for (int k = 1; k < l.Count - 1; k++) ml.AddLastVertex(ln, World(l[k], toWorld));
        }

        /// <summary>Punto donde AutoCAD dibuja el final de una linea de directriz (su
        /// enganche con el rellano o con el texto): el otro extremo del tramo que sale
        /// del ultimo vertice propio de la linea, segun la geometria que dibuja el
        /// MLEADER (se descompone en memoria, sin tocar el dibujo).</summary>
        private static Point3d? DrawnConnection(MLeader ml, Point3d lastOwn, Point3d? prevOwn, double nearTol)
        {
            var parts = new DBObjectCollection();
            try
            {
                ml.Explode(parts);
                Point3d? best = null;
                double bestD = double.MaxValue;
                foreach (DBObject o in parts)
                {
                    if (!(o is Curve c)) continue;
                    List<Point3d> v = GetVertices(c);
                    for (int i = 0; i + 1 < v.Count; i++)
                    {
                        Point3d a = v[i], b = v[i + 1];
                        for (int side = 0; side < 2; side++)
                        {
                            Point3d near = side == 0 ? a : b, far = side == 0 ? b : a;
                            double d = near.DistanceTo(lastOwn);
                            if (d > nearTol || d >= bestD) continue;
                            // no confundirlo con el tramo que vuelve al vertice anterior
                            if (prevOwn.HasValue && far.DistanceTo(prevOwn.Value) <= nearTol) continue;
                            bestD = d;
                            best = far;
                        }
                    }
                }
                return best;
            }
            catch (System.Exception) { return null; }
            finally
            {
                foreach (DBObject o in parts) o.Dispose();
            }
        }

        /// <summary>Tramo paralelo al texto (eje X local), con 0,1 de tolerancia.</summary>
        private static bool IsAlongText(Point2d a, Point2d b)
        {
            double dx = b.X - a.X, dy = b.Y - a.Y;
            return Math.Abs(dx) > 1e-9 && Math.Abs(dy) <= 0.1 * Math.Abs(dx);
        }

        /// <summary>Rectangulo del texto original en el sistema local. Primero sobre
        /// una copia; si AutoCAD no la mide, sobre el propio texto (que luego se
        /// borra); y si tampoco, con su caja envolvente universal.</summary>
        private static Box MeasureText(Entity textEnt, Matrix3d toLocal)
        {
            if (textEnt is MText omt)
            {
                try { return new Box(omt.GetBoundingPoints().Cast<Point3d>().Select(p => p.TransformBy(toLocal))); }
                catch (System.Exception) { }
            }
            try
            {
                using (var clone = (Entity)textEnt.Clone())
                {
                    clone.TransformBy(toLocal);
                    Extents3d e = clone.GeometricExtents;
                    return new Box(new[] { e.MinPoint, e.MaxPoint });
                }
            }
            catch (System.Exception) { }
            try
            {
                Extents3d w = textEnt.GeometricExtents;
                var corners = new List<Point3d>();
                foreach (double x in new[] { w.MinPoint.X, w.MaxPoint.X })
                    foreach (double y in new[] { w.MinPoint.Y, w.MaxPoint.Y })
                        foreach (double z in new[] { w.MinPoint.Z, w.MaxPoint.Z })
                            corners.Add(new Point3d(x, y, z).TransformBy(toLocal));
                return new Box(corners);
            }
            catch (System.Exception) { }
            Point3d o = Point3d.Origin;
            return new Box(new[] { o, o });
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
        /// apoyo es el nudo mas cercano al texto (si hay varios igual de cerca, se
        /// prefiere un extremo libre). El tronco va del apoyo al primer cruce (o a la
        /// punta, si no hay ramas), y cada rama del cruce a una punta. Devuelve false
        /// si los tramos no forman un unico conjunto conectado.
        /// </summary>
        private static bool BuildTree(List<List<Point2d>> pieces, Box textBox, double tol, double near,
            out List<Point2d> trunk, out List<List<Point2d>> branches)
        {
            trunk = null;
            branches = null;
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

            // apoyo
            double dmin = nodes.Min(n => textBox.DistanceTo(n));
            var close = Enumerable.Range(0, nodes.Count).Where(n => textBox.DistanceTo(nodes[n]) <= dmin + near).ToList();
            var closeLeaves = close.Where(n => adj[n].Count == 1).ToList();
            int landNode = (closeLeaves.Count > 0 ? closeLeaves : close).OrderBy(n => textBox.DistanceTo(nodes[n])).First();

            // todos los tramos deben estar conectados con el apoyo
            var seen = new HashSet<int> { landNode };
            var queue = new Queue<int>();
            queue.Enqueue(landNode);
            var edgeSeen = new HashSet<int>();
            while (queue.Count > 0)
            {
                int n = queue.Dequeue();
                foreach (int ei in adj[n])
                {
                    edgeSeen.Add(ei);
                    int o = edges[ei].Other(n);
                    if (seen.Add(o)) queue.Enqueue(o);
                }
            }
            if (edgeSeen.Count != edges.Count) return false;

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
            branches = new List<List<Point2d>>();
            CollectBranches(edges, adj, cur, new List<Point2d> { nodes[cur] }, used, branches);
            return trunk.Count >= 2 || branches.Count > 0;
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

        /// <summary>Texto de un TEXT -> contenido de MTEXT: escapa \ { }, quita el
        /// subrayado %%u (lo dibuja la directriz, si no saldria doble) y convierte el
        /// sobrerrayado %%o; %%c, %%d, %%p y %%nnn se dejan tal cual (MTEXT si los
        /// entiende).</summary>
        private static string DbTextToMText(string s, out bool underlined)
        {
            var sb = new StringBuilder();
            bool over = false;
            underlined = false;
            for (int i = 0; i < s.Length; i++)
            {
                char c = s[i];
                if (c == '%' && i + 2 < s.Length && s[i + 1] == '%')
                {
                    char k = char.ToLowerInvariant(s[i + 2]);
                    if (k == 'u') { underlined = true; i += 2; continue; }
                    if (k == 'o') { over = !over; sb.Append(over ? "\\O" : "\\o"); i += 2; continue; }
                }
                if (c == '\\') sb.Append("\\\\");
                else if (c == '{') sb.Append("\\{");
                else if (c == '}') sb.Append("\\}");
                else sb.Append(c);
            }
            return sb.ToString();
        }

        /// <summary>Quita los codigos de subrayado \L ... \l de un contenido de MTEXT
        /// (el subrayado lo dibuja la directriz; si no, saldria doble).</summary>
        private static string StripMTextUnderline(string s, out bool underlined)
        {
            var sb = new StringBuilder();
            underlined = false;
            for (int i = 0; i < s.Length; i++)
            {
                char c = s[i];
                if (c == '\\' && i + 1 < s.Length)
                {
                    char k = s[i + 1];
                    if (k == 'L') { underlined = true; i++; continue; }
                    if (k == 'l') { i++; continue; }
                    sb.Append(c).Append(k);   // cualquier otro codigo (incluido \\) se deja igual
                    i++;
                    continue;
                }
                sb.Append(c);
            }
            return sb.ToString();
        }

    }
}
