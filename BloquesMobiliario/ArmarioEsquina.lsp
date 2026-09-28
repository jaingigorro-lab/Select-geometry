;;; ===========================================================================
;;; ArmarioEsquina.lsp
;;;
;;; Armario empotrado en esquina de 90 grados, en planta y con detalle:
;;;  - casco: traseras de 10 mm, costados y divisiones de 16 mm;
;;;  - frente: tapajuntas 70x10, premarco 70x35 y cerco 70x30 en cada extremo,
;;;    poste de rincon y regletas de 50 mm para que las puertas no choquen;
;;;  - puertas batientes con su barrido, o correderas en dos guias con flechas;
;;;  - barra de colgar en L en el rincon y barras rectas en el resto, con
;;;    perchas.
;;;
;;; Unidades: metros. Si el dibujo tiene INSUNITS en centimetros o
;;; milimetros, el armario se dibuja a esa escala automaticamente.
;;;
;;; Comandos:
;;;   ARMESQ     Crea un armario. Pide la esquina interior de las paredes, el
;;;              final del armario en cada pared (se puede teclear el largo
;;;              con la direccion del cursor), el fondo y el tipo de puertas.
;;;              Si la segunda pared queda a la derecha, el armario sale
;;;              simetrico.
;;;   ARMESQMOD  Cambia el largo de cada lado, el fondo o las puertas de un
;;;              armario ya insertado y lo redibuja con todos sus detalles.
;;;
;;; Cada combinacion de medidas es un bloque (p. ej. ARMESQ_B_2.00x1.60x0.60,
;;; B = batientes, C = correderas). Las medidas se guardan en la insercion
;;; (XDATA "ARMESQ") para poder modificarlas despues.
;;;
;;; Geometria del bloque: punto base en el rincon de las paredes; la primera
;;; pared va por el eje X y la segunda por el eje Y; la habitacion queda en
;;; el cuadrante positivo, delante de los frentes (x > fondo, y > fondo).
;;; ===========================================================================

(setq *ae-app*   "ARMESQ"
      *ae-k*     1.0            ; metros -> unidades del dibujo
      *ae-fondo* 0.60
      *ae-tipo*  "Batientes")

;;; ---------------------------------------------------------------------------
;;; Primitivas: capa 0 y color PorCapa. Reciben metros.
;;; ---------------------------------------------------------------------------

(defun ae:p (x y) (list (* x *ae-k*) (* y *ae-k*) 0.0))

(defun ae:linea (x1 y1 x2 y2)
  (entmake (list '(0 . "LINE") '(8 . "0")
                 (cons 10 (ae:p x1 y1)) (cons 11 (ae:p x2 y2)))))

(defun ae:grados->rad (a)
  (while (< a 0.0) (setq a (+ a 360.0)))
  (while (>= a 360.0) (setq a (- a 360.0)))
  (/ (* a pi) 180.0))

;; Arco antihorario de a1 a a2 (grados)
(defun ae:arco (cx cy r a1 a2)
  (entmake (list '(0 . "ARC") '(8 . "0") (cons 10 (ae:p cx cy))
                 (cons 40 (* r *ae-k*))
                 (cons 50 (ae:grados->rad a1)) (cons 51 (ae:grados->rad a2)))))

;; pts: lista de (x y) o (x y bulge)
(defun ae:polilinea (pts cerrada / d)
  (setq d (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") '(8 . "0")
                '(100 . "AcDbPolyline") (cons 90 (length pts))
                (cons 70 (if cerrada 1 0))))
  (foreach p pts
    (setq d (append d
                    (list (cons 10 (list (* (car p) *ae-k*) (* (cadr p) *ae-k*)))
                          (cons 42 (if (caddr p) (caddr p) 0.0))))))
  (entmake d))

(defun ae:rect (x1 y1 x2 y2)
  (ae:polilinea (list (list x1 y1) (list x2 y1) (list x2 y2) (list x1 y2)) T))

;;; ---------------------------------------------------------------------------
;;; Coordenadas de cada lado: u a lo largo de la pared (desde el rincon) y v
;;; desde la pared hacia la habitacion. Lado 1 = primera pared (eje X),
;;; lado 2 = segunda pared (eje Y): es el simetrico respecto a la diagonal.
;;; ---------------------------------------------------------------------------

(defun ae:xy (lado u v) (if (= lado 1) (list u v) (list v u)))

(defun ae:l (lado u1 v1 u2 v2 / a b)
  (setq a (ae:xy lado u1 v1)
        b (ae:xy lado u2 v2))
  (ae:linea (car a) (cadr a) (car b) (cadr b)))

