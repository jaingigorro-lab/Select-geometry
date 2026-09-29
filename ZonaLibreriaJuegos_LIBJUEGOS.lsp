(vl-load-com)

;; ==========================================================
;; LIBJUEGOS - Dibuja en planta, a escala real, una ZONA DE LIBRERIA
;; Y JUEGOS para la parte de atras de un salon: el hueco que queda
;; detras del sofa, entre la fachada y un tabique en L.
;;
;; Concepto (pensado para un hueco de unos 3 x 3 m con dos accesos:
;; uno desde el pasillo, junto a la fachada, y otro por el hueco del
;; tabique inferior, ambos camino del sofa):
;;
;;   - LIBRERIA a medida contra la fachada (el tramo sin ventanas entre
;;     las dos ventanas): base con puertas de 40 cm de fondo para juegos
;;     de mesa, puzles y juguetes -las cajas de juego estandar miden
;;     unos 30 x 30 cm y no caben en una estanteria de libros normal-,
;;     y encima estantes abiertos de 30 cm para libros, hasta 2,40 m.
;;     Modulos de 80 cm como maximo, para que los estantes no se
;;     comben con el peso de los libros.
;;
;;   - RINCON DE JUEGOS en la esquina del tabique en L (la parte mas
;;     recogida de la zona, fuera de los pasos): BANCO CORRIDO EN L
;;     con arcon bajo el asiento (mas almacenaje para juegos) y cojines
;;     de respaldo contra el tabique, MESA DE JUEGOS -la mayor medida
;;     estandar que quepa, normalmente 90 x 120- y sillas en el lado
;;     libre. Caben 5-6 jugadores ocupando mucho menos que una mesa
;;     con sillas por los cuatro lados: el banco no necesita espacio
;;     para retirar la silla. Lampara colgante centrada sobre la mesa
;;     y un aplique de lectura en el extremo del banco.
;;
;;   - Se deja SIEMPRE un paso libre de 90 cm como minimo delante de
;;     la libreria (del pasillo al sofa) y junto al respaldo del sofa
;;     (del hueco inferior al sofa): la mesa, las sillas -contando el
;;     espacio para retirarlas y sentarse- y el banco se dimensionan
;;     para no invadirlos.
;;
;; Cada mueble se crea como un BLOQUE (para moverlo, girarlo o
;; borrarlo como una sola pieza) en la capa LJ-MOBILIARIO -el banco y la
;; mesa van juntos en un unico bloque, porque la mesa vuela sobre el
;; asiento y en planta tapa parte del banco-; la
;; iluminacion va en LJ-ILUMINACION y los rotulos en LJ-TEXTOS. Toda
;; la geometria se crea con entmake -sin comandos ni metodos ActiveX-,
;; y queda en un unico paso de deshacer: un solo H (U) lo quita entero.
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
(setq *lj-lib-fondo* 40.0)         ; fondo de la base con puertas (juegos)
(setq *lj-lib-fondo-sup* 30.0)     ; fondo de los estantes altos (libros)
(setq *lj-lib-alto* 240.0)         ; altura total (solo para el resumen)
(setq *lj-lib-margen-ini* 8.0)     ; holgura en el extremo del lado del banco
(setq *lj-lib-margen-fin* 20.0)    ; holgura en el extremo del lado del sofa
(setq *lj-lib-modulo-max* 80.0)    ; ancho maximo de modulo
(setq *lj-lib-tablero* 2.0)        ; grueso de costados y divisiones

;; Paso libre minimo delante de la libreria y junto al sofa.
(setq *lj-paso* 90.0)

;; Banco corrido en L contra el tabique.
(setq *lj-banco-fondo* 50.0)       ; fondo total (asiento + cojin de respaldo)
(setq *lj-banco-respaldo* 10.0)    ; grueso del cojin de respaldo
(setq *lj-banco-cojin-max* 70.0)   ; largo maximo de cada cojin de asiento
(setq *lj-banco-sobrante* 5.0)     ; lo que el banco pasa del borde de la mesa

