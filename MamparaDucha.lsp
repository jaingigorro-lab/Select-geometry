(vl-load-com)

;; ==========================================================
;; MAMPARA - Mampara de ducha en planta, a escala real.
;;
;; Dibuja una mampara FRONTAL de ducha vista desde arriba, ajustada a
;; la apertura entre dos paredes (por defecto 1.59 m), y la inserta
;; como UN SOLO BLOQUE -para poder moverla, borrarla o contarla de una
;; vez-. El bloque se crea una unica vez por cada combinacion de tipo +
;; longitud (MAMPARA_CORR_L1590, MAMPARA_ABAT_L1590...) y se reutiliza
;; si ya existe en el dibujo. Todas las medidas estan en metros dentro
;; de este archivo y se escalan a las unidades del dibujo.
;;
;;   Tipos:
;;     Corredera - 2 hojas de vidrio de 8 mm en carril doble: una FIJA
;;                 (en la via exterior, junto a la habitacion) y una
;;                 CORREDERA (en la via interior), solapadas 5 cm en el
;;                 centro, con perfiles de pared en los dos extremos y
;;                 un tirador en la hoja corredera. Es la opcion por
;;                 defecto, y la que no invade el bano al abrirse.
;;     Abatible  - un panel fijo + una puerta de 0.90 m de vidrio que
;;                 abre hacia FUERA de la ducha (90 grados), con su arco
;;                 de apertura. La bisagra queda en el lado del
;;                 SEGUNDO extremo (el de la direccion que se indica).
;;
;;   Uso:
;;     1. Ejecutar MAMPARA y elegir el tipo (Intro = Corredera). La
;;        primera vez pregunta las unidades del dibujo (m/cm/mm); se
;;        puede cambiar luego con la opcion Unidades.
;;     2. Longitud de la apertura: Intro para los 1.59 m por defecto,
;;        escribir otro valor, o pulsar dos puntos para medirla.
;;     3. Pulsar el primer extremo de la apertura (la cara de una de
;;        las dos paredes, en el lado abierto de la ducha).
;;     4. Pulsar un punto en la direccion del otro extremo (solo marca
;;        la direccion; la longitud ya se ha fijado en el paso 2).
;;     5. Pulsar un punto cualquiera DENTRO de la ducha (indica de que
;;        lado queda el interior).
;;   La cara exterior del perfil queda a ras de la linea de apertura,
;;   y la mampara se construye hacia el interior de la ducha.
;; ==========================================================

;; --- Parametros (en METROS) ---

;; Longitud por defecto de la apertura (la ultima usada pasa a ser el
;; nuevo valor por defecto durante la sesion).
(setq *mampara-length-m* 1.59)

(setq *mampara-glass-t* 0.008)     ; espesor del vidrio
(setq *mampara-rail-w* 0.028)      ; ancho del carril / perfiles de pared
(setq *mampara-wall-prof* 0.020)   ; ancho de cada perfil de pared (a lo largo)
(setq *mampara-track-pitch* 0.012) ; separacion entre las dos vias del carril
(setq *mampara-overlap* 0.050)     ; solape de las hojas en el centro
(setq *mampara-door-max* 0.90)     ; hoja maxima de la puerta abatible
(setq *mampara-door-gap* 0.006)    ; holgura panel fijo - puerta abatible
(setq *mampara-min-len* 0.50)      ; longitud minima admitida
(setq *mampara-max-len* 4.00)      ; longitud maxima admitida (anti-typos de unidades)

;; Capas (se crean si no existen).
(setq *mampara-layer-prof*  "MAMPARA")           ; perfiles y tirador
(setq *mampara-layer-glass* "MAMPARA_VIDRIO")    ; vidrios
(setq *mampara-layer-open*  "MAMPARA_APERTURA")  ; arco y hoja abierta

;; Unidades del dibujo elegidas ("m", "cm" o "mm"); se preguntan una vez.
(setq *mampara-unit* nil)

;; --- Utilidades ---

;; Unidades del dibujo por metro, segun *mampara-unit*.
(defun mampara-scale ()
  (cond
    ((= *mampara-unit* "mm") 1000.0)
    ((= *mampara-unit* "cm") 100.0)
    (T 1.0)
  )
)

