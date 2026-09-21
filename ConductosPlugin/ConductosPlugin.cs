using System;
using System.Collections.Generic;
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
    // CVENT / CVENTT - Traza conductos de ventilacion en planta (representacion
    // a dos lineas), circulares o rectangulares, con reducciones y
    // derivaciones en T o en cruz que se acoplan a un conducto ya existente.
    // Traduccion 1:1 de ConductoVentilacionCircular_CVENT.lsp (que solo
    // contemplaba circular) con dos diferencias deliberadas:
    //
    //   - En vez de depender de una libreria de bloques externa (.dwg)
    //     construida a mano -algo que AutoLISP no puede generar-, este plugin
    //     CREA el mismo contrato de bloques (CVENT_TRAMO_RECTO,
    //     CVENT_REDUCCION, CVENT_CODO_A<angulo>) la primera vez que hace
    //     falta, vease BlockFactory.
    //   - Se anade el tipo RECTANGULAR: sin bloques de pared NI de codo -un
    //     codo real en conducto rectangular es un simple miter recto, sin
    //     radio: las dos paredes se cortan en su interseccion exacta a
    //     cualquier angulo, sin ninguna geometria de codo aparte- pero SI de
    //     rotulo (CVENT_ROTULO_RECT), con los mismos angulos normalizados
    //     que el circular.
    //
    // CVENT  - traza un conducto nuevo desde cero, punto a punto. Primero
    //          pregunta el tipo (Circular/Rectangular).
    // CVENTT - arranca una derivacion (T o cruz) desde un punto de un
    //          conducto YA DIBUJADO con CVENT, y a partir de ahi se traza
    //          igual que con CVENT. Por ahora solo admite derivaciones
    //          circulares.
    //
    // Cada giro (circular o rectangular) se ajusta al multiplo de 15 grados
    // mas cercano (hasta un maximo de 90). Se puede desactivar sobre la
    // marcha con "Libre".
    // ==========================================================

    internal static class CventConfig
    {
        // Longitud de la reduccion = TransitionFactor x la diferencia de
        // diametros, con un minimo para que nunca salga una reduccion
        // degenerada entre diametros muy parecidos.
        public const double TransitionFactor = 2.5;
        public const double TransitionMinFactor = 0.5;

        // Incremento de angulo de giro admitido (multiplos de 15, catalogo SMACNA),
        // igual en circular y rectangular -vease DuctRunner.TraceDuctRun-. Tope
        // maximo (grados), tambien igual para ambos tipos.
        public const double AngleStepCircular = 15.0;
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

        /// <summary>Fuerza la variable de sistema ATTDISP a 1 ("Normal"): con
        /// ATTDISP en 2 ("Activado"), AutoCAD fuerza TODOS los atributos de bloque a
        /// verse, sea cual sea su propio flag Invisible -incluida la seccion de un
        /// codo, que este plugin deja siempre invisible (BlockFactory.InsertLabel,
        /// forceInvisible)-, lo que parece un fallo del plugin sin serlo. CVENT y
        /// CVENTT llaman a esto al arrancar para que la visibilidad de cada rotulo
        /// dependa solo de su propio flag, como se espera.</summary>
        public static void EnsureAttDispNormal()
        {
            // ATTDISP es de tipo entero de 16 bits (short) a nivel interno: pasar un
            // int (32 bits) sin mas -aunque el valor "1" sea valido- dispara
            // eInvalidInput en SetSystemVariable. Hay que forzar el tipo exacto.
            AcApp.SetSystemVariable("ATTDISP", (short)1);
        }
    }

    /// <summary>
    /// Genera (la primera vez que hace falta) y despues inserta los bloques del
    /// contrato CVENT: CVENT_TRAMO_RECTO_D&lt;diam&gt;, CVENT_REDUCCION_D&lt;d1&gt;_D&lt;d2&gt;,
    /// CVENT_CODO_A&lt;angulo&gt; (solo circular; el rectangular no usa bloque de
    /// codo, vease DuctRunner.TraceDuctRun) y CVENT_ROTULO_CIRC/RECT. El LSP
    /// original necesitaba que estos bloques existieran ya en una libreria .dwg
    /// construida a mano (AutoLISP no puede crear bloques dinamicos); en C# se
    /// generan directamente, como bloques normales (no dinamicos): el tramo recto y
    /// la reduccion usan un cuerpo de longitud UNIDAD que se estira en X al
    /// insertarse (ScaleFactors), y el codo se construye a un diametro de
    /// referencia y se inserta escalado uniformemente al diametro real.
    /// </summary>
    internal static class BlockFactory
    {
        private static string Tag(double x) => x.ToString("0.##", CultureInfo.InvariantCulture).Replace('.', '_').Replace('-', 'n');

        public static string StraightBlockName(double diameter) => $"CVENT_TRAMO_RECTO_D{Tag(diameter)}";
        public static string ReductionBlockName(double d1, double d2) => $"CVENT_REDUCCION_D{Tag(d1)}_D{Tag(d2)}";
        public static string ElbowBlockName(double angleDegAbs) => $"CVENT_CODO_A{Tag(Math.Round(angleDegAbs / CventConfig.AngleStepCircular) * CventConfig.AngleStepCircular)}";

        /// <summary>Nombres de bloque ya reconstruidos durante esta sesion de AutoCAD
        /// (desde que se cargo la DLL con NETLOAD) -un dwg de pruebas reutilizado
        /// entre sesiones puede llevar una version VIEJA de un bloque con el mismo
        /// nombre (de una version anterior del plugin); sin este control, un bloque
        /// que ya "existe con contenido" en ese dwg se daba por bueno tal cual, y un
        /// cambio de geometria en el codigo no se veia nunca reflejado hasta borrar
        /// el bloque a mano. Al arrancar una sesion nueva de AutoCAD (recomendado
        /// antes de cada prueba) este set esta vacio, asi que cada bloque se
        /// reconstruye una vez, la primera vez que hace falta en esa sesion, sea cual
        /// sea su contenido previo en el dwg.</summary>
        private static readonly HashSet<string> _rebuiltThisSession = new HashSet<string>();

        /// <summary>Da de alta el bloque "name" si no existe. Si ya existe pero no se
        /// ha reconstruido todavia en esta sesion (vease _rebuiltThisSession), borra
        /// su contenido y lo deja listo para reconstruirlo con la geometria actual.
        /// Devuelve null solo si ya se reconstruyo en esta sesion -no hace falta
        /// volver a dibujarlo-.</summary>
        private static BlockTableRecord GetOrCreateEmptyBlock(Transaction tr, Database db, string name)
        {
            var bt = (BlockTable)tr.GetObject(db.BlockTableId, OpenMode.ForRead);
            if (bt.Has(name))
            {
                if (_rebuiltThisSession.Contains(name)) return null;
                var existing = (BlockTableRecord)tr.GetObject(bt[name], OpenMode.ForWrite);
                foreach (ObjectId id in existing)
                    ((Entity)tr.GetObject(id, OpenMode.ForWrite)).Erase();
                _rebuiltThisSession.Add(name);
                return existing;
            }
            bt.UpgradeOpen();
            var btr = new BlockTableRecord { Name = name };
            bt.Add(btr);
            tr.AddNewlyCreatedDBObject(btr, true);
            _rebuiltThisSession.Add(name);
            return btr;
        }

        private static ObjectId ExistingId(Transaction tr, Database db, string name) =>
            ((BlockTable)tr.GetObject(db.BlockTableId, OpenMode.ForRead))[name];

        /// <summary>Tramo recto de longitud UNIDAD (1): dos lineas paralelas de (0,+-r)
        /// a (1,+-r) en la capa "0" (para heredar la capa de la insercion). Al
        /// insertarse se estira en X = longitud real. Sin atributos: este bloque
        /// tiene escala NO uniforme (X=longitud, Y=1 fijo), y un atributo definido
        /// aqui saldria con Height/WidthFactor mal calculados por
        /// SetAttributeFromBlock. El rotulo (ANCHO/ALTO/LARGO) se inserta aparte,
        /// como un bloque INDEPENDIENTE de escala uniforme -vease
        /// EnsureLabelBlock/InsertLabel mas abajo-.</summary>
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
        /// eje +X = direccion de entrada. Los arcos de pared van EXPLICITAMENTE en
        /// WallLayer y el de eje en AxisLayer -no en "0"-, porque este bloque se
        /// inserta con Layer=WallLayer: si los tres arcos fueran "0" (heredando esa
        /// capa), el arco de eje saldria tambien azul en vez de gris, distinto del
        /// eje de los tramos rectos (que si es una linea suelta en AxisLayer).
        /// </summary>
        public static ObjectId EnsureElbowBlock(Transaction tr, Database db, double angleDegAbs)
        {
            double snapped = Math.Round(angleDegAbs / CventConfig.AngleStepCircular) * CventConfig.AngleStepCircular;
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

            DrawingUtil.DrawArc(tr, btr, center, innerRadius, angleT1, angleT2, CventConfig.WallLayer);
            DrawingUtil.DrawArc(tr, btr, center, bendRadius, angleT1, angleT2, CventConfig.AxisLayer);
            DrawingUtil.DrawArc(tr, btr, center, outerRadius, angleT1, angleT2, CventConfig.WallLayer);

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

        /// <summary>Nombre del bloque de rotulo (uno por tipo de conducto: los
        /// atributos que lleva son distintos -circular no tiene ALTO-).</summary>
        public static string LabelBlockName(string tipo) => tipo == "Circular" ? "CVENT_ROTULO_CIRC" : "CVENT_ROTULO_RECT";

        /// <summary>
        /// Bloque de rotulo (ANCHO/diametro, ALTO -solo rectangular-, LARGO), a una
        /// altura de linea de referencia (1) que se escala UNIFORMEMENTE al
        /// insertarse (ScaleFactors = alturaTexto en X e Y) -a diferencia de los
        /// bloques de tramo recto/reduccion, este bloque NUNCA se estira de forma
        /// distinta en X que en Y, asi que SetAttributeFromBlock calcula bien
        /// Height/WidthFactor sin ningun ajuste a mano (el mismo mecanismo, sin
        /// problemas, que ya usaba el bloque de codo). Este bloque no lleva ninguna
        /// pared ni geometria de conducto -es solo el rotulo-, y se inserta aparte
        /// en el punto medio de cada tramo, independientemente de si las paredes de
        /// ese tramo son un bloque (circular) o lineas sueltas (rectangular): asi el
        /// rotulo siempre queda vinculado al bloque (atributo real, extraible con
        /// DATAEXTRACTION/BATTMAN) sin depender de como se dibujen las paredes.
        /// </summary>
        public static ObjectId EnsureLabelBlock(Transaction tr, Database db, string tipo)
        {
            string name = LabelBlockName(tipo);
            BlockTableRecord btr = GetOrCreateEmptyBlock(tr, db, name);
            if (btr == null) return ExistingId(tr, db, name);

            // Circular: ANCHO (diametro) visible, LARGO solo consultable en
            // Propiedades (Invisible=true). Rectangular: ANCHOxLARGO en una misma
            // fila -"x" es texto estatico (no atributo), para que ANCHO y LARGO
            // sigan siendo valores numericos puros y extraibles por separado
            // (DATAEXTRACTION/BATTMAN)-, con ALTO disponible pero solo en
            // Propiedades. Un codo fuerza ademas TODOS sus atributos a invisibles al
            // insertar (vease InsertLabel/forceInvisible), asi que esta visibilidad
            // por defecto solo afecta a los tramos rectos/reducciones.
            const double lineH = 1.0;
            const double lineGap = 1.4;
            if (tipo == "Circular")
            {
                AddAttDef(tr, btr, "ANCHO", "Diametro", new Point2d(0, 0), lineH, "%%C0", false);
                AddAttDef(tr, btr, "LARGO", "Largo", new Point2d(0, -lineGap), lineH, "0", true);
            }
            else
            {
                // Huecos generosos (ANCHO y LARGO pueden tener hasta 4-5 cifras en
                // mm) para que no se solapen entre si ni con el separador "x".
                AddAttDef(tr, btr, "ANCHO", "Ancho", new Point2d(0, 0), lineH, "0", false);
                AddStaticText(tr, btr, "x", new Point2d(3.0, 0), lineH);
                AddAttDef(tr, btr, "LARGO", "Largo", new Point2d(3.6, 0), lineH, "0", false);
                AddAttDef(tr, btr, "ALTO", "Alto", new Point2d(0, -lineGap), lineH, "0", true);
            }

            return btr.ObjectId;
        }

        /// <summary>Bloque de rotulo usado EXCLUSIVAMENTE para la seccion de un codo
        /// (forceInvisible en InsertLabel): solo atributos, ninguna geometria fija
        /// (ni el separador "x" del bloque de tramo recto) -una entidad no-atributo
        /// dentro de un bloque SIEMPRE se ve, pase lo que pase con los atributos, asi
        /// que un codo insertado con el bloque de tramo recto dejaria el "x" (y, si
        /// ATTDISP esta en Activado, tambien los numeros) visibles en el dibujo pese
        /// a forceInvisible-. En circular no hace falta -su bloque de tramo recto ya
        /// no tiene ninguna geometria fija-, asi que reutiliza el mismo.</summary>
        public static ObjectId EnsureCodoLabelBlock(Transaction tr, Database db, string tipo)
        {
            if (tipo == "Circular") return EnsureLabelBlock(tr, db, tipo);

            string name = "CVENT_ROTULO_RECT_CODO";
            BlockTableRecord btr = GetOrCreateEmptyBlock(tr, db, name);
            if (btr == null) return ExistingId(tr, db, name);

            const double lineH = 1.0;
            const double lineGap = 1.4;
            AddAttDef(tr, btr, "ANCHO", "Ancho", new Point2d(0, 0), lineH, "0", true);
            AddAttDef(tr, btr, "ALTO", "Alto", new Point2d(0, -lineGap), lineH, "0", true);
            AddAttDef(tr, btr, "LARGO", "Largo", new Point2d(0, -2.0 * lineGap), lineH, "0", true);

            return btr.ObjectId;
        }

        private static void AddAttDef(Transaction tr, BlockTableRecord btr, string tag, string prompt, Point2d pos, double height, string defaultValue, bool invisible)
        {
            var attDef = new AttributeDefinition
            {
                Position = new Point3d(pos.X, pos.Y, 0),
                Height = height,
                Tag = tag,
                Prompt = prompt,
                TextString = defaultValue,
                Justify = AttachmentPoint.BaseLeft,
                Layer = "0",
                Invisible = invisible,
            };
            btr.AppendEntity(attDef);
            tr.AddNewlyCreatedDBObject(attDef, true);
        }

        /// <summary>Texto fijo (no atributo, no varia entre inserciones) dentro de un
        /// bloque -aqui, el separador "x" entre ANCHO y LARGO en el rotulo
        /// rectangular-.</summary>
        private static void AddStaticText(Transaction tr, BlockTableRecord btr, string text, Point2d pos, double height)
        {
            var dbText = new DBText
            {
                Position = new Point3d(pos.X, pos.Y, 0),
                Height = height,
                TextString = text,
                Layer = "0",
            };
            btr.AppendEntity(dbText);
            tr.AddNewlyCreatedDBObject(dbText, true);
        }

        /// <summary>Inserta el rotulo de un tramo (desplazado por fuera de la pared,
        /// orientado segun la direccion del tramo) con sus atributos ya rellenos.
        /// textHeight es la altura de texto REAL que se quiera en el dibujo, y offset
        /// la separacion REAL entre el rotulo y la pared -ambos elegidos por el
        /// usuario al principio de CVENT, para la escala que le convenga-.
        /// forceInvisible fuerza TODOS los atributos a invisibles en el dibujo (pero
        /// consultables en Propiedades) sea cual sea su visibilidad por defecto -se
        /// usa para el rotulo de un codo, donde solo interesa la seccion en
        /// Propiedades, nunca dibujada-. centerT (0..1) es la posicion a lo largo de
        /// start-end donde se centra el rotulo -0.5 (el centro) salvo que
        /// InsertLabels reparta varios rotulos a lo largo del mismo tramo-.</summary>
        public static BlockReference InsertLabel(Transaction tr, Database db, BlockTableRecord owner, Point2d start, Point2d end, double ancho, double alto, double largo, double textHeight, double offset, string tipo, bool forceInvisible = false, double centerT = 0.5)
        {
            Vector2d dir = GeometryUtil.UnitVector(start, end);
            Vector2d perp = GeometryUtil.LeftNormal(dir);
            var mid = new Point2d(start.X + (end.X - start.X) * centerT, start.Y + (end.Y - start.Y) * centerT);
            double margin = ancho / 2.0 + offset;
            var pos = new Point2d(mid.X + perp.X * margin, mid.Y + perp.Y * margin);

            // Igual que cualquier rotulo de texto en CAD: si el tramo apunta hacia la
            // mitad "de vuelta" (mas de 90 grados respecto a la horizontal), el texto
            // saldria boca abajo o al reves. Se gira 180 grados para que siempre se lea
            // de izquierda a derecha.
            double rot = GeometryUtil.VectorAngle(dir);
            if (Math.Abs(rot) > Math.PI / 2.0) rot = GeometryUtil.NormPi(rot + Math.PI);

            ObjectId id = forceInvisible ? EnsureCodoLabelBlock(tr, db, tipo) : EnsureLabelBlock(tr, db, tipo);
            var br = new BlockReference(new Point3d(pos.X, pos.Y, 0), id)
            {
                Rotation = rot,
                ScaleFactors = new Scale3d(textHeight, textHeight, 1.0),
                Layer = CventConfig.WallLayer,
            };
            owner.AppendEntity(br);
            tr.AddNewlyCreatedDBObject(br, true);

            var btr = (BlockTableRecord)tr.GetObject(id, OpenMode.ForRead);
            foreach (ObjectId defId in btr)
            {
                var defEnt = tr.GetObject(defId, OpenMode.ForRead);
                if (defEnt is AttributeDefinition attDef && !attDef.Constant)
                {
                    var attRef = new AttributeReference();
                    attRef.SetAttributeFromBlock(attDef, br.BlockTransform);
                    if (forceInvisible) attRef.Invisible = true;
                    if (string.Equals(attDef.Tag, "ANCHO", StringComparison.OrdinalIgnoreCase))
                        attRef.TextString = tipo == "Circular" ? "%%C" + ancho.ToString("0") : ancho.ToString("0");
                    else if (string.Equals(attDef.Tag, "ALTO", StringComparison.OrdinalIgnoreCase))
                        attRef.TextString = alto.ToString("0");
                    else if (string.Equals(attDef.Tag, "LARGO", StringComparison.OrdinalIgnoreCase))
                        attRef.TextString = largo.ToString("0");
                    br.AttributeCollection.AppendAttribute(attRef);
                    tr.AddNewlyCreatedDBObject(attRef, true);
                }
            }
            return br;
        }

        /// <summary>Inserta el/los rotulo(s) de un tramo YA CERRADO (start-end
        /// reales): uno solo, centrado (igual que InsertLabel), si repeatDist es 0 o
        /// el tramo es mas corto que repeatDist; si no, uno cada repeatDist unidades
        /// de dibujo a lo largo de TODO el tramo -para que un tramo muy largo no
        /// dependa de un unico rotulo en su punto medio, y el usuario decida la
        /// frecuencia-.</summary>
        public static void InsertLabels(Transaction tr, Database db, BlockTableRecord owner, Point2d start, Point2d end, double ancho, double alto, double largo, double textHeight, double offset, double repeatDist, string tipo)
        {
            double len = start.GetDistanceTo(end);
            if (repeatDist <= 1e-6 || len <= repeatDist)
            {
                InsertLabel(tr, db, owner, start, end, ancho, alto, largo, textHeight, offset, tipo);
                return;
            }
            for (double d = repeatDist / 2.0; d < len; d += repeatDist)
            {
                InsertLabel(tr, db, owner, start, end, ancho, alto, largo, textHeight, offset, tipo, forceInvisible: false, centerT: d / len);
            }
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

        /// <summary>Si esta pieza se dibujo como bloque (tramo recto o reduccion), su
        /// ObjectId -para poder RECORTARLO despues si el vertice de salida resulta
        /// ser un codo (el bloque se inserta con la longitud completa al primer
        /// clic, antes de saber si ese punto sera un codo o no; ver
        /// DuctTracer.AdjustBodyLength)-. ObjectId.Null si no aplica.</summary>
        public ObjectId BodyBlockId = ObjectId.Null;

        /// <summary>Punto real de inicio del cuerpo (bloque) de esta pieza -para
        /// recalcular su longitud en AdjustBodyLength-.</summary>
        public Point2d BodyStartPt;

        /// <summary>Tipo de conducto de esta pieza ("Circular"/"Rectangular") -para
        /// saber que bloque de rotulo (BlockFactory.EnsureLabelBlock) usar al cerrar
        /// la pieza-.</summary>
        public string Tipo;

        /// <summary>Alto (solo conductos rectangulares; 0 en circular). No influye en
        /// la geometria en planta -Radius*2 ya hace de "ancho" para ambos tipos-,
        /// solo se usa para rellenar el atributo ALTO del rotulo.</summary>
        public double Alto;

        /// <summary>Altura de texto real (en unidades de dibujo) que se quiere para
        /// el rotulo de esta pieza -la elige el usuario al principio de CVENT, segun
        /// la escala con la que vaya a trabajar-.</summary>
        public double TextHeight;

        /// <summary>Separacion (en unidades de dibujo) entre el rotulo y la pared del
        /// conducto -la elige el usuario al principio de CVENT-.</summary>
        public double LabelOffset;

        /// <summary>Cada cuantas unidades de dibujo se repite el rotulo a lo largo de
        /// un mismo tramo recto; 0 o menor = un solo rotulo, en el centro del tramo
        /// (comportamiento anterior) -tambien lo elige el usuario al principio de
        /// CVENT-.</summary>
        public double LabelRepeat;
    }

    /// <summary>
    /// El algoritmo de trazado propiamente dicho: cierre a inglete entre piezas,
    /// codos curvos con marcas delimitadoras, y el remate final del recorrido.
    /// </summary>
    internal static class DuctTracer
    {
        public static PendingPiece ProcessNextPiece(Transaction tr, Database db, BlockTableRecord ms, PendingPiece oldPending, Point2d startPt, Point2d endPt, double startRadius, double endRadius)
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
                BlockFactory.InsertLabels(tr, db, ms, oldPending.CenterStart, startPt, oldPending.Radius * 2.0, oldPending.Alto,
                    oldPending.CenterStart.GetDistanceTo(startPt), oldPending.TextHeight, oldPending.LabelOffset, oldPending.LabelRepeat, oldPending.Tipo);

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
        public static PendingPiece DrawPiece(Transaction tr, Database db, BlockTableRecord ms, PendingPiece oldPending, Point2d startPt, Point2d endPt, double startRadius, double endRadius, bool useBlocks, string tipo, double alto, double textHeight, double labelOffset, double labelRepeat)
        {
            bool drewBlock = false;
            ObjectId bodyId = ObjectId.Null;
            if (useBlocks)
            {
                Vector2d dir = GeometryUtil.UnitVector(startPt, endPt);
                double dirAngle = GeometryUtil.VectorAngle(dir);
                double length = startPt.GetDistanceTo(endPt);
                BlockReference br = Math.Abs(startRadius - endRadius) < 1e-9
                    ? BlockFactory.InsertStraight(tr, db, ms, startPt, dirAngle, length, 2.0 * startRadius)
                    : BlockFactory.InsertReduction(tr, db, ms, startPt, dirAngle, length, 2.0 * startRadius, 2.0 * endRadius);
                bodyId = br.ObjectId;
                drewBlock = true;
            }

            PendingPiece pending = ProcessNextPiece(tr, db, ms, oldPending, startPt, endPt, startRadius, endRadius);
            pending.WallsAlreadyDrawn = drewBlock;
            pending.BodyBlockId = bodyId;
            pending.BodyStartPt = startPt;
            pending.Tipo = tipo;
            pending.Alto = alto;
            pending.TextHeight = textHeight;
            pending.LabelOffset = labelOffset;
            pending.LabelRepeat = labelRepeat;
            return pending;
        }

        /// <summary>Recorta (o alarga) el bloque de cuerpo de "piece" -tramo recto o
        /// reduccion- para que termine exactamente en newEndPt, en vez de en el
        /// vertice bruto con el que se inserto la primera vez (el bloque se inserta
        /// al hacer clic en el punto, antes de saber si ese punto se convertira en un
        /// codo; solo entonces, aqui, se sabe el punto de tangencia real donde debe
        /// terminar). El rotulo de esta pieza (si tiene) se inserta aparte, ya en su
        /// posicion final, cuando se cierra la pieza -no antes-, asi que no hace
        /// falta reajustar nada mas aqui. No hace nada si "piece" no se dibujo como
        /// bloque.</summary>
        private static void AdjustBodyLength(Transaction tr, PendingPiece piece, Point2d newEndPt)
        {
            if (!piece.WallsAlreadyDrawn || piece.BodyBlockId.IsNull) return;

            var br = (BlockReference)tr.GetObject(piece.BodyBlockId, OpenMode.ForWrite);
            double newLength = piece.BodyStartPt.GetDistanceTo(newEndPt);
            if (newLength < 1e-6) newLength = 1e-6;
            br.ScaleFactors = new Scale3d(newLength, br.ScaleFactors.Y, br.ScaleFactors.Z);
        }

        /// <summary>Codo CURVO circular entre el final de la pieza pendiente y el
        /// inicio de la pieza siguiente, dado el giro turnAngle (radianes, con
        /// signo: + = izquierda, - = derecha) en el vertice compartido. Solo se
        /// llama para conductos circulares -un codo rectangular real es un miter
        /// recto sin radio, resuelto directamente por ProcessNextPiece, vease
        /// DuctRunner.TraceDuctRun-. Remata la pieza pendiente en el punto de
        /// tangencia de entrada, dibuja el codo (bloque de 3 arcos concentricos) y
        /// las dos marcas perpendiculares de inicio/fin. Devuelve la pieza
        /// siguiente, arrancando en el punto de tangencia de salida.</summary>
        public static PendingPiece ProcessElbow(Transaction tr, Database db, BlockTableRecord ms, PendingPiece oldPending, Point2d vertexPt, Point2d newEndPt, double turnAngle)
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

            Point2d t1 = new Point2d(vertexPt.X - dirIn.X * d, vertexPt.Y - dirIn.Y * d);
            Point2d t2 = new Point2d(vertexPt.X + dirOut.X * d, vertexPt.Y + dirOut.Y * d);

            // --- rematar la pieza pendiente hasta el punto de tangencia de entrada ---
            Point2d t1L = GeometryUtil.OffsetPoint(t1, dirIn, radius);
            Point2d t1R = GeometryUtil.OffsetPoint(t1, dirIn, -radius);
            if (!oldPending.WallsAlreadyDrawn)
            {
                DrawingUtil.DrawLine(tr, ms, oldPending.FinalStartL, t1L, CventConfig.WallLayer);
                DrawingUtil.DrawLine(tr, ms, oldPending.FinalStartR, t1R, CventConfig.WallLayer);
            }
            else
            {
                // La pared de la pieza pendiente ya es un bloque, insertado con la
                // longitud completa hasta el vertice bruto (antes de saber que ese
                // vertice seria un codo) -se recorta ahora para que termine justo en
                // el punto de tangencia t1, igual que el eje.
                AdjustBodyLength(tr, oldPending, t1);
            }
            DrawingUtil.DrawLine(tr, ms, oldPending.CenterStart, t1, CventConfig.AxisLayer);
            BlockFactory.InsertLabels(tr, db, ms, oldPending.CenterStart, t1, oldPending.Radius * 2.0, oldPending.Alto,
                oldPending.CenterStart.GetDistanceTo(t1), oldPending.TextHeight, oldPending.LabelOffset, oldPending.LabelRepeat, oldPending.Tipo);
            DrawingUtil.DrawLine(tr, ms, t1L, t1R, CventConfig.WallLayer); // marca perpendicular: inicio del codo

            // --- el codo en si: bloque curvo ---
            BlockFactory.InsertElbow(tr, db, ms, t1, GeometryUtil.VectorAngle(dirIn), GeometryUtil.Rtd(turnAngle), 2.0 * radius);

            // --- marca perpendicular: fin del codo ---
            Point2d t2L = GeometryUtil.OffsetPoint(t2, dirOut, radius);
            Point2d t2R = GeometryUtil.OffsetPoint(t2, dirOut, -radius);
            DrawingUtil.DrawLine(tr, ms, t2L, t2R, CventConfig.WallLayer);

            // Seccion del codo: solo consultable en Propiedades, nunca dibujada
            // (forceInvisible) -a diferencia del rotulo de un tramo recto, donde
            // ANCHO (y, en rectangular, tambien LARGO) si se ven-.
            BlockFactory.InsertLabel(tr, db, ms, t1, t2, 2.0 * radius, oldPending.Alto, 0.0, oldPending.TextHeight, oldPending.LabelOffset, oldPending.Tipo, forceInvisible: true);

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
                Tipo = oldPending.Tipo,
                Alto = oldPending.Alto,
                TextHeight = oldPending.TextHeight,
                LabelOffset = oldPending.LabelOffset,
                LabelRepeat = oldPending.LabelRepeat,
            };
        }

        /// <summary>Dibuja la ultima pieza pendiente (el extremo abierto del
        /// conducto): no hay tramo siguiente con el que empalmar, asi que se usa su
        /// final tal cual se calculo.</summary>
        public static void FlushPending(Transaction tr, Database db, BlockTableRecord ms, PendingPiece pending)
        {
            if (pending == null) return;
            if (!pending.WallsAlreadyDrawn)
            {
                DrawingUtil.DrawLine(tr, ms, pending.FinalStartL, pending.NaiveEndL, CventConfig.WallLayer);
                DrawingUtil.DrawLine(tr, ms, pending.FinalStartR, pending.NaiveEndR, CventConfig.WallLayer);
            }
            DrawingUtil.DrawLine(tr, ms, pending.CenterStart, pending.CenterEnd, CventConfig.AxisLayer);
            BlockFactory.InsertLabels(tr, db, ms, pending.CenterStart, pending.CenterEnd, pending.Radius * 2.0, pending.Alto,
                pending.CenterStart.GetDistanceTo(pending.CenterEnd), pending.TextHeight, pending.LabelOffset, pending.LabelRepeat, pending.Tipo);
        }

        /// <summary>Calcula el punto siguiente ajustado (si restrictMode y hay una
        /// direccion anterior) y el angulo de giro final con signo: + = izquierda, -
        /// = derecha. Si es el primer tramo del recorrido (lastDir nulo), angulo =
        /// 0. angleStepDeg es el incremento de giro admitido (15 en circular y en
        /// rectangular, hasta 90).</summary>
        public static (Point2d point, double turnAngleRad) ResolveNextPoint(Point2d p0, Point2d pt, Vector2d? lastDir, bool restrictMode, double angleStepDeg)
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
                double snappedDeg = GeometryUtil.RoundTo(GeometryUtil.Rtd(deflection), angleStepDeg);
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
        public static void TraceDuctRun(Database db, Editor ed, string tipo, double diam, double alto, double textHeight, double labelOffset, double labelRepeat, Point2d p0, PendingPiece pending, Vector2d? lastDir, bool restrictAngles, string cmdTag)
        {
            // Circular: bloques para tramo/reduccion/codo (todos generados por
            // BlockFactory), con codos CURVOS via ProcessElbow. Rectangular: sin
            // bloques de pared (una pared a inglete no se puede representar
            // estirando en X un bloque de extremos siempre perpendiculares) y SIN
            // bloque de codo tampoco -un codo rectangular real es un simple miter
            // recto, sin radio: las paredes de cada tramo se cortan en su
            // interseccion exacta, que ProcessNextPiece ya calcula para cualquier
            // angulo, mas abajo, al cerrar cada pieza-. El rotulo de cada tramo
            // (bloque CVENT_ROTULO_CIRC/RECT, con sus atributos ANCHO/ALTO/LARGO) se
            // inserta siempre, aparte de las paredes, al cerrar cada pieza; los
            // angulos normalizados (multiplos de 15, hasta 90) son los mismos en
            // ambos tipos.
            bool useBlocks = tipo == "Circular";
            double angleStep = CventConfig.AngleStepCircular;
            string dimKeyword = tipo == "Circular" ? "Diametro" : "Ancho";

            double? pendDiam = null;
            double pendAlto = alto;
            int segCount = 0, redCount = 0, elbowCount = 0;
            bool done = false;

            while (!done)
            {
                var pko = new PromptPointOptions($"\n[{cmdTag}] Punto siguiente [{dimKeyword}/Libre/Salir] <Salir>: ")
                {
                    UseBasePoint = true,
                    BasePoint = new Point3d(p0.X, p0.Y, 0),
                    AllowNone = true,
                };
                pko.Keywords.Add(dimKeyword);
                pko.Keywords.Add("Libre");
                pko.Keywords.Add("Salir");
                var ppr = ed.GetPoint(pko);

                if (ppr.Status == PromptStatus.None) { done = true; continue; }
                if (ppr.Status == PromptStatus.Keyword)
                {
                    if (ppr.StringResult == dimKeyword)
                    {
                        double def = pendDiam ?? diam;
                        var pdo = new PromptDistanceOptions($"\n[{cmdTag}] Nuevo {(tipo == "Circular" ? "diametro" : "ancho")}: ")
                        {
                            AllowNegative = false,
                            AllowZero = false,
                            DefaultValue = def,
                            UseDefaultValue = true,
                        };
                        var pdr = ed.GetDistance(pdo);
                        pendDiam = pdr.Status == PromptStatus.OK ? pdr.Value : def;

                        if (tipo == "Rectangular")
                        {
                            var pdoAlto = new PromptDistanceOptions($"\n[{cmdTag}] Nuevo alto: ")
                            {
                                AllowNegative = false,
                                AllowZero = false,
                                DefaultValue = pendAlto,
                                UseDefaultValue = true,
                            };
                            var pdrAlto = ed.GetDistance(pdoAlto);
                            pendAlto = pdrAlto.Status == PromptStatus.OK ? pdrAlto.Value : pendAlto;
                        }
                    }
                    else if (ppr.StringResult == "Libre")
                    {
                        restrictAngles = !restrictAngles;
                        ed.WriteMessage(restrictAngles
                            ? $"\n[{cmdTag}] Giros restringidos a multiplos de 15 grados (maximo 90)."
                            : $"\n[{cmdTag}] Giros libres (sin restriccion de angulo).");
                    }
                    else if (ppr.StringResult == "Salir")
                    {
                        done = true;
                    }
                    continue;
                }
                if (ppr.Status != PromptStatus.OK) { done = true; continue; }

                Point2d pt = new Point2d(ppr.Value.X, ppr.Value.Y);
                (Point2d resolvedPt, double turnAngle) = DuctTracer.ResolveNextPoint(p0, pt, lastDir, restrictAngles, angleStep);
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
                        if (tipo == "Circular")
                        {
                            pending = DuctTracer.ProcessElbow(tr, db, ms, pending, p0, pt, turnAngle);
                            effectiveStart = pending.CenterStart;
                        }
                        else
                        {
                            // Rectangular: un codo real es un miter recto -sin radio,
                            // sin bisel, sin zona delimitada-: las paredes de cada
                            // tramo simplemente se cortan en su interseccion exacta,
                            // que ProcessNextPiece ya calcula (mas abajo, al cerrar
                            // esta pieza) para cualquier angulo. Aqui solo se deja su
                            // seccion consultable en Propiedades -nunca dibujada-.
                            BlockFactory.InsertLabel(tr, db, ms, p0, pt, diam, alto, 0.0, textHeight, labelOffset, tipo, forceInvisible: true);
                        }
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

                        pending = DuctTracer.DrawPiece(tr, db, ms, pending, effectiveStart, pMid, diam / 2.0, pendDiam.Value / 2.0, useBlocks, tipo, alto, textHeight, labelOffset, labelRepeat);
                        redCount++;

                        if (pMid.GetDistanceTo(pt) > 1e-6)
                        {
                            pending = DuctTracer.DrawPiece(tr, db, ms, pending, pMid, pt, pendDiam.Value / 2.0, pendDiam.Value / 2.0, useBlocks, tipo, pendAlto, textHeight, labelOffset, labelRepeat);
                            segCount++;
                        }
                        diam = pendDiam.Value;
                        alto = pendAlto;
                        pendDiam = null;
                    }
                    else
                    {
                        pending = DuctTracer.DrawPiece(tr, db, ms, pending, effectiveStart, pt, diam / 2.0, diam / 2.0, useBlocks, tipo, alto, textHeight, labelOffset, labelRepeat);
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
                DuctTracer.FlushPending(tr, db, ms, pending);
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

            DrawingUtil.EnsureAttDispNormal();
            using (Transaction tr = db.TransactionManager.StartTransaction())
            {
                DrawingUtil.EnsureLayer(tr, db, CventConfig.WallLayer, CventConfig.WallColor);
                DrawingUtil.EnsureLayer(tr, db, CventConfig.AxisLayer, CventConfig.AxisColor);
                tr.Commit();
            }

            var pkoTipo = new PromptKeywordOptions("\n[CVENT] Tipo de conducto [Circular/Rectangular] <Circular>: ") { AllowNone = true };
            pkoTipo.Keywords.Add("Circular");
            pkoTipo.Keywords.Add("Rectangular");
            pkoTipo.Keywords.Default = "Circular";
            var pkrTipo = ed.GetKeywords(pkoTipo);
            if (pkrTipo.Status == PromptStatus.Cancel) { ed.WriteMessage("\n[CVENT] Cancelado."); return; }
            string tipo = (pkrTipo.Status == PromptStatus.OK && !string.IsNullOrEmpty(pkrTipo.StringResult)) ? pkrTipo.StringResult : "Circular";

            double diam, alto = 0.0;
            if (tipo == "Circular")
            {
                var pdo = new PromptDistanceOptions("\n[CVENT] Diametro inicial del conducto: ")
                {
                    AllowNegative = false,
                    AllowZero = false,
                    DefaultValue = 200.0,
                    UseDefaultValue = true,
                };
                var pdr = ed.GetDistance(pdo);
                diam = pdr.Status == PromptStatus.OK ? pdr.Value : 200.0;
            }
            else
            {
                var pdoAncho = new PromptDistanceOptions("\n[CVENT] Ancho inicial del conducto: ")
                {
                    AllowNegative = false,
                    AllowZero = false,
                    DefaultValue = 400.0,
                    UseDefaultValue = true,
                };
                var pdrAncho = ed.GetDistance(pdoAncho);
                diam = pdrAncho.Status == PromptStatus.OK ? pdrAncho.Value : 400.0;

                var pdoAlto = new PromptDistanceOptions("\n[CVENT] Alto inicial del conducto: ")
                {
                    AllowNegative = false,
                    AllowZero = false,
                    DefaultValue = 200.0,
                    UseDefaultValue = true,
                };
                var pdrAlto = ed.GetDistance(pdoAlto);
                alto = pdrAlto.Status == PromptStatus.OK ? pdrAlto.Value : 200.0;
            }

            var pdoTexto = new PromptDistanceOptions("\n[CVENT] Altura del texto de los rotulos (ANCHO/ALTO/LARGO), segun la escala de dibujo: ")
            {
                AllowNegative = false,
                AllowZero = false,
                DefaultValue = 2.5,
                UseDefaultValue = true,
            };
            var pdrTexto = ed.GetDistance(pdoTexto);
            double textHeight = pdrTexto.Status == PromptStatus.OK ? pdrTexto.Value : 2.5;

            var pdoOffset = new PromptDistanceOptions("\n[CVENT] Separacion entre el rotulo y la pared del conducto: ")
            {
                AllowNegative = false,
                AllowZero = true,
                DefaultValue = textHeight,
                UseDefaultValue = true,
            };
            var pdrOffset = ed.GetDistance(pdoOffset);
            double labelOffset = pdrOffset.Status == PromptStatus.OK ? pdrOffset.Value : textHeight;

            var pdoRepeat = new PromptDistanceOptions("\n[CVENT] Repetir el rotulo cada... a lo largo de un tramo recto (0 = uno solo, en el centro): ")
            {
                AllowNegative = false,
                AllowZero = true,
                DefaultValue = 0.0,
                UseDefaultValue = true,
            };
            var pdrRepeat = ed.GetDistance(pdoRepeat);
            double labelRepeat = pdrRepeat.Status == PromptStatus.OK ? pdrRepeat.Value : 0.0;

            var pprFirst = ed.GetPoint("\n[CVENT] Punto inicial del conducto: ");
            if (pprFirst.Status != PromptStatus.OK) { ed.WriteMessage("\n[CVENT] Cancelado."); return; }
            Point2d p0 = new Point2d(pprFirst.Value.X, pprFirst.Value.Y);

            ed.WriteMessage("\n[CVENT] Giros restringidos a multiplos de 15 grados (maximo 90). Escribe \"Libre\" para alternar.");

            DuctRunner.TraceDuctRun(db, ed, tipo, diam, alto, textHeight, labelOffset, labelRepeat, p0, null, null, true, "CVENT");
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

            DrawingUtil.EnsureAttDispNormal();
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

            var pdoTexto = new PromptDistanceOptions("\n[CVENTT] Altura del texto de los rotulos (ANCHO/LARGO), segun la escala de dibujo: ")
            {
                AllowNegative = false,
                AllowZero = false,
                DefaultValue = 2.5,
                UseDefaultValue = true,
            };
            var pdrTexto = ed.GetDistance(pdoTexto);
            double textHeight = pdrTexto.Status == PromptStatus.OK ? pdrTexto.Value : 2.5;

            var pdoOffset = new PromptDistanceOptions("\n[CVENTT] Separacion entre el rotulo y la pared del conducto: ")
            {
                AllowNegative = false,
                AllowZero = true,
                DefaultValue = textHeight,
                UseDefaultValue = true,
            };
            var pdrOffset = ed.GetDistance(pdoOffset);
            double labelOffset = pdrOffset.Status == PromptStatus.OK ? pdrOffset.Value : textHeight;

            var pdoRepeat = new PromptDistanceOptions("\n[CVENTT] Repetir el rotulo cada... a lo largo de un tramo recto (0 = uno solo, en el centro): ")
            {
                AllowNegative = false,
                AllowZero = true,
                DefaultValue = 0.0,
                UseDefaultValue = true,
            };
            var pdrRepeat = ed.GetDistance(pdoRepeat);
            double labelRepeat = pdrRepeat.Status == PromptStatus.OK ? pdrRepeat.Value : 0.0;

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
                // CVENTT solo admite derivaciones circulares por ahora.
                DuctRunner.TraceDuctRun(db, ed, "Circular", branchDiam, 0.0, textHeight, labelOffset, labelRepeat, edgePoint, null, branchDir, true, "CVENTT");
            }
            else
            {
                Point2d edgePoint1 = MainDuctEdgePoint(mainAxisPt, mainDir, mainRadius, branchDir);
                DrawBranchStartMarkTx(db, edgePoint1, branchDir, branchRadius);
                ed.WriteMessage("\n[CVENTT] --- Trazando la primera derivacion (lado 1) ---");
                DuctRunner.TraceDuctRun(db, ed, "Circular", branchDiam, 0.0, textHeight, labelOffset, labelRepeat, edgePoint1, null, branchDir, true, "CVENTT");

                Vector2d branchDir2 = new Vector2d(-branchDir.X, -branchDir.Y);
                Point2d edgePoint2 = MainDuctEdgePoint(mainAxisPt, mainDir, mainRadius, branchDir2);
                DrawBranchStartMarkTx(db, edgePoint2, branchDir2, branchRadius);
                ed.WriteMessage("\n[CVENTT] --- Trazando la segunda derivacion (lado 2) ---");
                DuctRunner.TraceDuctRun(db, ed, "Circular", branchDiam, 0.0, textHeight, labelOffset, labelRepeat, edgePoint2, null, branchDir2, true, "CVENTT");
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
                double snappedDeg = GeometryUtil.RoundTo(GeometryUtil.Rtd(deflection), CventConfig.AngleStepCircular);
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
