using System;
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
    //
    // Cada PIEZA (tramo recto, reduccion, o codo) se dibuja como un UNICO
    // bloque: paredes + eje + su propio rotulo (ANCHO/ALTO/LARGO) como
    // atributos REALES del MISMO bloque -no de uno aparte-, construido ya a
    // su tamano final en coordenadas locales e insertado siempre a escala
    // UNIFORME (1,1,1) -nunca estirado despues-, vease BlockFactory. Cada
    // pieza es una definicion de bloque UNICA (nombre generado, no
    // reutilizado entre piezas): la geometria de cada una es distinta (largo,
    // esquinas a inglete con la vecina...), asi que no tiene sentido
    // compartir definicion entre instancias -a cambio, el rotulo queda
    // vinculado al bloque de la propia pieza, seleccionable como un unico
    // objeto, y al ser siempre escala uniforme, SetAttributeFromBlock calcula
    // bien Height/WidthFactor sin ningun ajuste a mano.
    //
    // Circular: codos CURVOS (tres arcos concentricos). Rectangular: un codo
    // real es un simple miter recto -sin radio, sin bisel-, asi que sus dos
    // paredes se cortan en su interseccion exacta (ya lo hace
    // DuctTracer.ProcessNextPiece para cualquier angulo); solo se anade una
    // marca de Propiedades (seccion, nunca dibujada) en el vertice.
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
        // igual en circular y rectangular. Tope maximo (grados), tambien igual
        // para ambos tipos.
        public const double AngleStepCircular = 15.0;
        public const double AngleMax = 90.0;

        // Por debajo de este angulo (grados) un giro se considera "recto", sin codo.
        public const double AngleEpsilonDeg = 1.0;

        // Radio de eje del codo = este factor x el diametro/ancho del conducto (SMACNA).
        public const double ElbowRadiusFactor = 1.5;

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

        /// <summary>Transforma un punto MUNDO a coordenadas LOCALES de un sistema con
        /// origen "origin" y eje +X apuntando a "dirAngle" (radianes) -el inverso de
        /// insertar un bloque en (origin, Rotation=dirAngle, escala uniforme 1).
        /// Es la base de BlockFactory.InsertPiece: cada pieza se construye en su
        /// propio sistema local y se inserta ya en su sitio real.</summary>
        public static Point2d ToLocal(Point2d world, Point2d origin, double dirAngle)
        {
            double dx = world.X - origin.X, dy = world.Y - origin.Y;
            double cos = Math.Cos(-dirAngle), sin = Math.Sin(-dirAngle);
            return new Point2d(dx * cos - dy * sin, dx * sin + dy * cos);
        }
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
        /// codo, que este plugin deja siempre invisible-, lo que parece un fallo del
        /// plugin sin serlo. CVENT y CVENTT llaman a esto al arrancar para que la
        /// visibilidad de cada rotulo dependa solo de su propio flag, como se
        /// espera. Es solo una comodidad -si SetSystemVariable falla por lo que sea
        /// no debe tirar abajo el comando entero: en el peor caso, queda pendiente
        /// de revisar a mano con el comando ATTDISP (opcion Normal).</summary>
        public static void EnsureAttDispNormal()
        {
            try { AcApp.SetSystemVariable("ATTDISP", (short)1); }
            catch (Autodesk.AutoCAD.Runtime.Exception) { }
        }
    }

    /// <summary>
    /// Construye e inserta cada PIEZA (tramo recto, reduccion, o codo) como un
    /// unico bloque: paredes + eje + su propio rotulo (ANCHO/ALTO/LARGO), ya
    /// dibujado a su tamano final, a escala siempre uniforme (1,1,1). Cada
    /// pieza es una definicion de bloque nueva (nombre generado por
    /// NextPieceName) -no se comparte entre piezas distintas-.
    /// </summary>
    internal static class BlockFactory
    {
        private static int _pieceCounter = 0;

        private static string NextPieceName(Transaction tr, Database db)
        {
            var bt = (BlockTable)tr.GetObject(db.BlockTableId, OpenMode.ForRead);
            string name;
            do { name = $"CVENT_PIEZA_{++_pieceCounter}"; } while (bt.Has(name));
            return name;
        }

        private static BlockTableRecord NewBlock(Transaction tr, Database db, string name)
        {
            var bt = (BlockTable)tr.GetObject(db.BlockTableId, OpenMode.ForWrite);
            var btr = new BlockTableRecord { Name = name };
            bt.Add(btr);
            tr.AddNewlyCreatedDBObject(btr, true);
            return btr;
        }

        /// <summary>Inserta un tramo recto o una reduccion YA CERRADO -con sus
        /// cuatro esquinas de pared reales, ya resueltas a inglete con las piezas
        /// vecinas- como UN UNICO bloque: las dos paredes, el eje, y su propio
        /// rotulo (ANCHO/ALTO/LARGO), todos en el MISMO bloque, insertado a escala
        /// SIEMPRE uniforme (1,1,1) -la geometria ya se construye a su tamano real
        /// en coordenadas locales, nunca se estira despues-, para que
        /// SetAttributeFromBlock calcule bien Height/WidthFactor sin ningun ajuste
        /// a mano. Asi el rotulo queda vinculado al MISMO bloque que la pared
        /// -seleccionable como un unico objeto-, no a uno aparte.</summary>
        public static void InsertPiece(Transaction tr, Database db, BlockTableRecord owner,
            Point2d originPt, Vector2d dir, Point2d startL, Point2d startR, Point2d endL, Point2d endR,
            Point2d centerEnd, double startRadius, double endRadius, double alto, double largo,
            double textHeight, double offset, string tipo)
        {
            double dirAngle = GeometryUtil.VectorAngle(dir);
            BlockTableRecord btr = NewBlock(tr, db, NextPieceName(tr, db));

            Point2d lStartL = GeometryUtil.ToLocal(startL, originPt, dirAngle);
            Point2d lStartR = GeometryUtil.ToLocal(startR, originPt, dirAngle);
            Point2d lEndL = GeometryUtil.ToLocal(endL, originPt, dirAngle);
            Point2d lEndR = GeometryUtil.ToLocal(endR, originPt, dirAngle);
            Point2d lCenterEnd = GeometryUtil.ToLocal(centerEnd, originPt, dirAngle);

            DrawingUtil.DrawLine(tr, btr, lStartL, lEndL, CventConfig.WallLayer);
            DrawingUtil.DrawLine(tr, btr, lStartR, lEndR, CventConfig.WallLayer);
            DrawingUtil.DrawLine(tr, btr, new Point2d(0, 0), lCenterEnd, CventConfig.AxisLayer);

            var br = new BlockReference(new Point3d(originPt.X, originPt.Y, 0), btr.ObjectId)
            {
                Rotation = dirAngle,
                Layer = CventConfig.WallLayer,
            };
            owner.AppendEntity(br);
            tr.AddNewlyCreatedDBObject(br, true);

            double rAvg = (startRadius + endRadius) / 2.0;
            Point2d localLabelCenter = new Point2d(lCenterEnd.X / 2.0, rAvg + offset);
            AddLabel(tr, btr, br, localLabelCenter, dirAngle, 2.0 * endRadius, alto, largo, textHeight, tipo, forceInvisible: false);
        }

        /// <summary>Codo curvo circular entre el punto de tangencia de entrada t1
        /// (direccion de entrada dirIn) y el giro turnAngleRad (radianes, con
        /// signo: + = izquierda, - = derecha): centro y arcos calculados
        /// directamente para el giro real, sin ningun truco de reflejo -al no
        /// compartirse definicion entre instancias, cada codo se construye ya
        /// para su propio angulo y diametro reales-. Un unico bloque: paredes,
        /// eje, y su seccion (ANCHO) como atributo SIEMPRE invisible en el
        /// dibujo -solo consultable en Propiedades-.</summary>
        public static void InsertElbowCircular(Transaction tr, Database db, BlockTableRecord owner,
            Point2d t1, Vector2d dirIn, double turnAngleRad, double diameter, double alto,
            double textHeight, double offset, string tipo)
        {
            double dirInAngle = GeometryUtil.VectorAngle(dirIn);
            BlockTableRecord btr = NewBlock(tr, db, NextPieceName(tr, db));

            double radius = diameter / 2.0;
            double bendRadius = CventConfig.ElbowRadiusFactor * diameter;
            bool left = turnAngleRad > 0.0;
            var origin = new Point2d(0, 0);
            var center = new Point2d(0, left ? bendRadius : -bendRadius);
            double angleT1 = GeometryUtil.AngleTo(center, origin);
            double angleT2 = angleT1 + turnAngleRad;
            double startAng, endAng;
            if (left) { startAng = angleT1; endAng = angleT2; } else { startAng = angleT2; endAng = angleT1; }
            if (endAng <= startAng) endAng += 2.0 * Math.PI;

            double innerRadius = Math.Max(bendRadius - radius, radius * 0.05);
            double outerRadius = bendRadius + radius;

            DrawingUtil.DrawArc(tr, btr, center, innerRadius, startAng, endAng, CventConfig.WallLayer);
            DrawingUtil.DrawArc(tr, btr, center, bendRadius, startAng, endAng, CventConfig.AxisLayer);
            DrawingUtil.DrawArc(tr, btr, center, outerRadius, startAng, endAng, CventConfig.WallLayer);

            var br = new BlockReference(new Point3d(t1.X, t1.Y, 0), btr.ObjectId)
            {
                Rotation = dirInAngle,
                Layer = CventConfig.WallLayer,
            };
            owner.AppendEntity(br);
            tr.AddNewlyCreatedDBObject(br, true);

            AddLabel(tr, btr, br, origin, dirInAngle, diameter, alto, 0.0, textHeight, tipo, forceInvisible: true);
        }

        /// <summary>Marca de Propiedades de un codo rectangular: un codo
        /// rectangular real es un simple miter recto -sin radio, sin bisel, sin
        /// bloque de pared propio-, las dos piezas rectas vecinas (cada una ya un
        /// InsertPiece) se cortan directamente en su interseccion exacta. Este
        /// bloque no lleva ninguna pared ni eje, solo la seccion (ANCHO/ALTO)
        /// como atributos SIEMPRE invisibles en el dibujo.</summary>
        public static void InsertCodoMarker(Transaction tr, Database db, BlockTableRecord owner,
            Point2d at, double ancho, double alto, double textHeight, string tipo)
        {
            BlockTableRecord btr = NewBlock(tr, db, NextPieceName(tr, db));
            var br = new BlockReference(new Point3d(at.X, at.Y, 0), btr.ObjectId) { Layer = CventConfig.WallLayer };
            owner.AppendEntity(br);
            tr.AddNewlyCreatedDBObject(br, true);
            AddLabel(tr, btr, br, new Point2d(0, 0), 0.0, ancho, alto, 0.0, textHeight, tipo, forceInvisible: true);
        }

        /// <summary>Anade, en btr (coordenadas locales del bloque que se esta
        /// construyendo) y ya instanciados como AttributeReference reales sobre
        /// br, los atributos ANCHO/ALTO/LARGO del rotulo de una pieza, centrados
        /// en localCenter. blockDirAngle es la Rotation real con la que se va a
        /// insertar el bloque -si esa direccion cae en la mitad "de vuelta" (mas
        /// de 90 grados de la horizontal), el rotulo se gira 180 grados el mismo
        /// (Rotation LOCAL del atributo, no la del bloque -asi la pared no se ve
        /// afectada-) para que el texto nunca salga boca abajo. Si forceInvisible,
        /// TODOS los atributos salen invisibles en el dibujo (solo Propiedades) y
        /// no se anade el separador "x" de rectangular -solo hace falta para el
        /// formato VISIBLE "ANCHOxLARGO" de un tramo recto-.</summary>
        private static void AddLabel(Transaction tr, BlockTableRecord btr, BlockReference br,
            Point2d localCenter, double blockDirAngle, double ancho, double alto, double largo,
            double textHeight, string tipo, bool forceInvisible)
        {
            double localRot = Math.Abs(GeometryUtil.NormPi(blockDirAngle)) > Math.PI / 2.0 ? Math.PI : 0.0;
            double lineGap = textHeight * 1.4;

            void AddAtt(string tag, string prompt, double localDx, double localDy, string text, bool invisible)
            {
                double dx = localDx * Math.Cos(localRot) - localDy * Math.Sin(localRot);
                double dy = localDx * Math.Sin(localRot) + localDy * Math.Cos(localRot);
                var pos = new Point3d(localCenter.X + dx, localCenter.Y + dy, 0);
                var attDef = new AttributeDefinition
                {
                    Position = pos,
                    Height = textHeight,
                    Tag = tag,
                    Prompt = prompt,
                    TextString = text,
                    // Justify DEBE fijarse antes que AlignmentPoint -al reves dispara
                    // eNotApplicable-. Para cualquier justificacion que no sea
                    // BaseLeft (aqui, MiddleCenter) hace falta ademas fijar
                    // AlignmentPoint -sin el, el texto se sigue alineando como si
                    // fuera BaseLeft pese al Justify-.
                    Justify = AttachmentPoint.MiddleCenter,
                    AlignmentPoint = pos,
                    Rotation = localRot,
                    Layer = "0",
                    Invisible = forceInvisible || invisible,
                };
                btr.AppendEntity(attDef);
                tr.AddNewlyCreatedDBObject(attDef, true);

                var attRef = new AttributeReference();
                attRef.SetAttributeFromBlock(attDef, br.BlockTransform);
                br.AttributeCollection.AppendAttribute(attRef);
                tr.AddNewlyCreatedDBObject(attRef, true);
            }

            if (tipo == "Circular")
            {
                AddAtt("ANCHO", "Diametro", 0, 0, "%%C" + ancho.ToString("0"), false);
                AddAtt("LARGO", "Largo", 0, -lineGap, largo.ToString("0"), true);
            }
            else
            {
                AddAtt("ANCHO", "Ancho", 0, 0, ancho.ToString("0"), false);
                AddAtt("LARGO", "Largo", textHeight * 3.6, 0, largo.ToString("0"), false);
                AddAtt("ALTO", "Alto", 0, -lineGap, alto.ToString("0"), true);
                if (!forceInvisible)
                {
                    double sepLocalX = textHeight * 3.0;
                    double dx = sepLocalX * Math.Cos(localRot);
                    double dy = sepLocalX * Math.Sin(localRot);
                    var sepPos = new Point3d(localCenter.X + dx, localCenter.Y + dy, 0);
                    var dbText = new DBText
                    {
                        Position = sepPos,
                        Height = textHeight,
                        Justify = AttachmentPoint.MiddleCenter,
                        AlignmentPoint = sepPos,
                        Rotation = localRot,
                        TextString = "x",
                        Layer = "0",
                    };
                    btr.AppendEntity(dbText);
                    tr.AddNewlyCreatedDBObject(dbText, true);
                }
            }
        }
    }

    /// <summary>
    /// Estado "pendiente" de una pieza (tramo recto, reduccion, o el tramo de salida
    /// de un codo) cuyas paredes/eje aun no se han dibujado del todo -solo se
    /// dibujan (como bloque, BlockFactory.InsertPiece) cuando se sabe exactamente
    /// donde deben terminar (inglete con la siguiente pieza, o tangencia con el
    /// siguiente codo)-.
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
        public double StartRadius;    // radio en el extremo inicial -para el rotulo de una reduccion-

        /// <summary>Tipo de conducto de esta pieza ("Circular"/"Rectangular").</summary>
        public string Tipo;

        /// <summary>Alto (solo conductos rectangulares; 0 en circular).</summary>
        public double Alto;

        /// <summary>Altura de texto real (en unidades de dibujo) que se quiere para
        /// el rotulo de esta pieza -la elige el usuario al principio de CVENT-.</summary>
        public double TextHeight;

        /// <summary>Separacion (en unidades de dibujo) entre el rotulo y la pared del
        /// conducto -la elige el usuario al principio de CVENT-.</summary>
        public double LabelOffset;
    }

    /// <summary>
    /// El algoritmo de trazado propiamente dicho: cierre a inglete entre piezas,
    /// codos curvos con marcas delimitadoras, y el remate final del recorrido.
    /// </summary>
    internal static class DuctTracer
    {
        /// <summary>Calcula el cierre a inglete de la pieza pendiente (si la habia)
        /// contra la pieza nueva que arranca en startPt, e INSERTA la pieza
        /// pendiente ya cerrada como un unico bloque (BlockFactory.InsertPiece).
        /// Devuelve el nuevo estado pendiente (aun sin dibujar) para la pieza que
        /// empieza ahora.</summary>
        public static PendingPiece ProcessNextPiece(Transaction tr, Database db, BlockTableRecord ms, PendingPiece oldPending, Point2d startPt, Point2d endPt, double startRadius, double endRadius, string tipo, double alto, double textHeight, double labelOffset)
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

                BlockFactory.InsertPiece(tr, db, ms, oldPending.CenterStart, oldPending.Dir,
                    oldPending.FinalStartL, oldPending.FinalStartR, jointL, jointR, startPt,
                    oldPending.StartRadius, oldPending.Radius, oldPending.Alto,
                    oldPending.CenterStart.GetDistanceTo(startPt), oldPending.TextHeight, oldPending.LabelOffset, oldPending.Tipo);

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
                StartRadius = startRadius,
                Tipo = tipo,
                Alto = alto,
                TextHeight = textHeight,
                LabelOffset = labelOffset,
            };
        }

        /// <summary>Codo CURVO circular entre el final de la pieza pendiente y el
        /// inicio de la pieza siguiente, dado el giro turnAngle (radianes, con
        /// signo: + = izquierda, - = derecha) en el vertice compartido. Solo se
        /// llama para conductos circulares -un codo rectangular real es un miter
        /// recto sin radio, resuelto directamente por ProcessNextPiece, vease
        /// DuctRunner.TraceDuctRun-. Cierra (inserta como bloque) la pieza
        /// pendiente hasta el punto de tangencia de entrada, inserta el codo
        /// (bloque de 3 arcos concentricos, con su propia seccion invisible) y las
        /// dos marcas perpendiculares de inicio/fin. Devuelve la pieza siguiente,
        /// arrancando en el punto de tangencia de salida.</summary>
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

            Point2d t1L = GeometryUtil.OffsetPoint(t1, dirIn, radius);
            Point2d t1R = GeometryUtil.OffsetPoint(t1, dirIn, -radius);

            // --- cerrar (insertar como bloque) la pieza pendiente hasta t1 ---
            BlockFactory.InsertPiece(tr, db, ms, oldPending.CenterStart, oldPending.Dir,
                oldPending.FinalStartL, oldPending.FinalStartR, t1L, t1R, t1,
                oldPending.StartRadius, oldPending.Radius, oldPending.Alto,
                oldPending.CenterStart.GetDistanceTo(t1), oldPending.TextHeight, oldPending.LabelOffset, oldPending.Tipo);

            DrawingUtil.DrawLine(tr, ms, t1L, t1R, CventConfig.WallLayer); // marca perpendicular: inicio del codo

            BlockFactory.InsertElbowCircular(tr, db, ms, t1, dirIn, turnAngle, 2.0 * radius, oldPending.Alto, oldPending.TextHeight, oldPending.LabelOffset, oldPending.Tipo);

            Point2d t2L = GeometryUtil.OffsetPoint(t2, dirOut, radius);
            Point2d t2R = GeometryUtil.OffsetPoint(t2, dirOut, -radius);
            DrawingUtil.DrawLine(tr, ms, t2L, t2R, CventConfig.WallLayer); // marca perpendicular: fin del codo

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
                StartRadius = radius,
                Tipo = oldPending.Tipo,
                Alto = oldPending.Alto,
                TextHeight = oldPending.TextHeight,
                LabelOffset = oldPending.LabelOffset,
            };
        }

        /// <summary>Cierra (inserta como bloque) la ultima pieza pendiente (el
        /// extremo abierto del conducto): no hay tramo siguiente con el que
        /// empalmar, asi que se usa su final tal cual se calculo.</summary>
        public static void FlushPending(Transaction tr, Database db, BlockTableRecord ms, PendingPiece pending)
        {
            if (pending == null) return;
            BlockFactory.InsertPiece(tr, db, ms, pending.CenterStart, pending.Dir,
                pending.FinalStartL, pending.FinalStartR, pending.NaiveEndL, pending.NaiveEndR, pending.CenterEnd,
                pending.StartRadius, pending.Radius, pending.Alto,
                pending.CenterStart.GetDistanceTo(pending.CenterEnd), pending.TextHeight, pending.LabelOffset, pending.Tipo);
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
        public static void TraceDuctRun(Database db, Editor ed, string tipo, double diam, double alto, double textHeight, double labelOffset, Point2d p0, PendingPiece pending, Vector2d? lastDir, bool restrictAngles, string cmdTag)
        {
            // Circular: codos CURVOS (bloque de 3 arcos) via ProcessElbow.
            // Rectangular: un codo real es un simple miter recto -sin radio, sin
            // bisel-: las paredes de cada tramo se cortan en su interseccion
            // exacta, que ProcessNextPiece ya calcula para cualquier angulo, al
            // cerrar cada pieza; solo se anade una marca de Propiedades (seccion,
            // nunca dibujada) en el vertice. Cada pieza (tramo, reduccion o codo)
            // se inserta siempre como un UNICO bloque -paredes, eje y su propio
            // rotulo juntos-, en los dos tipos por igual.
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
                            // Rectangular: el codo en si ya es un simple inglete,
                            // resuelto mas abajo por ProcessNextPiece (interseccion
                            // de paredes). Aqui solo se marca su seccion, siempre
                            // consultable en Propiedades, nunca dibujada.
                            BlockFactory.InsertCodoMarker(tr, db, ms, p0, diam, alto, textHeight, tipo);
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

                        pending = DuctTracer.ProcessNextPiece(tr, db, ms, pending, effectiveStart, pMid, diam / 2.0, pendDiam.Value / 2.0, tipo, alto, textHeight, labelOffset);
                        redCount++;

                        if (pMid.GetDistanceTo(pt) > 1e-6)
                        {
                            pending = DuctTracer.ProcessNextPiece(tr, db, ms, pending, pMid, pt, pendDiam.Value / 2.0, pendDiam.Value / 2.0, tipo, pendAlto, textHeight, labelOffset);
                            segCount++;
                        }
                        diam = pendDiam.Value;
                        alto = pendAlto;
                        pendDiam = null;
                    }
                    else
                    {
                        pending = DuctTracer.ProcessNextPiece(tr, db, ms, pending, effectiveStart, pt, diam / 2.0, diam / 2.0, tipo, alto, textHeight, labelOffset);
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

            var pprFirst = ed.GetPoint("\n[CVENT] Punto inicial del conducto: ");
            if (pprFirst.Status != PromptStatus.OK) { ed.WriteMessage("\n[CVENT] Cancelado."); return; }
            Point2d p0 = new Point2d(pprFirst.Value.X, pprFirst.Value.Y);

            ed.WriteMessage("\n[CVENT] Giros restringidos a multiplos de 15 grados (maximo 90). Escribe \"Libre\" para alternar.");

            DuctRunner.TraceDuctRun(db, ed, tipo, diam, alto, textHeight, labelOffset, p0, null, null, true, "CVENT");
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
                DuctRunner.TraceDuctRun(db, ed, "Circular", branchDiam, 0.0, textHeight, labelOffset, edgePoint, null, branchDir, true, "CVENTT");
            }
            else
            {
                Point2d edgePoint1 = MainDuctEdgePoint(mainAxisPt, mainDir, mainRadius, branchDir);
                DrawBranchStartMarkTx(db, edgePoint1, branchDir, branchRadius);
                ed.WriteMessage("\n[CVENTT] --- Trazando la primera derivacion (lado 1) ---");
                DuctRunner.TraceDuctRun(db, ed, "Circular", branchDiam, 0.0, textHeight, labelOffset, edgePoint1, null, branchDir, true, "CVENTT");

                Vector2d branchDir2 = new Vector2d(-branchDir.X, -branchDir.Y);
                Point2d edgePoint2 = MainDuctEdgePoint(mainAxisPt, mainDir, mainRadius, branchDir2);
                DrawBranchStartMarkTx(db, edgePoint2, branchDir2, branchRadius);
                ed.WriteMessage("\n[CVENTT] --- Trazando la segunda derivacion (lado 2) ---");
                DuctRunner.TraceDuctRun(db, ed, "Circular", branchDiam, 0.0, textHeight, labelOffset, edgePoint2, null, branchDir2, true, "CVENTT");
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