;; Pregunta las unidades en las que esta dibujado el plano, ofreciendo
;; como valor por defecto lo que diga INSUNITS (o la ultima respuesta).
;; Se pregunta -en vez de fiarse solo de INSUNITS- porque las plantillas
;; suelen dejar INSUNITS en milimetros aunque se dibuje en metros.
(defun mampara-ask-units ( / u def kw)
  (setq u (getvar "INSUNITS"))
  (setq def
    (cond
      (*mampara-unit* *mampara-unit*)
      ((= u 4) "mm")
      ((= u 5) "cm")
      (T "m")
    )
  )
  (initget "m cm mm")
  (setq kw (getkword (strcat "\n[MAMPARA] Unidades del dibujo [m/cm/mm] <" def ">: ")))
  (setq *mampara-unit* (if kw (strcase kw T) def))
  (mampara-scale)
)

;; Angulo (en radianes) de a hacia b, en el plano XY de las coordenadas
;; que se le pasen (a diferencia de ANGLE, no depende del UCS actual).
(defun mampara-heading (a b)
  (atan (- (cadr b) (cadr a)) (- (car b) (car a)))
)

;; Componente Z de v1 x v2 en 2D: su signo dice a que lado de v1 cae v2
;; (positivo = izquierda, negativo = derecha).
(defun mampara-cross (v1 v2)
  (- (* (car v1) (cadr v2)) (* (cadr v1) (car v2)))
)

;; Crea la capa "name" con el color ACI dado si todavia no existe.
(defun mampara-ensure-layer (name color)
  (if (not (tblsearch "LAYER" name))
    (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLayerTableRecord")
                   (cons 2 name) '(70 . 0) (cons 62 color) '(6 . "Continuous")))
  )
  name
)

;; True si el bloque "name" existe Y tiene al menos una entidad dentro
;; (una definicion vacia, resto de un intento fallido, no cuenta).
(defun mampara-block-has-content (name / e)
  (setq e (tblobjname "BLOCK" name))
  (if e
    (progn
      (setq e (entnext e))
      (and e (/= (cdr (assoc 0 (entget e))) "ENDBLK"))
    )
    nil
  )
)

;; Nombre del bloque: tipo + longitud en milimetros.
(defun mampara-block-name (tipo len k)
  (strcat "MAMPARA_" (if (= tipo "Abatible") "ABAT" "CORR")
          "_L" (itoa (fix (+ 0.5 (* 1000.0 (/ len k))))))
)

;; --- Definiciones de entidades (listas DXF, en el sistema LOCAL del bloque) ---
;;
;; Sistema local: origen en el primer extremo de la apertura, +X hacia
;; el segundo extremo, +Y hacia el INTERIOR de la ducha (si el interior
;; cae al otro lado, se espeja el bloque al insertarlo, YScale = -1).
;; y = 0 es la linea de apertura, y negativo es "hacia fuera".

(defun mampara-def-rect (x0 y0 x1 y1 layer)
  (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 layer)
        '(100 . "AcDbPolyline") '(90 . 4) '(70 . 1)
        (cons 10 (list x0 y0)) (cons 10 (list x1 y0))
        (cons 10 (list x1 y1)) (cons 10 (list x0 y1)))
)

(defun mampara-def-line (x0 y0 x1 y1 layer)
  (list '(0 . "LINE") (cons 8 layer)
        (cons 10 (list x0 y0 0.0)) (cons 11 (list x1 y1 0.0)))
)

(defun mampara-def-arc (cx cy r a0 a1 layer)
  (list '(0 . "ARC") (cons 8 layer) (cons 10 (list cx cy 0.0))
        (cons 40 r) (cons 50 a0) (cons 51 a1))
)

;; Corredera de 2 hojas: carril, perfiles de pared, hoja fija (via
;; exterior), hoja corredera (via interior) y tirador. "len" y "k" en
;; unidades de dibujo / unidades por metro.
(defun mampara-defs-corredera (len k / gt hg rw wp ov yA yB mid sx0 lp lg)
  (setq lp *mampara-layer-prof* lg *mampara-layer-glass*)
  (setq gt (* k *mampara-glass-t*))
  (setq hg (/ gt 2.0))
  (setq rw (* k *mampara-rail-w*))
  (setq wp (* k *mampara-wall-prof*))
  (setq ov (* k *mampara-overlap*))
  (setq yA (- (/ rw 2.0) (/ (* k *mampara-track-pitch*) 2.0)))   ; via exterior (fija)
  (setq yB (+ (/ rw 2.0) (/ (* k *mampara-track-pitch*) 2.0)))   ; via interior (corredera)
  (setq mid (/ len 2.0))
  (setq sx0 (- mid (/ ov 2.0)))                                  ; extremo libre de la corredera
  (list
    (mampara-def-rect 0.0 0.0 len rw lp)
    (mampara-def-line wp 0.0 wp rw lp)
    (mampara-def-line (- len wp) 0.0 (- len wp) rw lp)
    (mampara-def-rect wp (- yA hg) (+ mid (/ ov 2.0)) (+ yA hg) lg)
    (mampara-def-rect sx0 (- yB hg) (- len wp) (+ yB hg) lg)
    (mampara-def-rect (+ sx0 (* k 0.03)) (+ yB hg) (+ sx0 (* k 0.18)) (+ yB hg (* k 0.006)) lp)
  )
)

