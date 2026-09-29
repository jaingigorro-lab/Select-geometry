(vl-load-com)

;; ==========================================================
;; LIBJUEGOS - Dibuja en planta, a escala real, una ZONA DE LIBRERIA
;; Y JUEGOS para la parte de atras de un salon: el hueco que queda
;; detras del sofa, entre la fachada y un tabique en L. Con BLOQUES
;; DETALLADOS de cada mueble y, si se pide, sus ALZADOS y una SECCION.
;;
;; Concepto (pensado para un hueco de unos 3 x 3 m con dos accesos:
;; uno desde el pasillo, junto a la fachada, y otro por el hueco del
;; tabique inferior, ambos camino del sofa):
;;
;;   - LIBRERIA a medida contra la fachada (el tramo sin ventanas entre
;;     las dos ventanas): armario bajo con puertas de 40 cm de fondo
;;     para juegos de mesa, puzles y juguetes -las cajas de juego
;;     estandar miden unos 30 x 30 cm y no caben en una estanteria de
;;     libros normal-, encimera, y encima estantes abiertos de 30 cm
;;     para libros hasta 2,40 m. Modulos de 80 cm como maximo, para que
;;     las baldas no se comben con el peso de los libros.
;;
;;   - RINCON DE JUEGOS en la esquina del tabique en L (la parte mas
;;     recogida de la zona, fuera de los pasos): BANCO CORRIDO EN L
;;     con cajones bajo el asiento (mas almacenaje para juegos),
;;     cojines de asiento y de respaldo y dos cojines sueltos, MESA DE
;;     JUEGOS con pie central -la mayor medida estandar que quepa,
;;     normalmente 90 x 120- y sillas en el lado libre. Caben 5-6
;;     jugadores ocupando mucho menos que una mesa con sillas por los
;;     cuatro lados. Lampara colgante centrada sobre la mesa y un
;;     aplique de lectura con brazo en el extremo del banco.
;;
;;   - Se deja SIEMPRE un paso libre de 90 cm como minimo delante de
;;     la libreria (del pasillo al sofa) y junto al respaldo del sofa
;;     (del hueco inferior al sofa): la mesa, las sillas -contando el
;;     espacio para retirarlas y sentarse- y el banco se dimensionan
;;     para no invadirlos.
;;
;; Bloques (todos con su geometria detallada, en la capa 0 dentro del
;; bloque para que tomen la capa de la insercion; las lineas de
;; detalle van en gris -color 8- y finas, y las de corte, gruesas):
;;   - Planta: LJ_LIBRERIA_... (costados y baldas con su grueso,
;;     trasera, libros, pilas y plantas en los estantes), LJ_RINCON_...
;;     (banco y mesa juntos: la mesa vuela sobre el asiento y en planta
;;     tapa parte del banco -esas lineas no se dibujan-; cojines con
;;     vivo, cojines sueltos, tablero de tablas con veta y el pie
;;     central oculto, a trazos), LJ_SILLA_..., LJ_LAMPARA_... y
;;     LJ_APLIQUE_....
;;   - Alzados (opcionales): LJ_LIBRERIA_ALZ_... (zocalo, puertas con
;;     tiradores, encimera, baldas, libros de pie e inclinados, pilas,
;;     cajas y plantas), LJ_BANCO_ALZ_... (tramo largo: cajones con
;;     unero, cojines, aplique) y LJ_SECCION_... (seccion A-A por el
;;     banco, la mesa, una silla y la lampara, con el tabique rayado).
;; Capas: LJ-MOBILIARIO, LJ-ILUMINACION, LJ-ALZADOS, LJ-COTAS (cotas
;; dibujadas con lineas y texto, sin entidades de cota, y la marca de
;; la seccion A-A en planta) y LJ-TEXTOS. Toda la geometria se crea con
;; entmake -sin comandos ni metodos ActiveX-; la planta queda en un
;; paso de deshacer y los alzados en otro.
;;
;; Uso:
;;   1. Ejecutar LIBJUEGOS.
;;   2. Designar la ESQUINA INTERIOR del tabique en L, por el lado del
;;      salon (donde ira el banco): la interseccion de sus dos caras
;;      (referencia a objetos Interseccion).
;;   3. Designar la ESQUINA OPUESTA de la zona: sobre la cara interior
;;      de la fachada, en la linea del respaldo del sofa. Mientras se
;;      mueve el cursor se ve el rectangulo de la zona.
;;   4. Confirmar las unidades del dibujo con Intro (se proponen segun
;;      INSUNITS y el tamano de la zona designada).
;;   5. Intro para aceptar la orientacion: libreria contra el lado de
;;      la zona paralelo al eje X del SCP, el mas alejado de la esquina
;;      del banco. "Girar" si en tu planta la fachada es el lado
;;      paralelo al eje Y. Funciona con la zona en cualquier cuadrante
;;      (espejada o no) y con el SCP girado.
;;   6. Designar un punto libre del dibujo para los alzados y la
;;      seccion (quedan en fila hacia la derecha), o Intro para no
;;      dibujarlos.
;;   Al terminar se resume en la linea de comandos lo dibujado: medida
;;   de cada pieza y ancho real de los dos pasos libres.
;;
;; El comando no sabe donde estan las ventanas ni hasta donde llega el
;; tabique: la libreria ocupa el lado de la fachada menos 8 cm en el
;; extremo del pasillo y 20 cm en el del sofa (para no pisar el marco de
;; las ventanas que haya a cada lado), y el banco sobresale 5 cm mas
;; alla de la mesa. Si en tu planta eso tapa una ventana o saca el
;; banco del tabique, ajusta los parametros de abajo.
;; ==========================================================

;; --- Parametros (TODAS las medidas en CENTIMETROS reales; el comando
;; las pasa a las unidades del dibujo) ---
;;
;; Los bloques se reutilizan por nombre, y el nombre solo lleva las
;; medidas principales de cada pieza: si cambias estos parametros, borra
;; antes lo dibujado por una ejecucion anterior y limpia los bloques
;; LJ_* con PURGE (o usa un dibujo donde no se haya ejecutado aun).

;; Libreria contra la fachada.
(setq *lj-lib-fondo* 40.0)         ; fondo del armario bajo (juegos)
(setq *lj-lib-fondo-sup* 30.0)     ; fondo de los estantes altos (libros)
(setq *lj-lib-alto* 240.0)         ; altura total
(setq *lj-lib-alt-base* 80.0)      ; altura del armario bajo (con su zocalo)
(setq *lj-lib-encimera* 3.0)       ; grueso de la encimera del armario bajo
(setq *lj-lib-huecos* 4)           ; huecos entre baldas en los estantes
(setq *lj-lib-margen-ini* 8.0)     ; holgura en el extremo del lado del banco
(setq *lj-lib-margen-fin* 20.0)    ; holgura en el extremo del lado del sofa
(setq *lj-lib-modulo-max* 80.0)    ; ancho maximo de modulo
(setq *lj-lib-tablero* 1.9)        ; grueso de costados, divisiones y baldas
(setq *lj-alt-zocalo* 8.0)         ; zocalo (retranqueado) de la libreria

;; Paso libre minimo delante de la libreria y junto al sofa.
(setq *lj-paso* 90.0)

;; Banco corrido en L contra el tabique.
(setq *lj-banco-fondo* 50.0)       ; fondo total (asiento + cojin de respaldo)
(setq *lj-banco-respaldo* 10.0)    ; grueso del cojin de respaldo
(setq *lj-banco-cojin-max* 70.0)   ; largo maximo de cada cojin de asiento
(setq *lj-banco-sobrante* 5.0)     ; lo que el banco pasa del borde de la mesa
(setq *lj-banco-alt* 40.0)         ; altura del cajon del banco (sin cojin)
(setq *lj-banco-cojin* 8.0)        ; grueso del cojin de asiento
(setq *lj-banco-alt-respaldo* 90.0) ; altura de los cojines de respaldo