(defun ae:r (lado u1 v1 u2 v2 / a b)
  (setq a (ae:xy lado u1 v1)
        b (ae:xy lado u2 v2))
  (ae:rect (min (car a) (car b)) (min (cadr a) (cadr b))
           (max (car a) (car b)) (max (cadr a) (cadr b))))

;; Arco en coordenadas del lado (la simetria invierte el sentido)
(defun ae:a (lado cu cv r a1 a2 / c)
  (setq c (ae:xy lado cu cv))
  (if (= lado 1)
    (ae:arco (car c) (cadr c) r a1 a2)
    (ae:arco (car c) (cadr c) r (- 90.0 a2) (- 90.0 a1))))

;; Flecha doble de puerta corredera, a lo largo de u
(defun ae:flecha (lado u1 u2 v / h)
  (setq h 0.035)
  (ae:l lado u1 v u2 v)
  (ae:l lado u1 v (+ u1 h) (+ v (/ h 2.0)))
  (ae:l lado u1 v (+ u1 h) (- v (/ h 2.0)))
  (ae:l lado u2 v (- u2 h) (+ v (/ h 2.0)))
  (ae:l lado u2 v (- u2 h) (- v (/ h 2.0))))

;; Barra recta de colgar entre u0 y u1, a la distancia vb de la pared, con
;; perchas de 2*h de ancho cada 8,5 cm
(defun ae:barra (lado u0 u1 vb h / u)
  (ae:l lado (+ u0 0.01) vb (- u1 0.01) vb)
  (setq u (+ u0 0.055))
  (while (<= u (- u1 0.045))
    (ae:l lado (- u 0.012) (- vb h) (+ u 0.012) (+ vb h))
    (setq u (+ u 0.085))))

;;; ---------------------------------------------------------------------------
;;; Un lado del armario (lado 1 o 2), de largo "largo" medido desde el rincon
;;; y fondo "fo". Devuelve la u donde termina el modulo de rincon.
;;; ---------------------------------------------------------------------------