;; Abatible: perfiles de pared, panel fijo, puerta cerrada junto a la
;; bisagra (extremo +X) y, en la capa de apertura, la puerta abierta a
;; 90 grados hacia fuera (-Y) con su arco de giro.
(defun mampara-defs-abatible (len k / gt hg rw wp yg doorW gap pivX lp lg lo)
  (setq lp *mampara-layer-prof* lg *mampara-layer-glass* lo *mampara-layer-open*)
  (setq gt (* k *mampara-glass-t*))
  (setq hg (/ gt 2.0))
  (setq rw (* k *mampara-rail-w*))
  (setq wp (* k *mampara-wall-prof*))
  (setq gap (* k *mampara-door-gap*))
  (setq yg (/ rw 2.0))
  (setq doorW (min (* k *mampara-door-max*) (* 0.6 len)))
  (setq pivX (- len wp))
  (list
    (mampara-def-rect 0.0 0.0 wp rw lp)
    (mampara-def-rect (- len wp) 0.0 len rw lp)
    (mampara-def-rect wp (- yg hg) (- pivX doorW gap) (+ yg hg) lg)
    (mampara-def-rect (- pivX doorW) (- yg hg) pivX (+ yg hg) lg)
    (mampara-def-rect (- pivX gt) (- yg doorW) pivX yg lo)
    (mampara-def-arc pivX yg doorW pi (* 1.5 pi) lo)
  )
)

;; --- Creacion del bloque ---