;; Mesa de juegos: medidas estandar (ancho x largo) por orden de
;; preferencia. Se usa la primera que quepa sin invadir los pasos; el
;; largo va a lo largo del tramo del banco paralelo al eje Y local.
(setq *lj-mesas* '((90.0 140.0) (90.0 120.0) (80.0 120.0) (80.0 100.0) (70.0 90.0) (70.0 80.0)))
(setq *lj-mesa-solape* 10.0)       ; lo que la mesa vuela sobre el asiento (>= 0)
(setq *lj-mesa-radio* 5.0)         ; radio de las esquinas redondeadas
(setq *lj-mesa-holgura* 10.0)      ; separacion minima entre la mesa y el paso
(setq *lj-mesa-alt* 75.0)          ; altura de la mesa
(setq *lj-mesa-grueso* 3.0)        ; grueso del tablero

;; Sillas en el lado libre de la mesa.
(setq *lj-silla-ancho* 45.0)
(setq *lj-silla-asiento* 40.0)     ; fondo del asiento
(setq *lj-silla-respaldo* 7.0)     ; fondo del respaldo curvo
(setq *lj-silla-separacion* 2.0)   ; hueco entre el borde de la mesa y el asiento
(setq *lj-silla-uso* 75.0)         ; espacio, desde el borde de la mesa, para
                                   ; retirar la silla y sentarse
(setq *lj-silla-hueco* 10.0)       ; separacion minima entre sillas
(setq *lj-silla-alt* 46.0)         ; altura del asiento

;; Iluminacion.
(setq *lj-lampara-diam* 45.0)      ; pantalla de la lampara colgante
(setq *lj-lampara-alt* 70.0)       ; del tablero al borde de la pantalla
(setq *lj-lampara-pantalla* 22.0)  ; alto de la pantalla
(setq *lj-aplique-dist* 25.0)      ; del aplique al extremo del banco
(setq *lj-aplique-alt* 125.0)      ; altura del aplique
(setq *lj-techo* 250.0)            ; altura libre (para el cable de la lampara)

;; Rotulos y cotas.
(setq *lj-texto-alto* 8.0)
(setq *lj-cota-texto* 6.0)

;; Tamano minimo de la zona (cada lado): por debajo no cabe el rincon de
;; juegos con un paso minimamente util al lado.
(setq *lj-zona-min* 200.0)

;; Capas: (nombre color-ACI).
(setq *lj-capa-muebles* '("LJ-MOBILIARIO" 3))
(setq *lj-capa-luz* '("LJ-ILUMINACION" 6))
(setq *lj-capa-alzados* '("LJ-ALZADOS" 3))
(setq *lj-capa-cotas* '("LJ-COTAS" 1))
(setq *lj-capa-textos* '("LJ-TEXTOS" 7))

;; --- Utilidades ---

;; Valor de "key" en una lista de asociacion con claves de texto.
(defun lj-get (lst key)
  (cdr (assoc key lst))
)

;; Entero mas pequeno >= x (AutoLISP no trae CEILING).
(defun lj-ceil (x / n)
  (setq n (fix x))
  (if (> x n) (1+ n) n)
)

;; Normaliza un angulo en radianes al rango [0, 2pi).
(defun lj-norm-2pi (a)
  (while (< a 0.0) (setq a (+ a (* 2.0 pi))))
  (while (>= a (* 2.0 pi)) (setq a (- a (* 2.0 pi))))
  a
)

;; Angulo de texto "legible": si el texto quedaria boca abajo (leyendo
;; de derecha a izquierda o de arriba abajo), se gira 180 grados.
(defun lj-readable (a)
  (setq a (lj-norm-2pi a))
  (if (and (> a (+ (/ pi 2.0) 1e-6)) (<= a (+ (* 1.5 pi) 1e-6)))
    (lj-norm-2pi (- a pi))
    a
  )
)

;; Texto con "cm" pasados a metros, siempre con dos decimales y coma
;; decimal ("3,20"): rtos quita los ceros finales (y el inicial) si
;; DIMZIN lo pide, asi que se completan a mano.
(defun lj-m (cm / s)
  (setq s (rtos (/ cm 100.0) 2 2))
  (if (not (vl-string-search "." s)) (setq s (strcat s ".")))
  (if (= (substr s 1 1) ".") (setq s (strcat "0" s)))
  (while (< (- (strlen s) (vl-string-search "." s)) 3) (setq s (strcat s "0")))
  (vl-string-subst "," "." s)
)

;; Texto con "x" centimetros redondeados, sin decimales.
(defun lj-cm (cm)
  (rtos cm 2 0)
)

;; Medida en cm como fragmento de nombre de bloque: un decimal como
;; mucho (resolucion de 1 mm), sin ceros sobrantes -tanto si DIMZIN los
;; quita como si no, para que el nombre no cambie con DIMZIN- y "_" en
;; vez del punto decimal.
(defun lj-tag (cm / s)
  (setq s (rtos cm 2 1))
  (if (= (substr s 1 1) ".") (setq s (strcat "0" s)))
  (if (vl-string-search "." s)
    (progn
      (while (= (substr s (strlen s)) "0") (setq s (substr s 1 (1- (strlen s)))))
      (if (= (substr s (strlen s)) ".") (setq s (substr s 1 (1- (strlen s)))))
    )
  )
  (vl-string-subst "_" "." s)
)

;; Nombre de bloque: el nombre base (con las medidas en cm) y, si el
;; dibujo no esta en cm, la unidad -la geometria del bloque va en
;; unidades de dibujo, asi que la misma pieza en mm o en m es otro
;; bloque, aunque se haya ejecutado el comando con unidades distintas
;; en el mismo dibujo-.
(defun lj-blk-name (base f)
  (strcat base (cond ((= f 10.0) "_MM") ((= f 0.01) "_M") (T "")))
)

;; Crea la capa (nombre color) si no existe.
(defun lj-ensure-layer (capa)
  (if (not (tblsearch "LAYER" (car capa)))
    (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord") '(100 . "AcDbLayerTableRecord")
                   (cons 2 (car capa)) '(70 . 0) (cons 62 (cadr capa)) '(6 . "Continuous")))
  )
  (tblsearch "LAYER" (car capa))
)

;; --- Utilidades de geometria ---

;; Generador pseudoaleatorio (congruencial, periodo 65536) para variar
;; libros y objetos: la misma semilla da siempre el mismo dibujo, que
;; hace falta porque un bloque se reutiliza por su nombre.
(defun lj-rnd-init (s)
  (setq *lj-rnd* s)
)

;; Siguiente numero, real en [0, 1).
(defun lj-rnd ( )
  (setq *lj-rnd* (rem (+ (* *lj-rnd* 1101) 12345) 65536))
  (/ *lj-rnd* 65536.0)
)

;; Real al azar entre a y b.
(defun lj-rnd-in (a b)
  (+ a (* (- b a) (lj-rnd)))
)

;; Punto a una fraccion u del segmento a-b.
(defun lj-lerp (a b u)
  (list (+ (car a) (* u (- (car b) (car a))))
        (+ (cadr a) (* u (- (cadr b) (cadr a)))))
)

;; Longitud de una linea quebrada (lista de puntos).
(defun lj-len (pts / s a b)
  (setq s 0.0 a (car pts))
  (foreach b (cdr pts)
    (setq s (+ s (distance a b)) a b)
  )
  s
)

;; Anade propiedades de estilo a una lista de entidades DXF, detras de
;; la capa: "DET" = linea de detalle (gris, 0,13 mm); "CORTE" = linea de
;; elemento cortado en una seccion (0,40 mm). Otro valor: sin cambios.
(defun lj-style (estilo ents / extra out e g x y)
  (setq extra (cond ((= estilo "DET") (list (cons 62 8) (cons 370 13)))
                    ((= estilo "CORTE") (list (cons 370 40)))))
  (setq out '())
  (foreach e ents
    (setq g '())
    (foreach x e
      (setq g (cons x g))
      (if (= (car x) 8)
        (foreach y extra (setq g (cons y g)))
      )
    )
    (setq out (cons (reverse g) out))
  )
  (reverse out)
)

;; Vertices (x y bulge), en sentido antihorario, de un rectangulo con
;; las esquinas redondeadas: r1 abajo-izquierda, r2 abajo-derecha, r3
;; arriba-derecha y r4 arriba-izquierda (0 = esquina viva).
(defun lj-rr4 (x0 y0 x1 y1 r1 r2 r3 r4 / b)
  (setq b (/ (sin (/ pi 8.0)) (cos (/ pi 8.0))))   ; bulge de un cuarto de circulo
  (append
    (if (> r1 0.0) (list (list x0 (+ y0 r1) b) (list (+ x0 r1) y0 0.0)) (list (list x0 y0 0.0)))
    (if (> r2 0.0) (list (list (- x1 r2) y0 b) (list x1 (+ y0 r2) 0.0)) (list (list x1 y0 0.0)))
    (if (> r3 0.0) (list (list x1 (- y1 r3) b) (list (- x1 r3) y1 0.0)) (list (list x1 y1 0.0)))
    (if (> r4 0.0) (list (list (+ x0 r4) y1 b) (list x0 (- y1 r4) 0.0)) (list (list x0 y1 0.0)))
  )
)

;; Igual, con el mismo radio en las cuatro esquinas.
(defun lj-rr (x0 y0 x1 y1 r)
  (lj-rr4 x0 y0 x1 y1 r r r r)
)

;; Gira "a" radianes y traslada a (cx cy) una lista de puntos (x y
;; [bulge]); los bulges no cambian con un giro.
(defun lj-xf (pts cx cy a / c s out p)
  (setq c (cos a) s (sin a) out '())
  (foreach p pts
    (setq out (cons (append (list (+ cx (- (* c (car p)) (* s (cadr p))))
                                  (+ cy (* s (car p)) (* c (cadr p))))
                            (cddr p))
                    out))
  )
  (reverse out)
)

;; Pasa una polilinea (x y [bulge]) a puntos (x y), aproximando cada
;; arco por tramos de 15 grados como mucho. Si es cerrada, el ultimo
;; punto devuelto repite el primero.
(defun lj-tess (pts closed / out n i p q bu th ch d mx my nx ny c r a0 m k)
  (setq out '() n (length pts) i 0)
  (while (< i (if closed n (1- n)))
    (setq p (nth i pts) q (nth (rem (1+ i) n) pts))
    (setq out (cons (list (car p) (cadr p)) out))
    (setq bu (if (caddr p) (caddr p) 0.0))
    (if (> (abs bu) 1e-9)
      (progn
        (setq th (* 4.0 (atan bu)))
        (setq ch (distance (list (car p) (cadr p)) (list (car q) (cadr q))))
        ;; centro: desde el punto medio de la cuerda, hacia su izquierda
        (setq d (/ (* (/ ch 2.0) (- 1.0 (* bu bu))) (* 2.0 bu)))
        (setq mx (/ (+ (car p) (car q)) 2.0) my (/ (+ (cadr p) (cadr q)) 2.0))
        (setq nx (/ (- (cadr p) (cadr q)) ch) ny (/ (- (car q) (car p)) ch))
        (setq c (list (+ mx (* nx d)) (+ my (* ny d))))
        (setq r (distance c (list (car p) (cadr p))))
        (setq a0 (angle c (list (car p) (cadr p))))
        (setq m (max 2 (lj-ceil (/ (abs th) (/ pi 12.0)))))
        (setq k 1)
        (while (< k m)
          (setq out (cons (polar c (+ a0 (* th (/ (float k) m))) r) out))
          (setq k (1+ k))
        )
      )
    )
    (setq i (1+ i))
  )
  (setq p (if closed (car pts) (last pts)))
  (reverse (cons (list (car p) (cadr p)) out))
)

;; Poligono (sin repetir el primer punto) de una forma cerrada con bulges.
(defun lj-poly (pts)
  (reverse (cdr (reverse (lj-tess pts T))))
)

;; Caja (xmin ymin xmax ymax) de una lista de puntos, con un margen m.
(defun lj-bbox (pts m / x0 y0 x1 y1 p)
  (setq x0 (car (car pts)) x1 x0 y0 (cadr (car pts)) y1 y0)
  (foreach p pts
    (setq x0 (min x0 (car p)) x1 (max x1 (car p))
          y0 (min y0 (cadr p)) y1 (max y1 (cadr p)))
  )
  (list (- x0 m) (- y0 m) (+ x1 m) (+ y1 m))
)

;; True si dos cajas se solapan.
(defun lj-bbox-cruza (a b)
  (and (< (car a) (caddr b)) (< (car b) (caddr a))
       (< (cadr a) (cadddr b)) (< (cadr b) (cadddr a)))
)

;; Intervalo (t0 t1) del segmento a-b que queda DENTRO del poligono
;; convexo "poly" (puntos en sentido antihorario), o nil si no entra
;; (recorte de Cyrus-Beck).
(defun lj-cb (a b poly / t0 t1 ok n i v w nx ny num den tt dx dy)
  (setq t0 0.0 t1 1.0 ok T n (length poly) i 0
        dx (- (car b) (car a)) dy (- (cadr b) (cadr a)))
  (while (and ok (< i n))
    (setq v (nth i poly) w (nth (rem (1+ i) n) poly))
    ;; normal interior: a la izquierda del lado v->w
    (setq nx (- (cadr v) (cadr w)) ny (- (car w) (car v)))
    (setq num (+ (* nx (- (car v) (car a))) (* ny (- (cadr v) (cadr a)))))
    (setq den (+ (* nx dx) (* ny dy)))
    (cond
      ((< (abs den) 1e-12)
        (if (> num 0.0) (setq ok nil)))
      ((> den 0.0)
        (setq tt (/ num den))
        (if (> tt t0) (setq t0 tt)))
      (T
        (setq tt (/ num den))
        (if (< tt t1) (setq t1 tt)))
    )
    (setq i (1+ i))
  )
  (if (and ok (< t0 t1)) (list t0 t1) nil)
)

;; Tramos de la linea quebrada "pts" que quedan FUERA del poligono
;; convexo "poly": lista de lineas quebradas.
(defun lj-hide1 (pts poly / runs cur a b iv)
  (setq runs '() cur nil a (car pts))
  (foreach b (cdr pts)
    (setq iv (lj-cb a b poly))
    (if (not iv)
      (setq cur (if cur (cons b cur) (list b a)))
      (progn
        (if (> (car iv) 1e-9)
          (setq cur (if cur (cons (lj-lerp a b (car iv)) cur) (list (lj-lerp a b (car iv)) a)))
        )
        (if cur (setq runs (cons (reverse cur) runs) cur nil))
        (if (< (cadr iv) (- 1.0 1e-9))
          (setq cur (list b (lj-lerp a b (cadr iv))))
        )
      )
    )
    (setq a b)
  )
  (if cur (setq runs (cons (reverse cur) runs)))
  (reverse runs)
)

;; Tramos de "pts" fuera de TODOS los poligonos de "tapas".
(defun lj-hide (pts tapas / runs tapa nuevos run)
  (setq runs (list pts))
  (foreach tapa tapas
    (setq nuevos '())
    (foreach run runs
      (setq nuevos (append nuevos (lj-hide1 run tapa)))
    )
    (setq runs nuevos)
  )
  runs
)
;; --- Unidades ---

;; Unidades de dibujo por centimetro.
(defun lj-unit-factor (unidad)
  (cond ((= unidad "Milimetros") 10.0)
        ((= unidad "Metros") 0.01)
        (T 1.0))
)

;; True si una zona de "size" unidades de dibujo tiene un tamano
;; razonable para un salon (entre 1,5 y 15 m) en esa unidad.
(defun lj-plausible (size unidad / cm)
  (setq cm (/ size (lj-unit-factor unidad)))
  (and (>= cm 150.0) (<= cm 1500.0))
)

;; Unidad con la que la zona (lado mayor "size") mide mas cerca de 3,5 m.
(defun lj-guess-unit (size / best bestd d u)
  (setq best "Centimetros" bestd nil)
  (foreach u '("Milimetros" "Centimetros" "Metros")
    (setq d (abs (log (/ (/ size (lj-unit-factor u)) 350.0))))
    (if (or (not bestd) (< d bestd)) (setq best u bestd d))
  )
  best
)

;; Pregunta las unidades del dibujo, proponiendo las de INSUNITS si dan
;; una zona de tamano razonable, y si no las que mejor encajan con el
;; tamano designado. Devuelve "Milimetros", "Centimetros" o "Metros".
;; (Las palabras clave llevan dos mayusculas, MIlimetros / MEtros, para
;; que "MI" y "ME" las distingan: con una sola "M" serian ambiguas.)
(defun lj-ask-units (sizeX sizeY / ins def kw)
  (setq ins (getvar "INSUNITS"))
  (setq def (cond ((= ins 4) "Milimetros") ((= ins 5) "Centimetros") ((= ins 6) "Metros")))
  (if (or (not def) (not (lj-plausible (max sizeX sizeY) def)))
    (setq def (lj-guess-unit (max sizeX sizeY)))
  )
  (initget "MIlimetros Centimetros MEtros")
  (setq kw (getkword (strcat "\n[LIBJUEGOS] La zona mide "
                             (lj-m (/ sizeX (lj-unit-factor def))) " x "
                             (lj-m (/ sizeY (lj-unit-factor def))) " m si el dibujo esta en "
                             (strcase def T) ". Unidades del dibujo [MIlimetros/Centimetros/MEtros] <"
                             def ">: ")))
  (cond ((not kw) def)
        ((= (strcase kw) "MILIMETROS") "Milimetros")
        ((= (strcase kw) "METROS") "Metros")
        (T "Centimetros"))
)

;; --- Marco local de la zona ---
;;
;; Todo el diseno se calcula en un sistema local, en centimetros:
;; origen en la esquina interior del tabique en L, eje X local hacia el
;; sofa y eje Y local hacia la fachada. "fr" es la lista
;; (origenWCS ejeX ejeY factor mano ancho fondo): ejes como vectores
;; unitarios 2D en WCS, factor = unidades de dibujo por cm, mano = 1
;; si el marco local no esta espejado respecto al WCS y -1 si lo esta,
;; ancho/fondo = medidas de la zona en cm a lo largo de X/Y locales.

(defun lj-v2 (v s)
  (list (* s (car v)) (* s (cadr v)))
)

;; p1, p2: esquinas designadas (en el SCP actual).
(defun lj-frame (p1 p2 girar f / o xw yw dx dy sx sy ex ey hand)
  (setq o (trans p1 1 0))
  (setq xw (trans '(1.0 0.0 0.0) 1 0 T))
  (setq yw (trans '(0.0 1.0 0.0) 1 0 T))
  (setq dx (- (car p2) (car p1)))
  (setq dy (- (cadr p2) (cadr p1)))
  (setq sx (if (minusp dx) -1.0 1.0))
  (setq sy (if (minusp dy) -1.0 1.0))
  (if girar
    (setq ex (lj-v2 yw sy) ey (lj-v2 xw sx))
    (setq ex (lj-v2 xw sx) ey (lj-v2 yw sy))
  )
  (setq hand (if (minusp (- (* (car ex) (cadr ey)) (* (cadr ex) (car ey)))) -1.0 1.0))
  (list (list (car o) (cadr o)) ex ey f hand
        (/ (abs (if girar dy dx)) f)
        (/ (abs (if girar dx dy)) f))
)

;; Punto WCS (x y 0) de unas coordenadas locales (en cm).
(defun lj-pt (fr x y / o ex ey f)
  (setq o (nth 0 fr) ex (nth 1 fr) ey (nth 2 fr) f (nth 3 fr))
  (list (+ (car o) (* f (+ (* x (car ex)) (* y (car ey)))))
        (+ (cadr o) (* f (+ (* x (cadr ex)) (* y (cadr ey)))))
        0.0)
)

;; Angulo WCS de una direccion local (a, en radianes).
(defun lj-ang (fr a / ex ey)
  (setq ex (nth 1 fr) ey (nth 2 fr))
  (angle '(0.0 0.0)
         (list (+ (* (cos a) (car ex)) (* (sin a) (car ey)))
               (+ (* (cos a) (cadr ex)) (* (sin a) (cadr ey)))))
)

;; --- Distribucion (todo en cm, en el marco local) ---
;;
;; Devuelve una lista de asociacion con la posicion y medida de cada
;; pieza, el ancho de los pasos que quedan y los avisos, si los hay.
(defun lj-layout (anchoZ fondoZ / avisos xa largoLib nMod yTope xTope x0 y0 cand mesa mW mL
                                  x1 y1 Lv Lh ys0 span nS i sillas cabecera pasoSup pasoLat)
  (setq avisos '())

  ;; Libreria: todo el lado de la fachada menos las holguras.
  (setq xa *lj-lib-margen-ini*)
  (setq largoLib (- anchoZ *lj-lib-margen-ini* *lj-lib-margen-fin*))
  (if (< largoLib 60.0)
    (setq largoLib nil
          avisos (cons "La zona es demasiado estrecha para la libreria: no se dibuja." avisos))
    (setq nMod (lj-ceil (/ largoLib *lj-lib-modulo-max*)))
  )

  ;; Hasta donde puede llegar el rincon de juegos sin invadir los pasos:
  ;; por arriba, el paso delante de la libreria; por el lado del sofa,
  ;; el paso junto a su respaldo.
  (setq yTope (- fondoZ (if largoLib *lj-lib-fondo* 0.0) *lj-paso*))
  (setq xTope (- anchoZ *lj-paso*))

  ;; Mesa: la mayor medida estandar que quepa, con la silla retirada
  ;; (espacio de uso) sin entrar en el paso lateral.
  (setq x0 (- *lj-banco-fondo* *lj-mesa-solape*))
  (setq y0 x0)
  (setq mesa nil)
  (foreach cand *lj-mesas*
    (if (and (not mesa)
             (<= (+ x0 (car cand) *lj-silla-uso*) xTope)
             (<= (+ y0 (cadr cand) (max *lj-banco-sobrante* *lj-mesa-holgura*)) yTope))
      (setq mesa cand)
    )
  )
  (if (not mesa)
    (setq mesa (last *lj-mesas*)
          avisos (cons "No cabe ninguna mesa sin invadir los pasos de 90 cm: se pone la mas pequena y algun paso queda mas estrecho." avisos))
  )
  (setq mW (car mesa) mL (cadr mesa))
  (setq x1 (+ x0 mW) y1 (+ y0 mL))

  ;; Banco en L: un poco mas largo que la mesa por cada lado.
  (setq Lv (+ y1 *lj-banco-sobrante*))
  (setq Lh (+ x1 *lj-banco-sobrante*))

  ;; Sillas en el lado libre (el del sofa): tantas como quepan entre el
  ;; frente del tramo inferior del banco y el borde de la mesa.
  (setq ys0 (+ *lj-banco-fondo* (/ *lj-silla-hueco* 2.0)))
  (setq span (- y1 ys0))
  (setq nS (fix (/ (+ span *lj-silla-hueco*) (+ *lj-silla-ancho* *lj-silla-hueco*))))
  (setq sillas '())
  (setq i 0)
  (while (< i nS)
    (setq sillas (append sillas (list (+ ys0 (/ (* span (+ (* 2 i) 1)) (* 2.0 nS))))))
    (setq i (1+ i))
  )

  ;; Silla en la cabecera (lado de la libreria) solo si al retirarla no
  ;; entra en el paso de delante de la libreria.
  (setq cabecera (<= (+ y1 *lj-silla-uso*) yTope))

  ;; Pasos que quedan realmente libres.
  (setq pasoSup (- fondoZ (if largoLib *lj-lib-fondo* 0.0)
                   (max Lv (if cabecera (+ y1 *lj-silla-uso*) 0.0))))
  (setq pasoLat (- anchoZ (max Lh (if sillas (+ x1 *lj-silla-uso*) 0.0))))
  (if (< pasoSup (- *lj-paso* 0.5))
    (setq avisos (cons (strcat "El paso delante de la libreria se queda en " (lj-cm pasoSup) " cm.") avisos))
  )
  (if (< pasoLat (- *lj-paso* 0.5))
    (setq avisos (cons (strcat "El paso junto al sofa se queda en " (lj-cm pasoLat) " cm.") avisos))
  )

  (list (cons "XA" xa) (cons "LIB" largoLib) (cons "NMOD" nMod)
        (cons "X0" x0) (cons "Y0" y0) (cons "MW" mW) (cons "ML" mL) (cons "X1" x1) (cons "Y1" y1)
        (cons "LV" Lv) (cons "LH" Lh)
        (cons "SILLAS" sillas) (cons "CABECERA" cabecera)
        (cons "PASOSUP" pasoSup) (cons "PASOLAT" pasoLat)
        (cons "AVISOS" (reverse avisos)))
)

;; --- Entidades DXF para los bloques (en cm locales x f) ---

;; LWPOLYLINE en la capa 0 (dentro de un bloque toma la capa de la
;; insercion). pts: lista de (x y) o (x y bulge).
(defun lj-e-pline (f pts closed / data p)
  (setq data (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") '(8 . "0") '(100 . "AcDbPolyline")
                   (cons 90 (length pts)) (cons 70 (if closed 1 0))))
  (foreach p pts
    (setq data (append data (list (list 10 (* f (car p)) (* f (cadr p))))))
    (if (caddr p) (setq data (append data (list (cons 42 (caddr p))))))
  )
  data
)

(defun lj-e-rect (f x0 y0 x1 y1)
  (lj-e-pline f (list (list x0 y0) (list x1 y0) (list x1 y1) (list x0 y1)) T)
)

(defun lj-e-line (f x0 y0 x1 y1)
  (list '(0 . "LINE") '(8 . "0")
        (list 10 (* f x0) (* f y0) 0.0) (list 11 (* f x1) (* f y1) 0.0))
)

(defun lj-e-circle (f x y r)
  (list '(0 . "CIRCLE") '(8 . "0") (list 10 (* f x) (* f y) 0.0) (cons 40 (* f r)))
)

;; Arco de a0 a a1 (radianes, en sentido antihorario).
(defun lj-e-arc (f x y r a0 a1)
  (list '(0 . "ARC") '(8 . "0") (list 10 (* f x) (* f y) 0.0) (cons 40 (* f r))
        (cons 50 a0) (cons 51 a1))
)

;; Hoja (de planta): forma de lente entre la base b y la punta p.
(defun lj-e-hoja (f b p bu)
  (lj-e-pline f (list (list (car b) (cadr b) bu) (list (car p) (cadr p) bu)) T)
)

;; Entidades de una forma (vertices con bulge; cerrada o abierta) sin las
;; partes que queden debajo de otras piezas ("tapas": poligonos
;; convexos en sentido antihorario). Si ninguna tapa la toca, se crea
;; tal cual (con sus arcos); si no, aproximada por tramos y recortada.
(defun lj-e-shape (f pts closed tapas / caja toca tapa out run)
  (setq caja (lj-bbox pts 3.0) toca nil)
  (foreach tapa tapas
    (if (lj-bbox-cruza caja (lj-bbox tapa 0.0)) (setq toca T))
  )
  (if (not toca)
    (list (lj-e-pline f pts closed))
    (progn
      (setq out '())
      (foreach run (lj-hide (lj-tess pts closed) tapas)
        (if (> (lj-len run) 0.05) (setq out (cons (lj-e-pline f run nil) out)))
      )
      (reverse out)
    )
  )
)

;; Linea discontinua dibujada a mano (trazos "tr" y huecos "hu") a lo
;; largo de la linea quebrada pts (x y), para lo que queda oculto, sin
;; depender de un tipo de linea cargado ni de LTSCALE. Devuelve LINEs.
(defun lj-e-dashed (f pts tr hu / out per s0 a b len k d0 d1 pa pb)
  (setq out '() per (+ tr hu) s0 0.0 a (car pts))
  (foreach b (cdr pts)
    (setq len (distance a b))
    (if (> len 1e-9)
      (progn
        (setq k (fix (/ s0 per)))
        (while (< (* k per) (+ s0 len))
          (setq d0 (max s0 (* k per)) d1 (min (+ s0 len) (+ (* k per) tr)))
          (if (> d1 (+ d0 1e-6))
            (progn
              (setq pa (lj-lerp a b (/ (- d0 s0) len)) pb (lj-lerp a b (/ (- d1 s0) len)))
              (setq out (cons (lj-e-line f (car pa) (cadr pa) (car pb) (cadr pb)) out))
            )
          )
          (setq k (1+ k))
        )
      )
    )
    (setq s0 (+ s0 len) a b)
  )
  (reverse out)
)

;; Rayado a 45 grados (lineas separadas "sep") dentro de un rectangulo,
;; para los elementos de obra cortados.
(defun lj-rayado (f x0 y0 x1 y1 sep / rect ents c cmax a b iv pa pb)
  (setq rect (list (list x0 y0) (list x1 y0) (list x1 y1) (list x0 y1)) ents '())
  ;; rectas x = y + c
  (setq c (+ (- x0 y1) (/ sep 2.0)) cmax (- x1 y0))
  (while (< c cmax)
    (setq a (list (+ c y0) y0) b (list (+ c y1) y1))
    (setq iv (lj-cb a b rect))
    (if iv
      (progn
        (setq pa (lj-lerp a b (car iv)) pb (lj-lerp a b (cadr iv)))
        (setq ents (cons (lj-e-line f (car pa) (cadr pa) (car pb) (cadr pb)) ents))
      )
    )
    (setq c (+ c sep))
  )
  (reverse ents)
)

;; --- Bloques de planta ---

;; Lo que se ve desde arriba en un estante (de x = xa a x = xb, con el
;; frente en y = yf y el fondo hacia +Y): grupos de libros de pie con
;; el lomo al frente, algun hueco, pilas de libros tumbados y alguna
;; planta.
(defun lj-libros-planta (f xa xb yf seed / ents x w d r)
  (lj-rnd-init seed)
  (setq ents '() x (+ xa 1.0))
  (while (< x (- xb 3.0))
    (setq r (lj-rnd))
    (cond
      ((and (< r 0.06) (> x (+ xa 10.0)) (< (+ x 16.0) xb))
        (setq ents (append ents (lj-planta-planta f (+ x 8.0) (+ yf 12.0) 5.5)))
        (setq x (+ x 16.0)))
      ((and (< r 0.14) (< (+ x 25.0) xb))
        (setq w (lj-rnd-in 17.0 22.0) d (lj-rnd-in 21.0 24.0))
        (setq ents (append ents (list (lj-e-rect f x yf (+ x w) (+ yf d))
                                      (lj-e-rect f (+ x 1.2) (+ yf 1.2) (- (+ x w) 1.2) (- (+ yf d) 1.2)))))
        (setq x (+ x w 2.0)))
      ((< r 0.21)
        (setq x (+ x (lj-rnd-in 3.0 8.0))))
      (T
        (setq w (lj-rnd-in 1.6 4.6) d (lj-rnd-in 16.0 22.0))
        (if (< (+ x w) (- xb 1.0))
          (setq ents (append ents (list (lj-e-rect f x yf (+ x w) (+ yf d)))))
        )
        (setq x (+ x w 0.25)))
    )
  )
  ents
)

;; Planta en maceta vista desde arriba: maceta (con su borde) y hojas.
(defun lj-planta-planta (f cx cy r / c ents k a)
  (setq c (list cx cy))
  (setq ents (list (lj-e-circle f cx cy r) (lj-e-circle f cx cy (* 0.82 r))))
  (setq k 0)
  (while (< k 7)
    (setq a (+ 0.4 (* k (/ (* 2.0 pi) 7.0))))
    (setq ents (append ents (list (lj-e-hoja f (polar c a (* 0.2 r)) (polar c (+ a 0.15) (* 1.45 r)) 0.38))))
    (setq k (1+ k))
  )
  ents
)

;; Libreria de "largo" cm con nMod modulos, en planta. Origen en su
;; extremo inicial, sobre la cara de la fachada; el mueble queda hacia
;; -Y local. Se ve el armario bajo (su encimera asoma por delante) y,
;; cortados, los estantes con sus costados y divisiones; en detalle, el
;; canto de la encimera, la trasera y lo que hay en cada estante.
(defun lj-ents-libreria (f largo nMod / fb fs tb m i x xa xb ents)
  (setq fb *lj-lib-fondo* fs *lj-lib-fondo-sup* tb *lj-lib-tablero*)
  (setq m (/ largo nMod))
  (setq ents (list (lj-e-rect f 0.0 (- fb) largo 0.0)
                   (lj-e-line f 0.0 (- fs) largo (- fs))))
  (setq i 0)
  (while (<= i nMod)
    (setq x (* i m))
    (setq ents (append ents (list
      (cond ((= i 0) (lj-e-rect f 0.0 (- fs) tb 0.0))
            ((= i nMod) (lj-e-rect f (- largo tb) (- fs) largo 0.0))
            (T (lj-e-rect f (- x (/ tb 2.0)) (- fs) (+ x (/ tb 2.0)) 0.0))))))
    (setq i (1+ i))
  )
  (setq ents (append ents (lj-style "DET" (list (lj-e-line f 0.0 (+ (- fb) 1.5) largo (+ (- fb) 1.5))))))
  (setq i 0)
  (while (< i nMod)
    (setq xa (+ (* i m) (if (= i 0) tb (/ tb 2.0))))
    (setq xb (- (* (1+ i) m) (if (= i (1- nMod)) tb (/ tb 2.0))))
    (setq ents (append ents (lj-style "DET" (cons (lj-e-line f xa -0.8 xb -0.8)
                                                   (lj-libros-planta f xa xb (+ (- fs) 0.8) (+ 101 (* 37 i)))))))
    (setq i (1+ i))
  )
  ents
)

;; Cojin suelto (mullido) de largo "lp" (eje u) y grueso "gp" (eje v),
;; centrado en el origen: esquinas redondeadas y los lados largos algo
;; abombados. Vertices (x y bulge) en sentido antihorario.
(defun lj-cojin-pts (lp gp / r b90 bl hx hy)
  (setq r 3.5 hx (/ lp 2.0) hy (/ gp 2.0))
  (setq b90 (/ (sin (/ pi 8.0)) (cos (/ pi 8.0))))
  (setq bl (/ 3.0 (- lp (* 2.0 r))))           ; flecha de 1,5 cm
  (list (list (+ (- hx) r) (- hy) bl) (list (- hx r) (- hy) b90)
        (list hx (+ (- hy) r) 0.0) (list hx (- hy r) b90)
        (list (- hx r) hy bl) (list (+ (- hx) r) hy b90)
        (list (- hx) (- hy r) 0.0) (list (- hx) (+ (- hy) r) b90))
)

;; Cojin suelto colocado (centro cx cy, girado a): contorno y detalle
;; -pellizcos de las esquinas y, en planta, la costura-.
(defun lj-ents-cojin (f lp gp cx cy a costura / hx hy det s ents)
  (setq hx (/ lp 2.0) hy (/ gp 2.0))
  (setq det (list (list (list (- hx 1.2) (- hy 1.2)) (list (- hx 3.8) (- hy 2.6)))
                  (list (list (- hx 1.2) (+ (- hy) 1.2)) (list (- hx 3.8) (+ (- hy) 2.6)))
                  (list (list (+ (- hx) 1.2) (- hy 1.2)) (list (+ (- hx) 3.8) (- hy 2.6)))
                  (list (list (+ (- hx) 1.2) (+ (- hy) 1.2)) (list (+ (- hx) 3.8) (+ (- hy) 2.6)))))
  (if costura
    (setq det (cons (list (list (+ (- hx) 5.0) 0.0) (list (- hx 5.0) 0.0)) det))
  )
  (setq ents (list (lj-e-pline f (lj-xf (lj-cojin-pts lp gp) cx cy a) T)))
  (foreach s det
    (setq ents (append ents (lj-style "DET" (list (lj-e-pline f (lj-xf s cx cy a) nil)))))
  )
  ents
)

;; Tablas y veta del tablero de la mesa (tres tablas a lo largo).
(defun lj-tablas-mesa (f x0 y0 x1 y1 / w ents k xc)
  (setq w (/ (- x1 x0) 3.0))
  (setq ents (list (lj-e-line f (+ x0 w) (+ y0 1.5) (+ x0 w) (- y1 1.5))
                   (lj-e-line f (+ x0 (* 2.0 w)) (+ y0 1.5) (+ x0 (* 2.0 w)) (- y1 1.5))))
  (lj-rnd-init 7)
  (setq k 0)
  (while (< k 3)
    (setq xc (+ x0 (* w (+ k 0.5))))
    (setq ents (append ents (list (lj-e-pline f (list (list (+ xc (lj-rnd-in -3.0 3.0)) (+ y0 9.0) 0.06)
                                                       (list (+ xc (lj-rnd-in -3.0 3.0)) (+ y0 (* 0.35 (- y1 y0))) -0.05)
                                                       (list (+ xc (lj-rnd-in -3.0 3.0)) (+ y0 (* 0.65 (- y1 y0))) 0.05)
                                                       (list (+ xc (lj-rnd-in -3.0 3.0)) (- y1 9.0) 0.0))
                                                 nil))))
    (setq k (1+ k))
  )
  ents
)

;; Rincon de juegos: banco corrido en L + mesa, como UNA sola pieza (la
;; mesa vuela sobre el asiento, asi que van juntos). Origen en la
;; esquina del tabique; tramo del banco de largo Lv a lo largo de Y
;; local y de largo Lh a lo largo de X local, ambos del fondo del banco;
;; mesa de (x0 y0) a (x1 y1). Todo lo que queda debajo de otra pieza
;; -del tablero, o de un cojin suelto- no se dibuja.
(defun lj-ents-rincon (f Lv Lh x0 y0 x1 y1 / B R g cr cx cy tapaMesa tp1 tp2 ents nv nh len k
                                             ya yb xa xb bw bl)
  (setq B *lj-banco-fondo* R *lj-banco-respaldo* g 1.0 cr 3.0)
  (setq cx (/ (+ x0 x1) 2.0) cy (/ (+ y0 y1) 2.0))
  ;; tapas: el tablero (un pelo metido, para no borrar sus bordes) y los
  ;; dos cojines sueltos: uno de lectura al final del tramo largo y otro
  ;; en la esquina, a 45 grados
  (setq tapaMesa (lj-poly (lj-rr (+ x0 0.05) (+ y0 0.05) (- x1 0.05) (- y1 0.05) (- *lj-mesa-radio* 0.05))))
  (setq tp1 (lj-poly (lj-xf (lj-cojin-pts 42.0 13.0) (+ R 7.0) (- Lv 32.0) (/ pi 2.0))))
  (setq tp2 (lj-poly (lj-xf (lj-cojin-pts 40.0 13.0) 26.0 26.0 (- (/ pi 4.0)))))
  ;; estructura del banco (el cajon)
  (setq ents (lj-e-shape f (list (list 0.0 0.0) (list Lh 0.0) (list Lh B) (list B B) (list B Lv) (list 0.0 Lv))
                         T (list tapaMesa)))
  ;; cojin de asiento de la esquina, con su vivo
  (setq ents (append ents
    (lj-e-shape f (lj-rr (+ R 0.5) (+ R 0.5) (- B 0.5) (- B 0.5) cr) T (list tapaMesa tp2))
    (lj-style "DET" (lj-e-shape f (lj-rr (+ R 1.7) (+ R 1.7) (- B 1.7) (- B 1.7) 1.8) T (list tapaMesa tp2)))
    ;; respaldos detras del cojin de la esquina (uno contra cada tabique)
    (lj-e-shape f (lj-rr 0.5 0.5 (- R 0.5) (- B 0.5) 2.0) T (list tp2))
    (lj-e-shape f (lj-rr (+ R 0.5) 0.5 (- B 0.5) (- R 0.5) 2.0) T (list tp2))))
  ;; tramo largo: cojines de asiento (con vivo) y de respaldo
  (setq nv (lj-ceil (/ (- Lv B) *lj-banco-cojin-max*)) len (/ (- Lv B) nv) k 0)
  (while (< k nv)
    (setq ya (+ B (* k len) (/ g 2.0)) yb (- (+ B (* (1+ k) len)) (/ g 2.0)))
    (setq ents (append ents
      (lj-e-shape f (lj-rr (+ R 0.5) ya (- B 0.5) yb cr) T (list tapaMesa tp1 tp2))
      (lj-style "DET" (lj-e-shape f (lj-rr (+ R 1.7) (+ ya 1.2) (- B 1.7) (- yb 1.2) 1.8) T (list tapaMesa tp1 tp2)))
      (lj-e-shape f (lj-rr 0.5 ya (- R 0.5) yb 2.0) T (list tp1 tp2))))
    (setq k (1+ k))
  )
  ;; tramo corto: cojines de asiento (con vivo) y de respaldo
  (setq nh (lj-ceil (/ (- Lh B) *lj-banco-cojin-max*)) len (/ (- Lh B) nh) k 0)
  (while (< k nh)
    (setq xa (+ B (* k len) (/ g 2.0)) xb (- (+ B (* (1+ k) len)) (/ g 2.0)))
    (setq ents (append ents
      (lj-e-shape f (lj-rr xa (+ R 0.5) xb (- B 0.5) cr) T (list tapaMesa))
      (lj-style "DET" (lj-e-shape f (lj-rr (+ xa 1.2) (+ R 1.7) (- xb 1.2) (- B 1.7) 1.8) T (list tapaMesa)))
      (lj-e-shape f (lj-rr xa 0.5 xb (- R 0.5) 2.0) T (list tp2))))
    (setq k (1+ k))
  )
  ;; cojines sueltos, encima de todo lo del banco
  (setq ents (append ents
    (lj-ents-cojin f 42.0 13.0 (+ R 7.0) (- Lv 32.0) (/ pi 2.0) T)
    (lj-ents-cojin f 40.0 13.0 26.0 26.0 (- (/ pi 4.0)) T)))
  ;; mesa: tablero, canto, tablas con veta y, oculto (a trazos), el pie
  ;; central con su base
  (setq bw (max 20.0 (- (- x1 x0) 35.0)) bl (max 20.0 (- (- y1 y0) 35.0)))
  (setq ents (append ents
    (list (lj-e-pline f (lj-rr x0 y0 x1 y1 *lj-mesa-radio*) T))
    (lj-style "DET" (cons (lj-e-pline f (lj-rr (+ x0 1.5) (+ y0 1.5) (- x1 1.5) (- y1 1.5) (- *lj-mesa-radio* 1.5)) T)
                          (lj-tablas-mesa f x0 y0 x1 y1)))
    (lj-style "DET" (lj-e-dashed f (lj-tess (lj-rr (- cx 7.0) (- cy 7.0) (+ cx 7.0) (+ cy 7.0) 0.0) T) 3.0 2.0))
    (lj-style "DET" (lj-e-dashed f (lj-tess (lj-rr (- cx (/ bw 2.0)) (- cy (/ bl 2.0))
                                                   (+ cx (/ bw 2.0)) (+ cy (/ bl 2.0)) 4.0) T) 4.0 2.5))))
  ents
)

;; Silla en planta. Origen en el centro del asiento, mirando hacia -X
;; local (hacia la mesa): asiento tapizado de esquinas redondeadas (mas
;; por delante) y respaldo curvo de madera.
(defun lj-ents-silla (f / hw ha bb)
  (setq hw (/ *lj-silla-ancho* 2.0) ha (/ *lj-silla-asiento* 2.0))
  (setq bb (/ 5.0 *lj-silla-ancho*))            ; flecha de 2,5 cm en el respaldo
  (append
    (list (lj-e-pline f (lj-rr4 (- ha) (- 1.5 hw) ha (- hw 1.5) 4.0 1.5 1.5 4.0) T)
          (lj-e-pline f (list (list ha (- hw) 0.0) (list (+ ha 4.0) (- hw) bb)
                              (list (+ ha 4.0) hw 0.0) (list ha hw (- bb))) T))
    (lj-style "DET" (list (lj-e-pline f (lj-rr4 (+ (- ha) 2.5) (- 4.0 hw) (- ha 2.5) (- hw 4.0) 2.5 1.0 1.0 2.5) T))))
)

;; Lampara colgante en planta: pantalla con su borde, gajos, floron del
;; techo y el aspa de punto de luz en el centro. Origen en su centro.
(defun lj-ents-lampara (f / r k a ents)
  (setq r (/ *lj-lampara-diam* 2.0))
  (setq ents (list (lj-e-circle f 0.0 0.0 r) (lj-e-circle f 0.0 0.0 5.0)
                   (lj-e-line f -3.5 -3.5 3.5 3.5) (lj-e-line f -3.5 3.5 3.5 -3.5)))
  (setq ents (append ents (lj-style "DET" (list (lj-e-circle f 0.0 0.0 (- r 1.5))))))
  (setq k 0)
  (while (< k 8)
    (setq a (+ (/ pi 8.0) (* k (/ pi 4.0))))
    (setq ents (append ents (lj-style "DET" (list (lj-e-line f (* 5.0 (cos a)) (* 5.0 (sin a))
                                                            (* (- r 1.5) (cos a)) (* (- r 1.5) (sin a)))))))
    (setq k (1+ k))
  )
  ents
)

;; Aplique de lectura con brazo, en planta: placa en la pared (origen,
;; con la pared en X = 0), brazo articulado y pantalla sobre el asiento.
(defun lj-ents-aplique (f)
  (append
    (list (lj-e-rect f 0.0 -6.0 1.5 6.0)
          (lj-e-pline f (list (list 1.5 0.0) (list 15.0 0.0) (list 24.0 -8.0)) nil)
          (lj-e-circle f 15.0 0.0 1.2)
          (lj-e-circle f 24.0 -8.0 7.0))
    (lj-style "DET" (list (lj-e-circle f 24.0 -8.0 5.5) (lj-e-circle f 24.0 -8.0 2.0))))
)

;; --- Bloques de alzado y seccion (origen en el suelo) ---

;; Planta en maceta vista de frente: maceta con su borde (centrada en
;; cx, apoyada en y0) y hojas en abanico, hasta "hmax" de alto.
(defun lj-planta-alzado (f cx y0 hmax / ents base lh k a)
  (setq ents (list (lj-e-pline f (list (list (- cx 5.0) y0) (list (+ cx 5.0) y0)
                                       (list (+ cx 6.5) (+ y0 9.0)) (list (- cx 6.5) (+ y0 9.0))) T)
                   (lj-e-rect f (- cx 7.0) (+ y0 9.0) (+ cx 7.0) (+ y0 11.0))))
  (setq base (list cx (+ y0 11.0)) lh (- hmax 12.0))
  (setq k 0)
  (while (< k 7)
    (setq a (+ (* 0.2 pi) (* k (/ (* 0.6 pi) 6.0))))
    (setq ents (append ents (list (lj-e-hoja f base (polar base a (* lh (- 1.0 (* 0.18 (abs (- k 3)))))) 0.32))))
    (setq k (1+ k))
  )
  ents
)

;; Contenido de un hueco de la libreria en alzado (de x = xa a x = xb,
;; apoyado en y = y0, con "hmax" de alto libre): libros de pie de
;; alturas y gruesos variados, alguno inclinado apoyado en el anterior,
;; pilas de libros tumbados, cajas con etiqueta y plantas.
(defun lj-libros-alzado (f xa xb y0 hmax seed / ents x w h r a ca sa xl hh n k yy ww wmax prev)
  (lj-rnd-init seed)
  (setq ents '() x (+ xa 1.0) prev nil)
  (while (< x (- xb 3.0))
    (setq r (lj-rnd))
    (cond
      ;; caja (juegos, archivo) con su etiqueta
      ((and (< r 0.05) (< (+ x 27.0) xb) (> hmax 24.0))
        (setq hh (min 22.0 (- hmax 6.0)))
        (setq ents (append ents (list (lj-e-rect f x y0 (+ x 25.0) (+ y0 hh))
                                      (lj-e-rect f (+ x 8.0) (+ y0 (* 0.55 hh)) (+ x 17.0) (+ y0 (* 0.55 hh) 4.0)))))
        (setq x (+ x 26.5) prev nil))
      ;; planta en maceta
      ((and (< r 0.10) (> x (+ xa 12.0)) (< (+ x 20.0) xb) (> hmax 28.0))
        (setq ents (append ents (lj-planta-alzado f (+ x 9.5) y0 (min 30.0 (- hmax 3.0)))))
        (setq x (+ x 19.0) prev nil))
      ;; pila de libros tumbados
      ((and (< r 0.17) (< (+ x 26.0) xb))
        (setq n (+ 3 (fix (* 3 (lj-rnd)))) k 0 yy y0 wmax 0.0)
        (while (< k n)
          (setq ww (lj-rnd-in 17.0 23.0) hh (lj-rnd-in 2.4 4.4))
          (if (< (+ (- yy y0) hh) (- hmax 2.0))
            (setq ents (append ents (list (lj-e-rect f (+ x (lj-rnd-in 0.0 1.5)) yy (+ x ww) (+ yy hh)))))
          )
          (setq yy (+ yy hh) wmax (max wmax ww) k (1+ k))
        )
        (setq x (+ x wmax 2.0) prev nil))
      ;; libro inclinado, apoyado en el anterior (que esta de pie)
      ((and (< r 0.25) prev (< (+ x 14.0) xb))
        (setq a (lj-rnd-in 0.14 0.26) ca (cos a) sa (sin a) w (lj-rnd-in 1.8 3.4))
        (setq h (min (* hmax 0.8) (/ (- hmax 2.5 (* w sa)) ca)))
        (setq xl (+ x (* h sa) -0.1))
        (setq ents (append ents (list (lj-e-pline f (list (list xl y0)
                                                          (list (+ xl (* w ca)) (+ y0 (* w sa)))
                                                          (list (- (+ xl (* w ca)) (* h sa)) (+ y0 (* w sa) (* h ca)))
                                                          (list (- xl (* h sa)) (+ y0 (* h ca))))
                                                    T))))
        (setq x (+ xl (* w ca) (lj-rnd-in 3.0 7.0)) prev nil))
      ;; libro de pie, a veces con una banda en el lomo
      (T
        (setq w (lj-rnd-in 1.6 4.6) h (min (- hmax 2.5) (* hmax (lj-rnd-in 0.6 0.93))))
        (if (< (+ x w) (- xb 1.0))
          (progn
            (setq ents (append ents (list (lj-e-rect f x y0 (+ x w) (+ y0 h)))))
            (if (< (lj-rnd) 0.3)
              (setq ents (append ents (list (lj-e-line f x (+ y0 (* 0.82 h)) (+ x w) (+ y0 (* 0.82 h))))))
            )
          )
        )
        (setq x (+ x w 0.2) prev T))
    )
  )
  ents
)

;; Alzado frontal de la libreria (origen abajo a la izquierda, en el
;; suelo): zocalo retranqueado, armario bajo con dos puertas por modulo
;; y tiradores, encimera, estantes con sus baldas y, en detalle, lo que
;; hay en cada hueco.
(defun lj-ents-libreria-alz (f largo nMod / H zs hb he tb m nh hc i k x xa xb xm y ents)
  (setq H *lj-lib-alto* zs *lj-alt-zocalo* hb *lj-lib-alt-base* he *lj-lib-encimera*
        tb *lj-lib-tablero* m (/ largo nMod) nh *lj-lib-huecos*)
  ;; alto libre de cada hueco entre baldas
  (setq hc (/ (- H tb (+ hb he) (* (1- nh) tb)) nh))
  (setq ents (list (lj-e-rect f 1.5 0.0 (- largo 1.5) zs)
                   (lj-e-rect f 0.0 zs largo hb)
                   (lj-e-rect f -1.0 hb (+ largo 1.0) (+ hb he))
                   (lj-e-rect f 0.0 (+ hb he) largo H)
                   (lj-e-line f tb (- H tb) (- largo tb) (- H tb))))
  (setq i 0)
  (while (<= i nMod)
    (setq x (* i m))
    (setq ents (append ents (list
      (cond ((= i 0) (lj-e-rect f 0.0 (+ hb he) tb (- H tb)))
            ((= i nMod) (lj-e-rect f (- largo tb) (+ hb he) largo (- H tb)))
            (T (lj-e-rect f (- x (/ tb 2.0)) (+ hb he) (+ x (/ tb 2.0)) (- H tb)))))))
    (setq i (1+ i))
  )
  (setq i 0)
  (while (< i nMod)
    (setq xa (+ (* i m) (if (= i 0) tb (/ tb 2.0))))
    (setq xb (- (* (1+ i) m) (if (= i (1- nMod)) tb (/ tb 2.0))))
    (setq xm (+ (* i m) (/ m 2.0)))
    ;; dos puertas por modulo, con tirador junto al encuentro
    (setq ents (append ents
      (list (lj-e-rect f (+ (* i m) 0.2) (+ zs 0.2) (- xm 0.15) (- hb 0.2))
            (lj-e-rect f (+ xm 0.15) (+ zs 0.2) (- (* (1+ i) m) 0.2) (- hb 0.2)))
      (lj-style "DET" (list (lj-e-rect f (- xm 3.0) (- hb 20.0) (- xm 1.8) (- hb 6.0))
                            (lj-e-rect f (+ xm 1.8) (- hb 20.0) (+ xm 3.0) (- hb 6.0))))))
    ;; baldas y contenido de cada hueco
    (setq k 0 y (+ hb he))
    (while (< k nh)
      (setq ents (append ents (lj-style "DET" (lj-libros-alzado f xa xb y hc (+ 211 (* 53 i) (* 17 k))))))
      (setq y (+ y hc))
      (if (< k (1- nh))
        (setq ents (append ents (list (lj-e-rect f xa y xb (+ y tb))))
              y (+ y tb))
      )
      (setq k (1+ k))
    )
    (setq i (1+ i))
  )
  ents
)

;; Contorno visible de un cojin de respaldo en alzado, de u = ua a u = ub
;; y asomando desde y = y0 hasta y = y1: sin el borde de abajo, que queda
;; detras del cojin de asiento. Esquinas de arriba redondeadas.
(defun lj-respaldo-alz (ua ub y0 y1 / b r)
  (setq r 5.0 b (/ (sin (/ pi 8.0)) (cos (/ pi 8.0))))
  (list (list ua y0 0.0) (list ua (- y1 r) (- b)) (list (+ ua r) y1 0.0)
        (list (- ub r) y1 (- b)) (list ub (- y1 r) 0.0) (list ub y0 0.0))
)

;; Aplique de pared visto de frente (placa centrada en u, a la altura h):
;; placa, brazo y pantalla conica con la bombilla asomando.
(defun lj-aplique-alz (f u h / sx sy)
  (setq sx (- u 8.0) sy (- h 9.0))
  (append
    (list (lj-e-rect f (- u 4.0) (- h 6.0) (+ u 4.0) (+ h 6.0))
          (lj-e-pline f (list (list u h) (list (- u 4.0) (+ h 2.0)) (list sx (+ sy 6.0))) nil)
          (lj-e-pline f (list (list (- sx 3.0) (+ sy 6.0)) (list (+ sx 3.0) (+ sy 6.0))
                              (list (+ sx 7.0) (- sy 4.0)) (list (- sx 7.0) (- sy 4.0))) T))
    (lj-style "DET" (list (lj-e-arc f sx (- sy 4.0) 2.5 pi (* 2.0 pi)))))
)

;; Alzado del banco: el tramo largo visto desde la mesa (sin la mesa).
;; Eje X del bloque = a lo largo del tramo, con 0 en la esquina; origen
;; en el suelo. En la esquina se ve de testa el tramo corto, que viene
;; hacia el observador.
(defun lj-ents-banco-alz (f Lv / B R zs hb hc hr g tp1 tp2 ents nv len k ua ub um)
  (setq B *lj-banco-fondo* R *lj-banco-respaldo* zs 6.0 hb *lj-banco-alt* hc *lj-banco-cojin*
        hr *lj-banco-alt-respaldo* g 1.0)
  ;; cojines sueltos de frente: el de lectura y el de la esquina (tapan
  ;; parte de los respaldos)
  (setq tp1 (lj-poly (lj-xf (lj-cojin-pts 40.0 36.0) (- Lv 32.0) (+ hb hc 18.0) 0.0)))
  (setq tp2 (lj-poly (lj-xf (lj-cojin-pts 36.0 34.0) 27.0 (+ hb hc 17.0) 0.12)))
  ;; suelo
  (setq ents (lj-style "CORTE" (list (lj-e-line f -15.0 0.0 (+ Lv 15.0) 0.0))))
  ;; tramo largo: zocalo, frente del cajon y tapa del asiento
  (setq ents (append ents (list (lj-e-rect f B 0.0 (- Lv 1.5) zs)
                                (lj-e-rect f B zs Lv hb)
                                (lj-e-line f B (- hb 3.0) Lv (- hb 3.0)))))
  ;; un cajon por cojin (con unero), cojines de asiento y de respaldo
  (setq nv (lj-ceil (/ (- Lv B) *lj-banco-cojin-max*)) len (/ (- Lv B) nv) k 0)
  (while (< k nv)
    (setq ua (+ B (* k len)) ub (+ B (* (1+ k) len)) um (/ (+ ua ub) 2.0))
    (setq ents (append ents
      (list (lj-e-rect f (+ ua 0.3) (+ zs 1.0) (- ub 0.3) (- hb 4.0)))
      (lj-style "DET" (list (lj-e-arc f um (- hb 4.0) 3.5 pi (* 2.0 pi))))
      (list (lj-e-pline f (lj-rr (+ ua (/ g 2.0)) hb (- ub (/ g 2.0)) (+ hb hc) 2.5) T))
      (lj-style "DET" (list (lj-e-line f (+ ua 2.0) (+ hb 1.3) (- ub 2.0) (+ hb 1.3))
                            (lj-e-line f (+ ua 2.0) (+ hb hc -1.3) (- ub 2.0) (+ hb hc -1.3))))
      (lj-e-shape f (lj-respaldo-alz (+ ua (/ g 2.0)) (- ub (/ g 2.0)) (+ hb hc) hr) nil (list tp1))))
    (setq k (1+ k))
  )
  ;; esquina: al fondo, el respaldo del tramo largo (asoma por encima del
  ;; tramo corto); delante, la testa del tramo corto con su cojin de
  ;; asiento y su respaldo
  (setq ents (append ents
    (lj-e-shape f (lj-respaldo-alz (- R 0.5) (- B 0.5) (+ hb hc) hr) nil (list tp2))
    (list (lj-e-rect f 0.0 0.0 B hb)
          (lj-e-line f 0.0 (- hb 3.0) B (- hb 3.0))
          (lj-e-pline f (lj-rr (+ R 0.5) hb (- B 0.5) (+ hb hc) 2.5) T)
          (lj-e-pline f (lj-rr4 0.5 hb (- R 0.5) hr 0.0 0.0 2.0 2.0) T))))
  ;; cojines sueltos y aplique en la pared
  (setq ents (append ents
    (lj-ents-cojin f 40.0 36.0 (- Lv 32.0) (+ hb hc 18.0) 0.0 nil)
    (lj-ents-cojin f 36.0 34.0 27.0 (+ hb hc 17.0) 0.12 nil)
    (lj-aplique-alz f (- Lv *lj-aplique-dist*) *lj-aplique-alt*)))
  ents
)

;; Silla vista de lado, mirando hacia -X (asiento delante en xs).
(defun lj-silla-lado (f xs / hs asiento)
  (setq hs *lj-silla-alt*)
  (setq asiento (list (list xs (- hs 4.0)) (list (+ xs 40.0) (- hs 4.0)) (list (+ xs 40.0) hs) (list xs hs)))
  (append
    (list (lj-e-pline f asiento T)
          (lj-e-rect f (+ xs 2.0) 0.0 (+ xs 5.0) (- hs 4.0))
          (lj-e-pline f (list (list (+ xs 39.0) 62.0) (list (+ xs 45.4) 62.0)
                              (list (+ xs 46.9) 84.0) (list (+ xs 40.5) 84.0)) T))
    ;; pata trasera, que sube hasta el respaldo (tapada por el asiento)
    (lj-e-shape f (list (list (+ xs 35.0) 0.0) (list (+ xs 38.0) 0.0) (list (+ xs 42.4) 62.0) (list (+ xs 39.4) 62.0))
                T (list asiento))
    (lj-style "DET" (list (lj-e-line f (+ xs 5.0) 16.0 (+ xs 35.8) 16.0)
                          (lj-e-line f (+ xs 1.0) (- hs 1.3) (+ xs 39.0) (- hs 1.3)))))
)

;; Aplique visto de lado (pared en X = 0), a la altura h.
(defun lj-aplique-lado (f h)
  (append
    (list (lj-e-rect f 0.0 (- h 6.0) 1.5 (+ h 6.0))
          (lj-e-pline f (list (list 1.5 h) (list 14.0 (+ h 2.0)) (list 22.0 (- h 5.0))) nil)
          (lj-e-pline f (list (list 19.0 (- h 5.0)) (list 25.0 (- h 5.0))
                              (list 28.0 (- h 15.0)) (list 16.0 (- h 15.0))) T))
    (lj-style "DET" (list (lj-e-arc f 22.0 (- h 15.0) 2.5 pi (* 2.0 pi)))))
)

;; Lampara colgante vista de frente (eje en cx, borde de la pantalla a
;; la altura lh, pantalla de "ls" de alto): floron en el techo, cable y
;; pantalla de cupula.
(defun lj-lampara-alz (f cx lh ls techo / r)
  (setq r (/ *lj-lampara-diam* 2.0))
  (append
    (list (lj-e-rect f (- cx 6.0) (- techo 3.0) (+ cx 6.0) techo)
          (lj-e-line f cx (- techo 3.0) cx (+ lh ls))
          (lj-e-pline f (list (list (- cx r) lh 0.0) (list (+ cx r) lh 0.18)
                              (list (+ cx 6.0) (- (+ lh ls) 2.0) 0.0) (list (- cx 6.0) (- (+ lh ls) 2.0) 0.18)) T)
          (lj-e-rect f (- cx 6.0) (- (+ lh ls) 2.0) (+ cx 6.0) (+ lh ls)))
    (lj-style "DET" (list (lj-e-line f (- cx (- r 1.5)) (+ lh 1.5) (+ cx (- r 1.5)) (+ lh 1.5)))))
)

;; Seccion A-A por el rincon: perpendicular al tramo largo del banco,
;; por el centro de la mesa, mirando hacia la libreria. Eje X del bloque
;; = eje X de la zona (0 en la cara del tabique); origen en el suelo. Se
;; ven cortados el tabique (rayado), el banco con su cajon, los cojines
;; y la mesa, y mas alla una silla, el cojin de lectura, el aplique y la
;; lampara.
(defun lj-ents-seccion (f x0 x1 / B R zs hb hc hr mt tg techo cx bw xs lh ls)
  (setq B *lj-banco-fondo* R *lj-banco-respaldo* zs 6.0 hb *lj-banco-alt* hc *lj-banco-cojin*
        hr *lj-banco-alt-respaldo* mt *lj-mesa-alt* tg *lj-mesa-grueso* techo *lj-techo*)
  (setq cx (/ (+ x0 x1) 2.0) bw (max 20.0 (- (- x1 x0) 35.0)) xs (+ x1 *lj-silla-separacion*))
  (setq lh (+ mt *lj-lampara-alt*) ls *lj-lampara-pantalla*)
  (append
    ;; tabique cortado (rayado), suelo y techo
    (lj-style "CORTE" (list (lj-e-rect f -8.0 0.0 0.0 techo)
                            (lj-e-line f -30.0 0.0 (+ xs 70.0) 0.0)
                            (lj-e-line f -8.0 techo (+ cx 45.0) techo)))
    (lj-style "DET" (lj-rayado f -8.0 0.0 0.0 techo 4.0))
    ;; banco cortado: cajon con el zocalo retranqueado, cojin de asiento y
    ;; cojin de respaldo (mas grueso abajo); en detalle, la tapa y el cajon
    (lj-style "CORTE" (list (lj-e-pline f (list (list 0.0 0.0) (list (- B 5.0) 0.0) (list (- B 5.0) zs)
                                                (list B zs) (list B hb) (list 0.0 hb)) T)
                            (lj-e-pline f (lj-rr (+ R 0.5) hb (- B 0.5) (+ hb hc) 3.0) T)
                            (lj-e-pline f (list (list 0.5 hb 0.0) (list R hb 0.0) (list 7.5 (- hr 4.0) 0.35)
                                                (list 0.5 hr 0.0)) T)))
    (lj-style "DET" (list (lj-e-line f 0.0 (- hb 3.0) B (- hb 3.0))
                          (lj-e-rect f 2.5 (+ zs 2.0) (- B 3.0) (- hb 5.0))))
    ;; mas alla del corte: cojin de lectura y aplique
    (list (lj-e-pline f (lj-xf (lj-cojin-pts 38.0 13.0) (+ R 7.5) (+ hb hc 19.0) (+ (/ pi 2.0) 0.1)) T))
    (lj-aplique-lado f *lj-aplique-alt*)
    ;; mesa cortada: tablero, columna y base del pie
    (lj-style "CORTE" (list (lj-e-pline f (lj-rr x0 (- mt tg) x1 mt 0.8) T)
                            (lj-e-rect f (- cx 7.0) 4.0 (+ cx 7.0) (- mt tg))
                            (lj-e-pline f (lj-rr4 (- cx (/ bw 2.0)) 0.0 (+ cx (/ bw 2.0)) 4.0 0.0 0.0 1.5 1.5) T)))
    ;; silla (la de mas alla del corte) y lampara colgante
    (lj-silla-lado f xs)
    (lj-lampara-alz f cx lh ls techo))
)

;; --- Creacion en el dibujo ---

;; Crea la definicion de bloque "name" con las entidades "ents" (listas
;; DXF en coordenadas del bloque), con entmake BLOCK ... ENDBLK. El
;; nombre de cada bloque lleva sus medidas (y la unidad del dibujo), asi
;; que si ya existe CON contenido es la misma pieza y se reutiliza
;; tal cual (sin redefinir nada). Si existe pero esta vacio -resto de
;; un intento fallido-, se prueba con otro nombre. Devuelve el nombre
;; del bloque listo para insertar, o nil si no se ha podido crear.
(defun lj-make-block (name ents / rec fails e res)
  (setq rec (tblsearch "BLOCK" name))
  (cond
    ((and rec (cdr (assoc -2 rec))) name)
    (rec (lj-make-block (strcat name "_B") ents))
    (T
      (setq fails 0)
      (if (entmake (list '(0 . "BLOCK") '(8 . "0") (cons 2 name) '(70 . 0) '(10 0.0 0.0 0.0)))
        (progn
          (foreach e ents
            (if (not (entmake e)) (setq fails (1+ fails)))
          )
          (setq res (entmake '((0 . "ENDBLK") (8 . "0"))))
          (if (> fails 0)
            (princ (strcat "\n[LIBJUEGOS] Aviso: " (itoa fails) " entidad(es) del bloque \""
                           name "\" no se han podido crear."))
          )
          (if res
            name
            (progn
              (princ (strcat "\n[LIBJUEGOS] Aviso: no se ha podido cerrar el bloque \"" name "\"."))
              nil
            )
          )
        )
        (progn
          (princ (strcat "\n[LIBJUEGOS] Aviso: no se ha podido crear el bloque \"" name "\"."))
          nil
        )
      )
    )
  )
)

;; Inserta el bloque "name" en la capa "capa", en el punto local (x y)
;; y girado "a" radianes en el marco local (espejado si el marco lo esta).
(defun lj-insert (fr name capa x y a)
  (if name
    (entmake (list '(0 . "INSERT") (cons 8 capa) (cons 2 name) (cons 10 (lj-pt fr x y))
                   '(41 . 1.0) (cons 42 (nth 4 fr)) '(43 . 1.0) (cons 50 (lj-ang fr a))))
  )
)

;; Texto (MTEXT centrado) en la capa "capa", en el punto local (x y), a
;; lo largo de la direccion local "a", de altura h cm. "\\P" separa
;; lineas.
(defun lj-text-l (fr capa txt x y a h)
  (entmake (list '(0 . "MTEXT") '(100 . "AcDbEntity") (cons 8 capa)
                 '(100 . "AcDbMText") (cons 10 (lj-pt fr x y)) (cons 40 (* h (nth 3 fr)))
                 '(41 . 0.0) '(71 . 5) (cons 1 txt) (cons 50 (lj-readable (lj-ang fr a)))))
)

;; Rotulo en la capa de textos.
(defun lj-text (fr txt x y a h)
  (lj-text-l fr (car *lj-capa-textos*) txt x y a h)
)

;; Linea suelta (en el espacio del dibujo) entre dos puntos locales.
(defun lj-line-l (fr capa x0 y0 x1 y1)
  (entmake (list '(0 . "LINE") (cons 8 capa) (cons 10 (lj-pt fr x0 y0)) (cons 11 (lj-pt fr x1 y1))))
)

;; Polilinea suelta de tramos rectos (puntos locales), con grueso de
;; linea "lw" (centesimas de mm; 0 = el de la capa).
(defun lj-pline-l (fr capa pts closed lw / data p w)
  (setq data (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 capa)))
  (if (> lw 0) (setq data (append data (list (cons 370 lw)))))
  (setq data (append data (list '(100 . "AcDbPolyline") (cons 90 (length pts)) (cons 70 (if closed 1 0)))))
  (foreach p pts
    (setq w (lj-pt fr (car p) (cadr p)))
    (setq data (append data (list (list 10 (car w) (cadr w)))))
  )
  (entmake data)
)

;; Cota "a mano" (lineas y texto, sin entidad de cota: no depende del
;; estilo de cota del dibujo) entre los puntos locales a y b, con la
;; linea de cota desplazada "d" en perpendicular (a la izquierda de
;; a->b si d > 0); el texto va por fuera, del lado de "d". Con d = 0 (la
;; distancia libre entre dos piezas) no lleva lineas de referencia.
(defun lj-cota (fr a b d txt / capa ux uy nx ny s pa pb p h)
  (setq capa (car *lj-capa-cotas*) h *lj-cota-texto*)
  (setq ux (cos (angle a b)) uy (sin (angle a b)) nx (- uy) ny ux)
  (setq s (if (minusp d) -1.0 1.0))
  (setq pa (list (+ (car a) (* nx d)) (+ (cadr a) (* ny d)))
        pb (list (+ (car b) (* nx d)) (+ (cadr b) (* ny d))))
  (if (> (abs d) 3.0)
    (progn
      (lj-line-l fr capa (+ (car a) (* nx s 1.5)) (+ (cadr a) (* ny s 1.5))
                         (+ (car pa) (* nx s 2.5)) (+ (cadr pa) (* ny s 2.5)))
      (lj-line-l fr capa (+ (car b) (* nx s 1.5)) (+ (cadr b) (* ny s 1.5))
                         (+ (car pb) (* nx s 2.5)) (+ (cadr pb) (* ny s 2.5)))
    )
  )
  (lj-line-l fr capa (car pa) (cadr pa) (car pb) (cadr pb))
  (foreach p (list pa pb)
    (lj-line-l fr capa (- (car p) (* 1.5 (+ ux nx))) (- (cadr p) (* 1.5 (+ uy ny)))
                       (+ (car p) (* 1.5 (+ ux nx))) (+ (cadr p) (* 1.5 (+ uy ny))))
  )
  (lj-text-l fr capa txt (+ (/ (+ (car pa) (car pb)) 2.0) (* nx s 0.9 h))
                         (+ (/ (+ (cadr pa) (cadr pb)) 2.0) (* ny s 0.9 h)) (angle a b) h)
)

;; Marca de seccion en planta: en los extremos de la linea de corte (a
;; la altura "y", de x = xa a x = xb) un trazo grueso, una flecha hacia
;; donde se mira (+Y local) y la letra.
(defun lj-marca-seccion (fr xa xb y letra / capa x)
  (setq capa (car *lj-capa-cotas*))
  (foreach x (list xa xb)
    (lj-pline-l fr capa (list (list (- x 7.0) y) (list (+ x 7.0) y)) nil 50)
    (lj-pline-l fr capa (list (list x y) (list x (+ y 11.0))) nil 0)
    (lj-pline-l fr capa (list (list (- x 2.5) (+ y 6.5)) (list x (+ y 11.0)) (list (+ x 2.5) (+ y 6.5))) nil 0)
    (lj-text-l fr capa letra (+ x 7.0) (+ y 8.0) 0.0 8.0)
  )
)

;; Dibuja todas las piezas de la distribucion "lay" en planta, en el
;; marco "fr", con sus rotulos, las cotas de la libreria y de los dos
;; pasos, y la marca de la seccion A-A. Devuelve el numero de piezas
;; que NO se han podido insertar.
(defun lj-draw (fr lay / f anchoZ fondoZ capaM capaL largoLib nMod xa x0 y0 mW mL x1 y1 Lv Lh
                         cx cy nv fallos blk yc)
  (setq f (nth 3 fr) anchoZ (nth 5 fr) fondoZ (nth 6 fr))
  (setq capaM (car *lj-capa-muebles*) capaL (car *lj-capa-luz*))
  (lj-ensure-layer *lj-capa-muebles*)
  (lj-ensure-layer *lj-capa-luz*)
  (lj-ensure-layer *lj-capa-cotas*)
  (lj-ensure-layer *lj-capa-textos*)
  (setq largoLib (lj-get lay "LIB") nMod (lj-get lay "NMOD") xa (lj-get lay "XA")
        x0 (lj-get lay "X0") y0 (lj-get lay "Y0") mW (lj-get lay "MW") mL (lj-get lay "ML")
        x1 (lj-get lay "X1") y1 (lj-get lay "Y1") Lv (lj-get lay "LV") Lh (lj-get lay "LH"))
  (setq cx (+ x0 (/ mW 2.0)) cy (+ y0 (/ mL 2.0)))
  (setq fallos 0)

  ;; Libreria, con su rotulo delante y la cota de su largo.
  (if largoLib
    (progn
      (setq blk (lj-make-block (lj-blk-name (strcat "LJ_LIBRERIA_" (lj-tag largoLib) "x"
                                                    (lj-tag *lj-lib-fondo*) "_" (itoa nMod) "MOD_DET") f)
                               (lj-ents-libreria f largoLib nMod)))
      (if (not (lj-insert fr blk capaM xa fondoZ 0.0)) (setq fallos (1+ fallos)))
      (lj-text fr "LIBRERIA" (+ xa (/ largoLib 2.0)) (- fondoZ *lj-lib-fondo* 7.0) 0.0 *lj-texto-alto*)
      (lj-cota fr (list xa (- fondoZ *lj-lib-fondo*)) (list (+ xa largoLib) (- fondoZ *lj-lib-fondo*))
               -20.0 (lj-cm largoLib))
    )
  )

  ;; Rincon de juegos (banco en L + mesa). Rotulo del banco a lo largo
  ;; de su primer cojin del tramo largo, y el de la mesa en la franja
  ;; entre la lampara (centrada) y su borde.
  (setq blk (lj-make-block (lj-blk-name (strcat "LJ_RINCON_" (lj-tag Lh) "x" (lj-tag Lv) "x"
                                                (lj-tag *lj-banco-fondo*) "_MESA_" (lj-tag mW) "x"
                                                (lj-tag mL) "_DET") f)
                           (lj-ents-rincon f Lv Lh x0 y0 x1 y1)))
  (if (not (lj-insert fr blk capaM 0.0 0.0 0.0)) (setq fallos (1+ fallos)))
  (setq nv (lj-ceil (/ (- Lv *lj-banco-fondo*) *lj-banco-cojin-max*)))
  (lj-text fr "BANCO" (/ (+ *lj-banco-respaldo* *lj-banco-fondo*) 2.0)
           (+ *lj-banco-fondo* (/ (- Lv *lj-banco-fondo*) (* 2.0 nv))) (/ pi 2.0) *lj-texto-alto*)
  (lj-text fr (strcat "MESA JUEGOS\\P" (lj-cm mW) " x " (lj-cm mL))
           cx (- cy (/ (+ (/ mL 2.0) (/ *lj-lampara-diam* 2.0)) 2.0)) 0.0 (* 0.85 *lj-texto-alto*))

  ;; Sillas: en el lado libre, mirando a la mesa y arrimadas a ella; y
  ;; en la cabecera si hay sitio.
  (setq blk (lj-make-block (lj-blk-name (strcat "LJ_SILLA_" (lj-tag *lj-silla-ancho*) "x"
                                                (lj-tag (+ *lj-silla-asiento* *lj-silla-respaldo*)) "_DET") f)
                           (lj-ents-silla f)))
  (foreach yc (lj-get lay "SILLAS")
    (if (not (lj-insert fr blk capaM (+ x1 *lj-silla-separacion* (/ *lj-silla-asiento* 2.0)) yc 0.0))
      (setq fallos (1+ fallos))
    )
  )
  (if (lj-get lay "CABECERA")
    (if (not (lj-insert fr blk capaM cx (+ y1 *lj-silla-separacion* (/ *lj-silla-asiento* 2.0)) (/ pi 2.0)))
      (setq fallos (1+ fallos))
    )
  )

  ;; Iluminacion: colgante sobre el centro de la mesa y aplique de
  ;; lectura en el tabique, cerca del extremo del banco.
  (setq blk (lj-make-block (lj-blk-name (strcat "LJ_LAMPARA_D" (lj-tag *lj-lampara-diam*) "_DET") f)
                           (lj-ents-lampara f)))
  (if (not (lj-insert fr blk capaL cx cy 0.0)) (setq fallos (1+ fallos)))
  (setq blk (lj-make-block (lj-blk-name "LJ_APLIQUE_DET" f) (lj-ents-aplique f)))
  (if (not (lj-insert fr blk capaL 0.0 (- Lv *lj-aplique-dist*) 0.0)) (setq fallos (1+ fallos)))

  ;; Cotas de los dos pasos libres y marca de la seccion A-A.
  (lj-cota fr (list 88.0 (max Lv (if (lj-get lay "CABECERA") (+ y1 *lj-silla-uso*) 0.0)))
              (list 88.0 (- fondoZ (if largoLib *lj-lib-fondo* 0.0))) 0.0
              (strcat "paso " (lj-cm (lj-get lay "PASOSUP"))))
  (lj-cota fr (list (- anchoZ (lj-get lay "PASOLAT")) 20.0) (list anchoZ 20.0) 0.0
              (strcat "paso " (lj-cm (lj-get lay "PASOLAT"))))
  (lj-marca-seccion fr -18.0 (+ x1 62.0) cy "A")

  fallos
)

;; Marco "de hoja" para alzados y secciones: origen en el punto p (del
;; SCP), ejes del SCP, sin espejar.
(defun lj-frame-hoja (p f / o)
  (setq o (trans p 1 0))
  (list (list (car o) (cadr o)) (lj-v2 (trans '(1.0 0.0 0.0) 1 0 T) 1.0)
        (lj-v2 (trans '(0.0 1.0 0.0) 1 0 T) 1.0) f 1.0 0.0 0.0)
)

;; Alzado de la libreria, alzado del banco y seccion A-A, en fila hacia
;; la derecha a partir del punto p (del SCP), con sus cotas y titulos.
;; Devuelve el numero de piezas que no se han podido insertar.
(defun lj-draw-alzados (p lay f / fr capaA largoLib nMod Lv x0 x1 mW mL xs hb he H m i fallos blk)
  (setq fr (lj-frame-hoja p f) capaA (car *lj-capa-alzados*) fallos 0)
  (lj-ensure-layer *lj-capa-alzados*)
  (lj-ensure-layer *lj-capa-cotas*)
  (lj-ensure-layer *lj-capa-textos*)
  (setq largoLib (lj-get lay "LIB") nMod (lj-get lay "NMOD") Lv (lj-get lay "LV")
        x0 (lj-get lay "X0") x1 (lj-get lay "X1") mW (lj-get lay "MW") mL (lj-get lay "ML"))
  (setq hb *lj-lib-alt-base* he *lj-lib-encimera* H *lj-lib-alto* xs 0.0)

  ;; 1. Alzado de la libreria.
  (if largoLib
    (progn
      (setq blk (lj-make-block (lj-blk-name (strcat "LJ_LIBRERIA_ALZ_" (lj-tag largoLib) "x" (lj-tag H)
                                                    "_" (itoa nMod) "MOD") f)
                               (lj-ents-libreria-alz f largoLib nMod)))
      (if (not (lj-insert fr blk capaA 0.0 0.0 0.0)) (setq fallos (1+ fallos)))
      (setq m (/ largoLib nMod) i 0)
      (while (< i nMod)
        (lj-cota fr (list (* i m) 0.0) (list (* (1+ i) m) 0.0) -14.0 (lj-cm m))
        (setq i (1+ i))
      )
      (lj-cota fr (list 0.0 0.0) (list largoLib 0.0) -28.0 (lj-cm largoLib))
      (lj-cota fr (list 0.0 0.0) (list 0.0 (+ hb he)) 14.0 (lj-cm (+ hb he)))
      (lj-cota fr (list 0.0 (+ hb he)) (list 0.0 H) 14.0 (lj-cm (- H hb he)))
      (lj-cota fr (list largoLib 0.0) (list largoLib H) -14.0 (lj-cm H))
      (lj-text fr "ALZADO LIBRERIA" (/ largoLib 2.0) -48.0 0.0 10.0)
      (setq xs (+ largoLib 130.0))
    )
  )

  ;; 2. Alzado del banco (tramo largo, visto desde la mesa).
  (setq fr (lj-frame-hoja (polar p 0.0 (* f xs)) f))
  (setq blk (lj-make-block (lj-blk-name (strcat "LJ_BANCO_ALZ_" (lj-tag Lv)) f) (lj-ents-banco-alz f Lv)))
  (if (not (lj-insert fr blk capaA 0.0 0.0 0.0)) (setq fallos (1+ fallos)))
  (lj-cota fr (list 0.0 0.0) (list Lv 0.0) -22.0 (lj-cm Lv))
  (lj-cota fr (list Lv 0.0) (list Lv (+ *lj-banco-alt* *lj-banco-cojin*)) -14.0
              (lj-cm (+ *lj-banco-alt* *lj-banco-cojin*)))
  (lj-cota fr (list Lv 0.0) (list Lv *lj-banco-alt-respaldo*) -30.0 (lj-cm *lj-banco-alt-respaldo*))
  (lj-text fr "ALZADO BANCO (TRAMO LARGO, SIN MESA)" (/ Lv 2.0) -48.0 0.0 10.0)

  ;; 3. Seccion A-A por el rincon.
  (setq fr (lj-frame-hoja (polar p 0.0 (* f (+ xs Lv 150.0))) f))
  (setq blk (lj-make-block (lj-blk-name (strcat "LJ_SECCION_A_" (lj-tag mW) "x" (lj-tag mL)) f)
                           (lj-ents-seccion f x0 x1)))
  (if (not (lj-insert fr blk capaA 0.0 0.0 0.0)) (setq fallos (1+ fallos)))
  (lj-cota fr (list 0.0 0.0) (list *lj-banco-fondo* 0.0) -14.0 (lj-cm *lj-banco-fondo*))
  (lj-cota fr (list x0 *lj-mesa-alt*) (list x1 *lj-mesa-alt*) 12.0 (lj-cm mW))
  (lj-cota fr (list x0 *lj-mesa-alt*) (list *lj-banco-fondo* *lj-mesa-alt*) 24.0
              (lj-cm (- *lj-banco-fondo* x0)))
  ;; alturas: el asiento del banco a la izquierda (por fuera del
  ;; tabique); la mesa y la lampara a la derecha, pasada la silla
  (lj-cota fr (list -8.0 0.0) (list -8.0 (+ *lj-banco-alt* *lj-banco-cojin*)) 14.0
              (lj-cm (+ *lj-banco-alt* *lj-banco-cojin*)))
  (setq xs (+ x1 *lj-silla-separacion* 60.0))
  (lj-cota fr (list xs 0.0) (list xs *lj-mesa-alt*) -10.0 (lj-cm *lj-mesa-alt*))
  (lj-cota fr (list xs *lj-mesa-alt*) (list xs (+ *lj-mesa-alt* *lj-lampara-alt*)) -10.0
              (lj-cm *lj-lampara-alt*))
  (lj-text fr "SECCION A-A" (/ (+ x1 20.0) 2.0) -48.0 0.0 10.0)

  fallos
)

;; Resumen en la linea de comandos.
(defun lj-report (anchoZ fondoZ unidad lay fallos / largoLib nMod a)
  (setq largoLib (lj-get lay "LIB") nMod (lj-get lay "NMOD"))
  (princ (strcat "\n[LIBJUEGOS] Zona de " (lj-m anchoZ) " x " (lj-m fondoZ) " m (dibujo en "
                 (strcase unidad T) ")."))
  (if largoLib
    (princ (strcat "\n  - Libreria: " (lj-cm largoLib) " x " (lj-cm *lj-lib-fondo*) " cm, "
                   (itoa nMod) " modulos de " (lj-cm (/ largoLib nMod)) " cm (armario bajo de "
                   (lj-cm *lj-lib-fondo*) " cm y estantes de " (lj-cm *lj-lib-fondo-sup*)
                   " cm, hasta " (lj-cm *lj-lib-alto*) " cm de alto)."))
  )
  (princ (strcat "\n  - Banco corrido en L con cajones: fondo " (lj-cm *lj-banco-fondo*)
                 " cm, tramos de " (lj-cm (lj-get lay "LV")) " y " (lj-cm (lj-get lay "LH")) " cm."))
  (princ (strcat "\n  - Mesa de juegos: " (lj-cm (lj-get lay "MW")) " x " (lj-cm (lj-get lay "ML"))
                 " cm, con " (itoa (+ (length (lj-get lay "SILLAS")) (if (lj-get lay "CABECERA") 1 0)))
                 " silla(s)."))
  (princ (strcat "\n  - Paso libre delante de la libreria: " (lj-cm (lj-get lay "PASOSUP"))
                 " cm. Junto al sofa: " (lj-cm (lj-get lay "PASOLAT"))
                 " cm (con las sillas retiradas)."))
  (foreach a (lj-get lay "AVISOS")
    (princ (strcat "\n[LIBJUEGOS] Aviso: " a))
  )
  (if (> fallos 0)
    (princ (strcat "\n[LIBJUEGOS] Aviso: " (itoa fallos) " pieza(s) no se han podido insertar."))
  )
)

;; --- Comando ---

(defun c:LIBJUEGOS ( / *error* doc p1 p2 sx sy unidad f kw fr anchoZ fondoZ lay fallos pa)

  (defun *error* (msg)
    (if doc (vl-catch-all-apply 'vla-EndUndoMark (list doc)))
    (if (and msg (not (wcmatch (strcase msg) "*CANCEL*,*EXIT*,*ABORT*,*SALIR*,*QUIT*")))
      (princ (strcat "\n[LIBJUEGOS] Error: " msg))
    )
    (princ)
  )

  (setq p1 (getpoint "\n[LIBJUEGOS] Esquina interior del tabique en L (donde va el banco): "))
  (if (not p1) (progn (princ "\n[LIBJUEGOS] Cancelado.") (exit)))
  (setq p2 (getcorner p1 "\n[LIBJUEGOS] Esquina opuesta de la zona (fachada, en la linea del respaldo del sofa): "))
  (if (not p2) (progn (princ "\n[LIBJUEGOS] Cancelado.") (exit)))

  (setq sx (abs (- (car p2) (car p1))))
  (setq sy (abs (- (cadr p2) (cadr p1))))
  (if (or (< sx 1e-6) (< sy 1e-6))
    (progn (princ "\n[LIBJUEGOS] Las dos esquinas deben formar un rectangulo. Cancelado.") (exit))
  )

  (setq unidad (lj-ask-units sx sy))
  (setq f (lj-unit-factor unidad))

  ;; Tamano minimo, antes de preguntar nada mas (el ancho y el fondo son
  ;; los dos lados designados, en un orden u otro segun la orientacion).
  (if (< (min sx sy) (* f *lj-zona-min*))
    (progn
      (princ (strcat "\n[LIBJUEGOS] La zona (" (lj-m (/ sx f)) " x " (lj-m (/ sy f))
                     " m) es demasiado pequena: hacen falta al menos " (lj-m *lj-zona-min*) " x "
                     (lj-m *lj-zona-min*) " m. Cancelado."))
      (exit)
    )
  )

  (initget "Aceptar Girar")
  (setq kw (getkword "\n[LIBJUEGOS] Libreria contra el lado paralelo al eje X, el mas alejado del banco. [Aceptar/Girar] <Aceptar>: "))

  (setq fr (lj-frame p1 p2 (= kw "Girar") f))
  (setq anchoZ (nth 5 fr) fondoZ (nth 6 fr))

  (setq lay (lj-layout anchoZ fondoZ))

  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (vl-catch-all-apply 'vla-StartUndoMark (list doc))
  (setq fallos (lj-draw fr lay))
  (vl-catch-all-apply 'vla-EndUndoMark (list doc))
  (setq doc nil)

  (lj-report anchoZ fondoZ unidad lay fallos)

  ;; Alzados y seccion, si se quieren, en un punto libre del dibujo.
  (setq pa (getpoint "\n[LIBJUEGOS] Punto para dibujar los alzados y la seccion A-A (Intro para no dibujarlos): "))
  (if pa
    (progn
      (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
      (vl-catch-all-apply 'vla-StartUndoMark (list doc))
      (setq fallos (lj-draw-alzados pa lay f))
      (vl-catch-all-apply 'vla-EndUndoMark (list doc))
      (setq doc nil)
      (princ "\n[LIBJUEGOS] Alzados dibujados: libreria, banco y seccion A-A (capas LJ-ALZADOS, LJ-COTAS y LJ-TEXTOS).")
      (if (> fallos 0)
        (princ (strcat "\n[LIBJUEGOS] Aviso: " (itoa fallos) " alzado(s) no se han podido insertar."))
      )
    )
  )
  (princ)
)

(princ "\n[LIBJUEGOS] Cargado. Escribe LIBJUEGOS para dibujar la zona de libreria y juegos.")
(princ)