;; Mesa de juegos: medidas estandar (ancho x largo) por orden de
;; preferencia. Se usa la primera que quepa sin invadir los pasos; el
;; largo va a lo largo del tramo del banco paralelo al eje Y local.
(setq *lj-mesas* '((90.0 140.0) (90.0 120.0) (80.0 120.0) (80.0 100.0) (70.0 90.0) (70.0 80.0)))
(setq *lj-mesa-solape* 10.0)       ; lo que la mesa vuela sobre el asiento (>= 0)
(setq *lj-mesa-radio* 5.0)         ; radio de las esquinas redondeadas
(setq *lj-mesa-holgura* 10.0)      ; separacion minima entre la mesa y el paso

;; Sillas en el lado libre de la mesa.
(setq *lj-silla-ancho* 45.0)
(setq *lj-silla-asiento* 40.0)     ; fondo del asiento
(setq *lj-silla-respaldo* 7.0)     ; grueso del respaldo
(setq *lj-silla-separacion* 2.0)   ; hueco entre el borde de la mesa y el asiento
(setq *lj-silla-uso* 75.0)         ; espacio, desde el borde de la mesa, para
                                   ; retirar la silla y sentarse
(setq *lj-silla-hueco* 10.0)       ; separacion minima entre sillas

;; Iluminacion.
(setq *lj-lampara-diam* 45.0)      ; lampara colgante sobre la mesa
(setq *lj-aplique-radio* 8.0)      ; aplique de lectura en el tabique
(setq *lj-aplique-dist* 25.0)      ; distancia del aplique al extremo del banco

;; Altura de los rotulos.
(setq *lj-texto-alto* 8.0)

;; Tamano minimo de la zona (cada lado): por debajo no cabe el rincon de
;; juegos con un paso minimamente util al lado.
(setq *lj-zona-min* 200.0)

;; Capas: (nombre color-ACI).
(setq *lj-capa-muebles* '("LJ-MOBILIARIO" 3))
(setq *lj-capa-luz* '("LJ-ILUMINACION" 6))
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

;; --- Geometria de los bloques (listas DXF, en cm locales x f) ---

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

;; Libreria de "largo" cm con nMod modulos. Origen en su extremo
;; inicial, sobre la cara de la fachada; el mueble queda hacia -Y local.
;; Se ve la base (40) y, encima, los estantes (30) con sus costados y
;; divisiones.
(defun lj-ents-libreria (f largo nMod / fb fs tb m i x ents)
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
  ents
)

;; Tablero de mesa de (x0 y0) a (x1 y1), con las esquinas redondeadas.
(defun lj-ents-mesa (f x0 y0 x1 y1 / r b)
  (setq r *lj-mesa-radio*)
  (setq b (/ (sin (/ pi 8.0)) (cos (/ pi 8.0))))   ; bulge de un cuarto de circulo
  (list (lj-e-pline f (list (list (+ x0 r) y0 0.0) (list (- x1 r) y0 b)
                            (list x1 (+ y0 r) 0.0) (list x1 (- y1 r) b)
                            (list (- x1 r) y1 0.0) (list (+ x0 r) y1 b)
                            (list x0 (- y1 r) 0.0) (list x0 (+ y0 r) b))
                    T))
)

;; Rincon de juegos: banco corrido en L + mesa, como UNA sola pieza (la
;; mesa vuela sobre el asiento, asi que van juntos). Origen en la
;; esquina del tabique; tramo del banco de largo Lv a lo largo de Y
;; local y de largo Lh a lo largo de X local, ambos del fondo del banco;
;; mesa de (x0 y0) a (x1 y1). Las lineas del banco que quedan debajo del
;; tablero no se dibujan: en planta, la mesa las tapa.
(defun lj-ents-rincon (f Lv Lh x0 y0 x1 y1 / B R cx cy ents nv nh i yy xx)
  (setq B *lj-banco-fondo* R *lj-banco-respaldo*)
  ;; hasta donde llegan, por el lado del banco, las lineas que se meten
  ;; bajo la mesa (el borde de la mesa, o el frente del asiento si la
  ;; mesa no llegara a volar sobre el)
  (setq cx (min x0 B) cy (min y0 B))
  (setq ents (list
    ;; contorno: el frente de cada tramo solo asoma pasado el borde de la mesa
    (lj-e-pline f (list (list B y1) (list B Lv) (list 0.0 Lv) (list 0.0 0.0)
                        (list Lh 0.0) (list Lh B) (list x1 B)) nil)
    ;; cojines de respaldo contra el tabique
    (lj-e-pline f (list (list Lh R) (list R R) (list R Lv)) nil)
    ;; cojin de la esquina
    (lj-e-line f R B cx B)
    (lj-e-line f B R B cy)))
  ;; divisiones de los cojines de asiento de cada tramo
  (setq nv (lj-ceil (/ (- Lv B) *lj-banco-cojin-max*)))
  (setq i 1)
  (while (< i nv)
    (setq yy (+ B (* i (/ (- Lv B) nv))))
    (setq ents (append ents (list (lj-e-line f R yy (if (< yy y1) cx B) yy))))
    (setq i (1+ i))
  )
  (setq nh (lj-ceil (/ (- Lh B) *lj-banco-cojin-max*)))
  (setq i 1)
  (while (< i nh)
    (setq xx (+ B (* i (/ (- Lh B) nh))))
    (setq ents (append ents (list (lj-e-line f xx R xx (if (< xx x1) cy B)))))
    (setq i (1+ i))
  )
  (append ents (lj-ents-mesa f x0 y0 x1 y1))
)

;; Silla. Origen en el centro del asiento, mirando hacia -X local.
(defun lj-ents-silla (f / hw ha rb)
  (setq hw (/ *lj-silla-ancho* 2.0) ha (/ *lj-silla-asiento* 2.0) rb *lj-silla-respaldo*)
  (list (lj-e-rect f (- ha) (- 1.5 hw) ha (- hw 1.5))
        (lj-e-rect f ha (- hw) (+ ha rb) hw))
)

;; Punto de luz en techo (circulo con aspa). Origen en su centro.
(defun lj-ents-lampara (f / r d)
  (setq r (/ *lj-lampara-diam* 2.0))
  (setq d (* r (cos (/ pi 4.0))))
  (list (lj-e-circle f 0.0 0.0 r)
        (lj-e-line f (- d) (- d) d d)
        (lj-e-line f (- d) d d (- d)))
)

;; Aplique de pared: semicirculo hacia +X local. Origen en la pared.
(defun lj-ents-aplique (f / r d)
  (setq r *lj-aplique-radio*)
  (setq d (* r (cos (/ pi 4.0))))
  (list (lj-e-arc f 0.0 0.0 r (* 1.5 pi) (* 0.5 pi))
        (lj-e-line f 0.0 (- r) 0.0 r)
        (lj-e-line f 0.0 0.0 d d)
        (lj-e-line f 0.0 0.0 d (- d)))
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

;; Rotulo (MTEXT centrado) en el punto local (x y), a lo largo de la
;; direccion local "a", de altura h cm. "\\P" separa lineas.
(defun lj-text (fr txt x y a h)
  (entmake (list '(0 . "MTEXT") '(100 . "AcDbEntity") (cons 8 (car *lj-capa-textos*))
                 '(100 . "AcDbMText") (cons 10 (lj-pt fr x y)) (cons 40 (* h (nth 3 fr)))
                 '(41 . 0.0) '(71 . 5) (cons 1 txt) (cons 50 (lj-readable (lj-ang fr a)))))
)

;; Dibuja todas las piezas de la distribucion "lay" en el marco "fr".
;; Devuelve el numero de piezas que NO se han podido insertar.
(defun lj-draw (fr lay / f fondoZ capaM capaL largoLib nMod xa x0 y0 mW mL x1 y1 Lv Lh
                         cx cy k nv fallos blk yc)
  (setq f (nth 3 fr) fondoZ (nth 6 fr))
  (setq capaM (car *lj-capa-muebles*) capaL (car *lj-capa-luz*))
  (lj-ensure-layer *lj-capa-muebles*)
  (lj-ensure-layer *lj-capa-luz*)
  (lj-ensure-layer *lj-capa-textos*)
  (setq largoLib (lj-get lay "LIB") nMod (lj-get lay "NMOD") xa (lj-get lay "XA")
        x0 (lj-get lay "X0") y0 (lj-get lay "Y0") mW (lj-get lay "MW") mL (lj-get lay "ML")
        x1 (lj-get lay "X1") y1 (lj-get lay "Y1") Lv (lj-get lay "LV") Lh (lj-get lay "LH"))
  (setq cx (+ x0 (/ mW 2.0)) cy (+ y0 (/ mL 2.0)))
  (setq fallos 0)

  ;; Libreria. El rotulo va dentro de un modulo (el central, o el de la
  ;; derecha del centro si son pares), entre dos divisiones.
  (if largoLib
    (progn
      (setq blk (lj-make-block (lj-blk-name (strcat "LJ_LIBRERIA_" (lj-tag largoLib) "x"
                                                    (lj-tag *lj-lib-fondo*) "_" (itoa nMod) "MOD") f)
                               (lj-ents-libreria f largoLib nMod)))
      (if (not (lj-insert fr blk capaM xa fondoZ 0.0)) (setq fallos (1+ fallos)))
      (setq k (/ nMod 2))
      (lj-text fr "LIBRERIA" (+ xa (* (+ k 0.5) (/ largoLib nMod))) (- fondoZ (/ *lj-lib-fondo-sup* 2.0))
               0.0 *lj-texto-alto*)
    )
  )

  ;; Rincon de juegos (banco en L + mesa). Rotulo del banco a lo largo
  ;; del ultimo cojin del tramo largo (el del extremo de lectura), y el
  ;; de la mesa en la franja entre la lampara (centrada) y su borde.
  (setq blk (lj-make-block (lj-blk-name (strcat "LJ_RINCON_" (lj-tag Lh) "x" (lj-tag Lv) "x"
                                                (lj-tag *lj-banco-fondo*) "_MESA_" (lj-tag mW) "x"
                                                (lj-tag mL)) f)
                           (lj-ents-rincon f Lv Lh x0 y0 x1 y1)))
  (if (not (lj-insert fr blk capaM 0.0 0.0 0.0)) (setq fallos (1+ fallos)))
  (setq nv (lj-ceil (/ (- Lv *lj-banco-fondo*) *lj-banco-cojin-max*)))
  (lj-text fr "BANCO" (/ (+ *lj-banco-respaldo* *lj-banco-fondo*) 2.0)
           (- Lv (/ (- Lv *lj-banco-fondo*) (* 2.0 nv))) (/ pi 2.0) *lj-texto-alto*)
  (lj-text fr (strcat "MESA JUEGOS\\P" (lj-cm mW) " x " (lj-cm mL))
           cx (- cy (/ (+ (/ mL 2.0) (/ *lj-lampara-diam* 2.0)) 2.0)) 0.0 (* 0.85 *lj-texto-alto*))

  ;; Sillas: en el lado libre, mirando a la mesa y arrimadas a ella; y
  ;; en la cabecera si hay sitio.
  (setq blk (lj-make-block (lj-blk-name (strcat "LJ_SILLA_" (lj-tag *lj-silla-ancho*) "x"
                                                (lj-tag (+ *lj-silla-asiento* *lj-silla-respaldo*))) f)
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
  (setq blk (lj-make-block (lj-blk-name (strcat "LJ_LAMPARA_D" (lj-tag *lj-lampara-diam*)) f)
                           (lj-ents-lampara f)))
  (if (not (lj-insert fr blk capaL cx cy 0.0)) (setq fallos (1+ fallos)))
  (setq blk (lj-make-block (lj-blk-name (strcat "LJ_APLIQUE_R" (lj-tag *lj-aplique-radio*)) f)
                           (lj-ents-aplique f)))
  (if (not (lj-insert fr blk capaL 0.0 (- Lv *lj-aplique-dist*) 0.0)) (setq fallos (1+ fallos)))

  fallos
)

;; Resumen en la linea de comandos.
(defun lj-report (anchoZ fondoZ unidad lay fallos / largoLib nMod a)
  (setq largoLib (lj-get lay "LIB") nMod (lj-get lay "NMOD"))
  (princ (strcat "\n[LIBJUEGOS] Zona de " (lj-m anchoZ) " x " (lj-m fondoZ) " m (dibujo en "
                 (strcase unidad T) ")."))
  (if largoLib
    (princ (strcat "\n  - Libreria: " (lj-cm largoLib) " x " (lj-cm *lj-lib-fondo*) " cm, "
                   (itoa nMod) " modulos de " (lj-cm (/ largoLib nMod)) " cm (base con puertas de "
                   (lj-cm *lj-lib-fondo*) " cm y estantes de " (lj-cm *lj-lib-fondo-sup*)
                   " cm, hasta " (lj-cm *lj-lib-alto*) " cm de alto)."))
  )
  (princ (strcat "\n  - Banco corrido en L con arcon: fondo " (lj-cm *lj-banco-fondo*)
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

(defun c:LIBJUEGOS ( / *error* doc p1 p2 sx sy unidad f kw fr anchoZ fondoZ lay fallos)

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
  (princ)
)

(princ "\n[LIBJUEGOS] Cargado. Escribe LIBJUEGOS para dibujar la zona de libreria y juegos.")
(princ)