;; Crea la definicion de bloque "name" directamente con ENTMAKE
;; (BLOCK ... ENDBLK), sin pasar por el comando -BLOCK: asi no depende
;; de referencias a objetos, del UCS, ni de las preguntas de
;; redefinicion. Devuelve "name" si ha quedado creado, o nil.
(defun mampara-make-block (name defs / ok d)
  (if (entmake (list '(0 . "BLOCK") (cons 2 name) '(70 . 0) '(10 0.0 0.0 0.0)))
    (progn
      (setq ok T)
      (foreach d defs
        (if (not (entmake d)) (setq ok nil))
      )
      ;; ENDBLK se emite SIEMPRE una vez abierto el bloque, o el dibujo
      ;; se quedaria con una definicion a medias.
      (entmake (list '(0 . "ENDBLK")))
      (if (and ok (mampara-block-has-content name))
        name
        (progn
          (princ (strcat "\n[MAMPARA] Aviso: el bloque \"" name "\" ha quedado incompleto."))
          nil
        )
      )
    )
    (progn
      (princ (strcat "\n[MAMPARA] Aviso: no se ha podido crear el bloque \"" name
                     "\" (si ya existe vacio, usa PURGE y repite)."))
      nil
    )
  )
)

;; Devuelve el nombre del bloque (creandolo si hace falta) o nil.
(defun mampara-ensure-block (tipo len k / name defs)
  (setq name (mampara-block-name tipo len k))
  (if (mampara-block-has-content name)
    name
    (progn
      (mampara-ensure-layer *mampara-layer-prof* 7)
      (mampara-ensure-layer *mampara-layer-glass* 4)
      (if (= tipo "Abatible") (mampara-ensure-layer *mampara-layer-open* 8))
      (setq defs
        (if (= tipo "Abatible")
          (mampara-defs-abatible len k)
          (mampara-defs-corredera len k)
        )
      )
      (mampara-make-block name defs)
    )
  )
)

;; Inserta el bloque en insPt (WCS), girado rotAng, espejado si
;; ySign = -1. vla-InsertBlock exige el punto como VARIANTE.
(defun mampara-insert (blkName insPt rotAng ySign / doc ms obj)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq ms (vla-get-ModelSpace doc))
  (setq obj (vl-catch-all-apply 'vla-InsertBlock
              (list ms (vlax-3d-point insPt) blkName 1.0 ySign 1.0 rotAng)))
  (if (vl-catch-all-error-p obj)
    (progn
      (princ (strcat "\n[MAMPARA] Aviso: fallo al insertar el bloque ("
                     (vl-catch-all-error-message obj) ")."))
      nil
    )
    (progn
      (vl-catch-all-apply 'vla-put-Layer (list obj *mampara-layer-prof*))
      obj
    )
  )
)

;; --- Comando ---

(defun c:MAMPARA
  ( / k tipo kw defLen len lenM p1 p2 p3 p1w p2w p3w ang side blkName)

  (if (not *mampara-unit*) (mampara-ask-units))
  (setq k (mampara-scale))

  ;; Tipo (con opcion de volver a elegir unidades).
  (while (not tipo)
    (initget "Corredera Abatible Unidades")
    (setq kw (getkword "\n[MAMPARA] Tipo [Corredera/Abatible/Unidades] <Corredera>: "))
    (cond
      ((= kw "Unidades") (setq k (mampara-ask-units)))
      ((not kw) (setq tipo "Corredera"))
      (T (setq tipo kw))
    )
  )

  ;; Longitud: Intro = la ultima usada (1.59 m al principio), o valor
  ;; escrito, o dos puntos (getdist mide).
  (setq defLen (* *mampara-length-m* k))
  (initget 6)
  (setq len (getdist (strcat "\n[MAMPARA] Longitud de la apertura (valor, o pulsa dos puntos) <"
                             (rtos defLen 2 2) ">: ")))
  (if (not len) (setq len defLen))
  (setq lenM (/ len k))

  (cond
    ((or (< lenM *mampara-min-len*) (> lenM *mampara-max-len*))
      (princ (strcat "\n[MAMPARA] Longitud de " (rtos lenM 2 3) " m fuera de rango ("
                     (rtos *mampara-min-len* 2 2) " a " (rtos *mampara-max-len* 2 2)
                     " m). Revisa las unidades con la opcion Unidades."))
    )
    (T
      (setq p1 (getpoint "\n[MAMPARA] Primer extremo de la apertura (cara de una pared): "))
      (if p1 (setq p2 (getpoint p1 "\n[MAMPARA] Punto en la direccion del otro extremo: ")))
      (if p2 (setq p3 (getpoint "\n[MAMPARA] Punto DENTRO de la ducha (indica el lado interior): ")))
      (cond
        ((not (and p1 p2 p3))
          (princ "\n[MAMPARA] Cancelado.")
        )
        (T
          ;; Todo a WCS, que es lo que esperan entmake / InsertBlock.
          (setq p1w (trans p1 1 0))
          (setq p2w (trans p2 1 0))
          (setq p3w (trans p3 1 0))
          (setq side
            (mampara-cross (list (- (car p2w) (car p1w)) (- (cadr p2w) (cadr p1w)))
                           (list (- (car p3w) (car p1w)) (- (cadr p3w) (cadr p1w)))))
          (cond
            ((< (distance p1w p2w) 1e-9)
              (princ "\n[MAMPARA] Los dos primeros puntos coinciden: no hay direccion. Cancelado.")
            )
            ((< (abs side) 1e-9)
              (princ "\n[MAMPARA] El punto interior esta sobre la linea de la apertura. Cancelado.")
            )
            (T
              (setq ang (mampara-heading p1w p2w))
              (setq blkName (mampara-ensure-block tipo len k))
              (if blkName
                (if (mampara-insert blkName (list (car p1w) (cadr p1w) (if (caddr p1w) (caddr p1w) 0.0))
                                    ang (if (> side 0.0) 1.0 -1.0))
                  (progn
                    (setq *mampara-length-m* lenM)
                    (princ (strcat "\n[MAMPARA] Mampara " (strcase tipo T) " de "
                                   (rtos lenM 2 3) " m creada (bloque " blkName ")."))
                  )
                )
                (princ "\n[MAMPARA] No se ha creado la mampara.")
              )
            )
          )
        )
      )
    )
  )
  (princ)
)

(princ "\n[MAMPARA] Cargado. Escribe MAMPARA para dibujar una mampara de ducha (1.59 m por defecto).")
(princ)