(defun ae:lado (lado largo fo tipo / us ue ap n w i a divs vt bis k u1 m0 vb h)
  ;; Frente en el extremo: premarco, cerco y tapajuntas
  (ae:r lado (- largo 0.035) (- fo 0.07) largo fo)
  (ae:r lado (- largo 0.065) (- fo 0.07) (- largo 0.035) fo)
  (ae:r lado (- largo 0.05) fo (+ largo 0.02) (+ fo 0.01))
  ;; Casco: costado del extremo y trasera (la del lado 2 cubre el rincon)
  (ae:r lado (- largo 0.016) 0.01 largo (- fo 0.08))
  (ae:r lado (if (= lado 1) 0.01 0.0) 0.0 (- largo 0.016) 0.01)
  ;; Regleta de rincon
  (ae:r lado fo (- fo 0.019) (+ fo 0.05) fo)
  ;; Puertas, entre la regleta y el cerco
  (setq us (+ fo 0.052)
        ue (- largo 0.067)
        ap (- ue us)
        divs nil)
  (if (= tipo "Correderas")
    (progn
      ;; hojas de 1 m como maximo, en dos guias, solapadas 4 cm
      (setq n (max 2 (fix (+ 0.999999 ap)))
            w (/ (+ ap (* (1- n) 0.04)) n)
            i 0)
      (repeat n
        (setq a (+ us (* i (- w 0.04))))
        (if (= (rem i 2) 0)
          (ae:r lado a (- fo 0.042) (+ a w) (- fo 0.023))
          (ae:r lado a (- fo 0.019) (+ a w) fo))
        (ae:flecha lado (+ a (* w 0.3)) (+ a (* w 0.7)) (+ fo 0.08))
        (setq i (1+ i)))
      (setq i 1)
      (repeat (1- n)
        (setq divs (append divs (list (+ us (/ (* i ap) n))))
              i (1+ i)))
      (setq vt (- fo 0.045)))
    (progn
      ;; hojas de 60 cm como maximo. La del rincon abre desde el lado
      ;; contrario al rincon (asi no choca con el otro frente); el resto va
      ;; por parejas y, si sobra una, abre desde el extremo.
      (setq n (max 1 (fix (+ 0.999999 (/ ap 0.6))))
            w (/ (- ap (* (1- n) 0.003)) n)
            bis '("F")
            i 1)
      (while (< i n)
        (if (< (1+ i) n)
          (setq bis (append bis '("R" "F")) i (+ i 2))
          (setq bis (append bis '("F")) i (1+ i))))
      (setq i 0)
      (foreach b bis
        (setq a (+ us (* i (+ w 0.003))))
        (ae:r lado a (- fo 0.019) (+ a w) fo)
        (if (= b "F")
          (ae:a lado (+ a w) fo w 90.0 180.0)
          (ae:a lado a fo w 0.0 90.0))
        (setq i (1+ i)))
      ;; una division tras la hoja del rincon y tras cada pareja
      (setq i 1)
      (while (< i n)
        (setq divs (append divs (list (+ us (* i w) (* (- i 0.5) 0.003))))
              i (+ i 2)))
      (setq vt (- fo 0.022))))
  ;; Divisiones de 16 mm
  (foreach u divs
    (ae:r lado (- u 0.008) 0.01 (+ u 0.008) vt))
  ;; Barras rectas en los modulos que no son el del rincon
  (setq vb (- (/ fo 2.0) 0.005)
        h (min 0.205 (/ (- fo 0.09) 2.0))
        k divs)
  (while k
    (setq m0 (+ (car k) 0.008)
          u1 (if (cdr k) (- (cadr k) 0.008) (- largo 0.016)))
    (ae:barra lado m0 u1 vb h)
    (setq k (cdr k)))
  (if divs (- (car divs) 0.008) (- largo 0.016)))

;;; ---------------------------------------------------------------------------
;;; Rincon: poste, barra de colgar en L (curva de 15 cm de radio) y perchas
;;; que giran con ella. ua/ub: final del modulo de rincon en cada lado.
;;; ---------------------------------------------------------------------------

(defun ae:rincon (fo ua ub / vb h r c0 x y ang c s px py)
  (ae:rect (- fo 0.05) (- fo 0.05) fo fo)
  (setq vb (- (/ fo 2.0) 0.005)
        h (min 0.205 (/ (- fo 0.09) 2.0))
        r 0.15
        c0 (+ vb r))
  (ae:polilinea (list (list (- ua 0.01) vb)
                      (list (+ vb r) vb -0.414213562373)
                      (list vb (+ vb r))
                      (list vb (- ub 0.01)))
                nil)
  (setq x (+ vb r 0.06))
  (while (<= x (- ua 0.045))
    (ae:linea (- x 0.012) (- vb h) (+ x 0.012) (+ vb h))
    (setq x (+ x 0.085)))
  (setq y (+ vb r 0.06))
  (while (<= y (- ub 0.045))
    (ae:linea (- vb h) (- y 0.012) (+ vb h) (+ y 0.012))
    (setq y (+ y 0.085)))
  (foreach ang '(247.5 225.0 202.5)
    (setq c (cos (/ (* ang pi) 180.0))
          s (sin (/ (* ang pi) 180.0))
          px (+ c0 (* r c))
          py (+ c0 (* r s)))
    (ae:linea (- px (* h c)) (- py (* h s)) (+ px (* h c)) (+ py (* h s)))))

(defun ae:dibujar (la lb fo tipo / ua ub)
  (setq ua (ae:lado 1 la fo tipo)
        ub (ae:lado 2 lb fo tipo))
  (ae:rincon fo ua ub))

;;; ---------------------------------------------------------------------------
;;; Bloque, insercion y datos
;;; ---------------------------------------------------------------------------

(defun ae:factor ( / u)
  (setq u (getvar "INSUNITS"))
  (cond ((= u 4) 1000.0)     ; milimetros
        ((= u 5) 100.0)      ; centimetros
        (T 1.0)))            ; metros o sin unidades

(defun ae:nombre (la lb fo tipo)
  (strcat "ARMESQ_" (if (= tipo "Correderas") "C_" "B_")
          (rtos la 2 2) "x" (rtos lb 2 2) "x" (rtos fo 2 2)
          (cond ((= *ae-k* 100.0) "_cm") ((= *ae-k* 1000.0) "_mm") (T ""))))

;; Crea la definicion si no existe. Devuelve el nombre, o nil si falla.
(defun ae:bloque (la lb fo tipo / nombre)
  (setq nombre (ae:nombre la lb fo tipo))
  (if (not (tblsearch "BLOCK" nombre))
    (progn
      (entmake (list '(0 . "BLOCK") (cons 2 nombre) '(70 . 0) '(10 0.0 0.0 0.0)))
      (ae:dibujar la lb fo tipo)
      (if (not (entmake '((0 . "ENDBLK"))))
        (setq nombre nil))))
  nombre)

(defun ae:valido (la lb fo / minimo)
  (setq minimo (+ fo 0.42))
  (cond
    ((or (< fo 0.35) (> fo 1.2))
     (princ "\n[ARMESQ] El fondo debe estar entre 0.35 y 1.20 m.")
     nil)
    ((or (< la minimo) (< lb minimo))
     (princ (strcat "\n[ARMESQ] Con ese fondo, cada lado necesita al menos "
                    (rtos minimo 2 2) " m."))
     nil)
    (T T)))

(defun ae:xdata (la lb fo tipo)
  (list -3 (list *ae-app* (cons 1040 la) (cons 1040 lb) (cons 1040 fo)
                 (cons 1000 tipo))))

(defun ae:insertar (p0 ang sy la lb fo tipo / nombre)
  (setq nombre (ae:bloque la lb fo tipo))
  (cond
    ((not nombre)
     (princ "\n[ARMESQ] No se ha podido crear el bloque."))
    (T
     (if (not (tblsearch "APPID" *ae-app*)) (regapp *ae-app*))
     (if (entmake (list '(0 . "INSERT") (cons 2 nombre) (cons 10 p0)
                        '(41 . 1.0) (cons 42 sy) '(43 . 1.0) (cons 50 ang)
                        (ae:xdata la lb fo tipo)))
       (princ (strcat "\n[ARMESQ] Insertado " nombre
                      ". Para cambiar sus medidas: ARMESQMOD."))
       (princ "\n[ARMESQ] No se ha podido insertar el bloque.")))))

(defun ae:pedir (msg v / r)
  (setq r (getdist (strcat "\n" msg " <" (rtos (* v *ae-k*) 2 2) ">: ")))
  (if r (/ r *ae-k*) v))

;;; ---------------------------------------------------------------------------
;;; Comandos
;;; ---------------------------------------------------------------------------

(defun c:ARMESQ ( / p0 p1 p2 ang d la lb fo tipo)
  (setq *ae-k* (ae:factor))
  (setq p0 (getpoint "\nEsquina interior de las paredes: "))
  (if p0
    (setq p1 (getpoint p0 "\nFinal del armario en la primera pared (o teclea el largo): ")))
  (if p1
    (setq p2 (getpoint p0 "\nFinal del armario en la segunda pared (o teclea el largo): ")))
  (if p2
    (progn
      (setq p0 (trans p0 1 0)
            p1 (trans p1 1 0)
            p2 (trans p2 1 0)
            ang (angle p0 p1)
            la (/ (distance p0 p1) *ae-k*)
            ;; distancia de p2 a la primera pared, con signo (+ = a la izquierda)
            d (/ (+ (* (- (car p2) (car p0)) (- (sin ang)))
                    (* (- (cadr p2) (cadr p0)) (cos ang)))
                 *ae-k*)
            lb (abs d))
      (setq fo (getdist (strcat "\nFondo del armario <"
                                (rtos (* *ae-fondo* *ae-k*) 2 2) ">: ")))
      (setq fo (if fo (/ fo *ae-k*) *ae-fondo*))
      (initget "Batientes Correderas")
      (setq tipo (getkword (strcat "\nPuertas [Batientes/Correderas] <" *ae-tipo* ">: ")))
      (if (not tipo) (setq tipo *ae-tipo*))
      (if (ae:valido la lb fo)
        (progn
          (setq *ae-fondo* fo
                *ae-tipo* tipo)
          (ae:insertar p0 ang (if (< d 0.0) -1.0 1.0) la lb fo tipo)))))
  (princ))

(defun c:ARMESQMOD ( / sel en ed xd v la lb fo tipo nt nombre)
  (setq *ae-k* (ae:factor))
  (setq sel (entsel "\nSelecciona el armario de esquina: "))
  (if sel
    (progn
      (setq en (car sel)
            ed (entget en (list *ae-app*))
            xd (cdr (assoc -3 ed)))
      (if (and (= (cdr (assoc 0 ed)) "INSERT") xd)
        (progn
          (setq v (cdr (car xd))
                la (cdr (nth 0 v))
                lb (cdr (nth 1 v))
                fo (cdr (nth 2 v))
                tipo (cdr (nth 3 v)))
          (setq la (ae:pedir "Largo en la primera pared" la)
                lb (ae:pedir "Largo en la segunda pared" lb)
                fo (ae:pedir "Fondo" fo))
          (initget "Batientes Correderas")
          (setq nt (getkword (strcat "\nPuertas [Batientes/Correderas] <" tipo ">: ")))
          (if nt (setq tipo nt))
          (if (ae:valido la lb fo)
            (if (setq nombre (ae:bloque la lb fo tipo))
              (progn
                (setq ed (subst (cons 2 nombre) (assoc 2 ed) ed)
                      ed (subst (ae:xdata la lb fo tipo) (assoc -3 ed) ed))
                (entmod ed)
                (entupd en)
                (princ (strcat "\n[ARMESQ] Armario actualizado: " nombre)))
              (princ "\n[ARMESQ] No se ha podido crear el bloque."))))
        (princ "\n[ARMESQ] Ese objeto no es un armario creado con ARMESQ."))))
  (princ))

(princ "\nArmarioEsquina cargado. Comandos: ARMESQ (crear) y ARMESQMOD (modificar).")
(princ)
