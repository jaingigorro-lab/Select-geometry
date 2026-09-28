;;; ===========================================================================
;;; MesaEsquina.lsp
;;;
;;; Mesa de escritorio en L (de esquina) con silla y complementos, en planta:
;;;  - tablero en L con el rincon interior curvo o recto y pasacables;
;;;  - puesto de trabajo en el rincon o en uno de los tramos: pantalla con su
;;;    pie, teclado, raton a la derecha y silla operativa con ruedas;
;;;  - lampara de mesa;
;;;  - cajonera bajo el tablero, en discontinua (dibujada a trazos, asi que se
;;;    ve igual con cualquier escala de tipo de linea).
;;;
;;; Unidades: metros. Si el dibujo tiene INSUNITS en centimetros o
;;; milimetros, la mesa se dibuja a esa escala automaticamente.
;;;
;;; Comandos:
;;;   MESAESQ     Crea la mesa. Pide la esquina exterior de la L, el final de
;;;               cada tramo (se puede teclear el largo con la direccion del
;;;               cursor), el fondo de cada tramo y las opciones.
;;;   MESAESQMOD  Cambia largos, fondos u opciones de una mesa ya insertada y
;;;               la redibuja entera, sin moverla.
;;;
;;; Cada combinacion de medidas y opciones es un bloque (p. ej.
;;; MESAESQ_1.70x1.60_0.60x0.60_CES). Las medidas se guardan en la insercion
;;; (XDATA "MESAESQ") para poder modificarlas despues.
;;;
;;; Geometria del bloque: punto base en la esquina exterior de la L; un tramo
;;; va por el eje X y el otro por el eje Y; el usuario se sienta en el
;;; cuadrante positivo, delante de los frentes. Si el segundo tramo queda a
;;; la derecha del primero, el comando intercambia los tramos para que el
;;; bloque no salga en simetria (asi el raton sigue a la derecha).
;;; ===========================================================================

(setq *md-app*    "MESAESQ"
      *md-k*      1.0          ; metros -> unidades del dibujo
      *md-f1*     0.60
      *md-f2*     0.60
      *md-puesto* "Esquina"
      *md-rincon* "Curvo"
      *md-silla*  "Si"
      *md-o*      '(0.0 0.0)   ; origen y giro del dibujo en curso
      *md-a*      0.0)

;; Silla operativa vista en planta (metros, centro del asiento en 0,0,
;; mirando hacia +Y). "P" polilinea (cerrada, vertices x y bulge),
;; "L" linea, "A" arco en grados, "C" circulo.
(setq *md-silla-geo*
 '(("P" 1 (-0.2 -0.19 0.0) (0.2 -0.19 0.4142) (0.24 -0.15 0.0) (0.24 0.195 0.4142)
       (0.165 0.27 0.0) (-0.165 0.27 0.4142) (-0.24 0.195 0.0) (-0.24 -0.15 0.4142))
   ("P" 1 (-0.23 -0.2 0.2174) (0.23 -0.2 0.0) (0.23 -0.25 -0.2174) (-0.23 -0.25 0.0))
   ("P" 1 (-0.261 -0.11 0.4142) (-0.247 -0.096 0.0) (-0.247 0.136 0.4142)
       (-0.261 0.15 0.4142) (-0.275 0.136 0.0) (-0.275 -0.096 0.4142))
   ("P" 1 (0.261 -0.11 0.4142) (0.275 -0.096 0.0) (0.275 0.136 0.4142)
       (0.261 0.15 0.4142) (0.247 0.136 0.0) (0.247 -0.096 0.4142))
   ("L" 0.0149 0.27 0.0144 0.3096)
   ("L" -0.0149 0.27 -0.0144 0.3096)
   ("C" 0.0 0.33 0.025)
   ("L" -0.24 0.0938 -0.247 0.0959)
   ("L" -0.275 0.1047 -0.29 0.1094)
   ("L" -0.24 0.0621 -0.247 0.0644)
   ("L" -0.275 0.0739 -0.2989 0.082)
   ("C" -0.3138 0.102 0.025)
   ("L" -0.1568 -0.19 -0.1783 -0.2204)
   ("L" -0.119 -0.19 -0.1485 -0.2297)
   ("A" -0.194 -0.267 0.025 153.45 345.52)
   ("L" 0.119 -0.19 0.1485 -0.2297)
   ("L" 0.1568 -0.19 0.1783 -0.2204)
   ("A" 0.194 -0.267 0.025 194.48 26.55)
   ("L" 0.24 0.0621 0.247 0.0644)
   ("L" 0.275 0.0739 0.2989 0.082)
   ("L" 0.24 0.0938 0.247 0.0959)
   ("L" 0.275 0.1047 0.29 0.1094)
   ("C" 0.3138 0.102 0.025)))

;;; ---------------------------------------------------------------------------
;;; Primitivas: capa 0 y color PorCapa. Reciben metros en el sistema local
;;; definido por *md-o* (origen) y *md-a* (giro en radianes).
;;; ---------------------------------------------------------------------------

(defun md:marco (x y ang) (setq *md-o* (list x y) *md-a* ang))

(defun md:t (x y / c s)
  (setq c (cos *md-a*)
        s (sin *md-a*))
  (list (* (+ (car *md-o*) (- (* x c) (* y s))) *md-k*)
        (* (+ (cadr *md-o*) (* x s) (* y c)) *md-k*)
        0.0))

(defun md:rad (g)
  (while (< g 0.0) (setq g (+ g 360.0)))
  (while (>= g 360.0) (setq g (- g 360.0)))
  (/ (* g pi) 180.0))

(defun md:linea (x1 y1 x2 y2)
  (entmake (list '(0 . "LINE") '(8 . "0") (cons 10 (md:t x1 y1)) (cons 11 (md:t x2 y2)))))

(defun md:arco (cx cy r a1 a2 / g)
  (setq g (/ (* *md-a* 180.0) pi))
  (entmake (list '(0 . "ARC") '(8 . "0") (cons 10 (md:t cx cy)) (cons 40 (* r *md-k*))
                 (cons 50 (md:rad (+ a1 g))) (cons 51 (md:rad (+ a2 g))))))

(defun md:circulo (cx cy r)
  (entmake (list '(0 . "CIRCLE") '(8 . "0") (cons 10 (md:t cx cy)) (cons 40 (* r *md-k*)))))

;; pts: lista de (x y) o (x y bulge)
(defun md:polilinea (pts cerrada / d q)
  (setq d (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") '(8 . "0")
                '(100 . "AcDbPolyline") (cons 90 (length pts))
                (cons 70 (if cerrada 1 0))))
  (foreach p pts
    (setq q (md:t (car p) (cadr p))
          d (append d (list (cons 10 (list (car q) (cadr q)))
                            (cons 42 (if (caddr p) (caddr p) 0.0))))))
  (entmake d))

(defun md:rect (x1 y1 x2 y2)
  (md:polilinea (list (list x1 y1) (list x2 y1) (list x2 y2) (list x1 y2)) T))

(defun md:rrect (x1 y1 x2 y2 r / k)
  (setq k 0.414213562373)
  (md:polilinea (list (list (+ x1 r) y1 0.0) (list (- x2 r) y1 k) (list x2 (+ y1 r) 0.0)
                      (list x2 (- y2 r) k) (list (- x2 r) y2 0.0) (list (+ x1 r) y2 k)
                      (list x1 (- y2 r) 0.0) (list x1 (+ y1 r) k))
                T))

;; Linea discontinua dibujada a trazos de 3 cm con huecos de 2 cm
(defun md:trazos (x1 y1 x2 y2 / l d0 d1 dx dy)
  (setq l (distance (list x1 y1) (list x2 y2))
        dx (- x2 x1)
        dy (- y2 y1)
        d0 0.0)
  (while (< d0 l)
    (setq d1 (min l (+ d0 0.03)))
    (md:linea (+ x1 (* dx (/ d0 l))) (+ y1 (* dy (/ d0 l)))
              (+ x1 (* dx (/ d1 l))) (+ y1 (* dy (/ d1 l))))
    (setq d0 (+ d1 0.02))))

(defun md:rect-trazos (x1 y1 x2 y2)
  (md:trazos x1 y1 x2 y1)
  (md:trazos x2 y1 x2 y2)
  (md:trazos x2 y2 x1 y2)
  (md:trazos x1 y2 x1 y1))

;; Dibuja una lista de datos como *md-silla-geo* en el marco actual
(defun md:datos (lista / e)
  (foreach e lista
    (cond ((= (car e) "L") (md:linea (nth 1 e) (nth 2 e) (nth 3 e) (nth 4 e)))
          ((= (car e) "C") (md:circulo (nth 1 e) (nth 2 e) (nth 3 e)))
          ((= (car e) "A") (md:arco (nth 1 e) (nth 2 e) (nth 3 e) (nth 4 e) (nth 5 e)))
          ((= (car e) "P") (md:polilinea (cddr e) (= (cadr e) 1))))))

;;; ---------------------------------------------------------------------------
;;; Partes de la mesa (en coordenadas del bloque: tramo 1 por X, tramo 2 por Y)
;;; ---------------------------------------------------------------------------

;; Tablero en L con el rincon interior redondeado con radio r (0 = recto)
(defun md:tablero (l1 l2 f1 f2 r)
  (md:marco 0.0 0.0 0.0)
  (md:polilinea
    (append (list (list 0.0 0.0) (list l1 0.0) (list l1 f1))
            (if (> r 0.0)
              (list (list (+ f2 r) f1 -0.414213562373) (list f2 (+ f1 r)))
              (list (list f2 f1)))
            (list (list f2 l2) (list 0.0 l2)))
    T))

;; Puesto de trabajo. (px py) es el punto del borde de la mesa frente al
;; usuario, (ux uy) la direccion hacia el usuario, fondo la profundidad de
;; mesa disponible delante de el y sep la distancia del borde al centro de
;; la silla.
(defun md:puesto (px py ux uy fondo sep silla / dm)
  ;; marco local: +Y hacia el fondo de la mesa, +X a la derecha del usuario
  (md:marco px py (- (atan (- uy) (- ux)) (/ pi 2.0)))
  (setq dm (min 0.55 (- fondo 0.12)))
  (md:rrect -0.22 0.13 0.22 0.27 0.01)           ; teclado
  (md:rect -0.205 0.145 0.205 0.25)
  (md:rrect 0.27 0.15 0.33 0.25 0.028)           ; raton
  (md:rrect -0.27 (- dm 0.015) 0.27 (+ dm 0.015) 0.008)   ; pantalla
  (md:rrect -0.11 (- dm 0.10) 0.11 (- dm 0.035) 0.02)     ; pie
  (md:circulo 0.0 (min (+ dm 0.07) (- fondo 0.05)) 0.03)  ; pasacables
  (md:circulo 0.0 (min (+ dm 0.07) (- fondo 0.05)) 0.02)
  (if (= silla "Si")
    (progn
      (md:marco (+ px (* ux sep)) (+ py (* uy sep)) *md-a*)
      (md:datos *md-silla-geo*))))

;; Lampara de mesa: base en (bx by), brazo hacia el angulo ang (radianes)
(defun md:lampara (bx by ang)
  (md:marco bx by ang)
  (md:circulo 0.0 0.0 0.07)
  (md:circulo 0.0 0.0 0.02)
  (md:linea 0.07 0.008 0.225 0.008)
  (md:linea 0.07 -0.008 0.225 -0.008)
  (md:circulo 0.30 0.0 0.075)
  (md:circulo 0.30 0.0 0.03))

;; Cajonera de 42 cm bajo el final del tramo donde no esta el usuario
;; (discontinua)
(defun md:cajonera (l1 l2 f1 f2 puesto)
  (md:marco 0.0 0.0 0.0)
  (if (= puesto "Segundo")
    (md:rect-trazos (- l1 0.47) 0.03 (- l1 0.05) (+ 0.03 (min 0.55 (- f1 0.06))))
    (md:rect-trazos 0.03 (- l2 0.47) (+ 0.03 (min 0.55 (- f2 0.06))) (- l2 0.05))))

;; Radio del rincon curvo segun el espacio disponible
(defun md:radio (l1 l2 f1 f2 rincon / r)
  (setq r (if (= rincon "Curvo") (min 0.40 (- l1 f2 0.50) (- l2 f1 0.50)) 0.0))
  (if (< r 0.10) 0.0 r))

;; Dibuja la mesa entera (valores en el orden del bloque)
(defun md:dibujar (l1 l2 f1 f2 rincon puesto silla / r d ux uy cx cy b tf)
  (setq r (md:radio l1 l2 f1 f2 rincon))
  (md:tablero l1 l2 f1 f2 r)
  (cond
    ((= puesto "Primero")
     (md:puesto (/ (+ f2 r l1) 2.0) f1 0.0 1.0 f1 0.30 silla))
    ((= puesto "Segundo")
     (md:puesto f2 (/ (+ f1 r l2) 2.0) 1.0 0.0 f2 0.30 silla))
    (T
     ;; en el rincon, mirando hacia la esquina exterior
     (setq d (sqrt (+ (* f1 f1) (* f2 f2)))
           ux (/ f2 d)
           uy (/ f1 d))
     (if (> r 0.0)
       (setq cx (+ f2 r)
             cy (+ f1 r)
             b (+ (* ux cx) (* uy cy))
             tf (- b (sqrt (+ (- (* b b) (* cx cx) (* cy cy)) (* r r)))))
       (setq tf d))
     ;; la silla se separa lo justo para que el asiento no pise el tablero
     (md:puesto (* ux tf) (* uy tf) ux uy tf
                (if (>= r 0.25) (- (+ 0.28 r) (sqrt (- (* r r) 0.0576))) 0.52)
                silla)))
  ;; lampara: en el rincon si el puesto esta en un tramo; si esta en el
  ;; rincon, al final del primer tramo (a la izquierda del usuario)
  (cond
    ((/= puesto "Esquina")
     (md:lampara 0.15 0.15 (/ pi 4.0)))
    ((>= (- l1 f2 r) 0.55)
     (md:lampara (- l1 0.15) 0.13 (/ (* 150.0 pi) 180.0))))
  (md:cajonera l1 l2 f1 f2 puesto))

;;; ---------------------------------------------------------------------------
;;; Bloque, insercion y datos
;;; ---------------------------------------------------------------------------

(defun md:factor ( / u)
  (setq u (getvar "INSUNITS"))
  (cond ((= u 4) 1000.0)     ; milimetros
        ((= u 5) 100.0)      ; centimetros
        (T 1.0)))            ; metros o sin unidades

;; Pasa las medidas del usuario al orden del bloque. giro = 1: igual;
;; giro = -1: se intercambian los tramos (el segundo quedaba a la derecha).
(defun md:orden (l1 l2 f1 f2 puesto giro)
  (if (= giro 1)
    (list l1 l2 f1 f2 puesto)
    (list l2 l1 f2 f1 (cond ((= puesto "Primero") "Segundo")
                            ((= puesto "Segundo") "Primero")
                            (T puesto)))))

(defun md:nombre (v rincon silla)
  (strcat "MESAESQ_" (rtos (nth 0 v) 2 2) "x" (rtos (nth 1 v) 2 2) "_"
          (rtos (nth 2 v) 2 2) "x" (rtos (nth 3 v) 2 2) "_"
          (if (= rincon "Curvo") "C" "R")
          (cond ((= (nth 4 v) "Primero") "1") ((= (nth 4 v) "Segundo") "2") (T "E"))
          (if (= silla "Si") "S" "N")
          (cond ((= *md-k* 100.0) "_cm") ((= *md-k* 1000.0) "_mm") (T ""))))

;; Crea la definicion si no existe. Devuelve el nombre, o nil si falla.
(defun md:bloque (l1 l2 f1 f2 rincon puesto silla giro / v nombre)
  (setq v (md:orden l1 l2 f1 f2 puesto giro)
        nombre (md:nombre v rincon silla))
  (if (not (tblsearch "BLOCK" nombre))
    (progn
      (entmake (list '(0 . "BLOCK") (cons 2 nombre) '(70 . 0) '(10 0.0 0.0 0.0)))
      (md:dibujar (nth 0 v) (nth 1 v) (nth 2 v) (nth 3 v) rincon (nth 4 v) silla)
      (if (not (entmake '((0 . "ENDBLK"))))
        (setq nombre nil))))
  nombre)

(defun md:valido (l1 l2 f1 f2)
  (cond
    ((or (< f1 0.40) (> f1 1.00) (< f2 0.40) (> f2 1.00))
     (princ "\n[MESAESQ] Los fondos deben estar entre 0.40 y 1.00 m.")
     nil)
    ((< l1 (+ f2 0.60))
     (princ (strcat "\n[MESAESQ] El primer tramo necesita al menos "
                    (rtos (+ f2 0.60) 2 2) " m."))
     nil)
    ((< l2 (+ f1 0.60))
     (princ (strcat "\n[MESAESQ] El segundo tramo necesita al menos "
                    (rtos (+ f1 0.60) 2 2) " m."))
     nil)
    (T T)))

(defun md:xdata (l1 l2 f1 f2 rincon puesto silla giro)
  (list -3 (list *md-app* (cons 1040 l1) (cons 1040 l2) (cons 1040 f1) (cons 1040 f2)
                 (cons 1000 rincon) (cons 1000 puesto) (cons 1000 silla)
                 (cons 1070 giro))))

(defun md:pedir (msg v / r)
  (setq r (getdist (strcat "\n" msg " <" (rtos (* v *md-k*) 2 2) ">: ")))
  (if r (/ r *md-k*) v))

;; Pide las opciones; devuelve (rincon puesto silla)
(defun md:opciones (rincon puesto silla / r)
  (initget "Esquina Primero Segundo")
  (if (setq r (getkword (strcat "\nPuesto de trabajo [Esquina/Primero/Segundo] <" puesto ">: ")))
    (setq puesto r))
  (initget "Curvo Recto")
  (if (setq r (getkword (strcat "\nRincon interior [Curvo/Recto] <" rincon ">: ")))
    (setq rincon r))
  (initget "Si No")
  (if (setq r (getkword (strcat "\nSilla [Si/No] <" silla ">: ")))
    (setq silla r))
  (list rincon puesto silla))

;;; ---------------------------------------------------------------------------
;;; Comandos
;;; ---------------------------------------------------------------------------

(defun c:MESAESQ ( / p0 p1 p2 a d l1 l2 f1 f2 op giro nombre)
  (setq *md-k* (md:factor))
  (setq p0 (getpoint "\nEsquina exterior de la mesa: "))
  (if p0
    (setq p1 (getpoint p0 "\nFinal del primer tramo (o teclea el largo): ")))
  (if p1
    (setq p2 (getpoint p0 "\nFinal del segundo tramo (o teclea el largo): ")))
  (if p2
    (progn
      (setq p0 (trans p0 1 0)
            p1 (trans p1 1 0)
            p2 (trans p2 1 0)
            a (angle p0 p1)
            l1 (/ (distance p0 p1) *md-k*)
            ;; distancia de p2 al primer tramo, con signo (+ = a la izquierda)
            d (/ (+ (* (- (car p2) (car p0)) (- (sin a)))
                    (* (- (cadr p2) (cadr p0)) (cos a)))
                 *md-k*)
            l2 (abs d)
            giro (if (< d 0.0) -1 1))
      (setq f1 (md:pedir "Fondo del primer tramo" *md-f1*)
            f2 (md:pedir "Fondo del segundo tramo" *md-f2*)
            op (md:opciones *md-rincon* *md-puesto* *md-silla*))
      (if (md:valido l1 l2 f1 f2)
        (if (setq nombre (md:bloque l1 l2 f1 f2 (nth 0 op) (nth 1 op) (nth 2 op) giro))
          (progn
            (setq *md-f1* f1
                  *md-f2* f2
                  *md-rincon* (nth 0 op)
                  *md-puesto* (nth 1 op)
                  *md-silla* (nth 2 op))
            (if (not (tblsearch "APPID" *md-app*)) (regapp *md-app*))
            (if (entmake (list '(0 . "INSERT") (cons 2 nombre) (cons 10 p0)
                               (cons 50 (if (= giro 1) a (- a (/ pi 2.0))))
                               (md:xdata l1 l2 f1 f2 (nth 0 op) (nth 1 op) (nth 2 op) giro)))
              (princ (strcat "\n[MESAESQ] Insertada " nombre
                             ". Para cambiar sus medidas: MESAESQMOD."))
              (princ "\n[MESAESQ] No se ha podido insertar el bloque.")))
          (princ "\n[MESAESQ] No se ha podido crear el bloque.")))))
  (princ))

(defun c:MESAESQMOD ( / sel en ed xd v l1 l2 f1 f2 op giro nombre)
  (setq *md-k* (md:factor))
  (setq sel (entsel "\nSelecciona la mesa de esquina: "))
  (if sel
    (progn
      (setq en (car sel)
            ed (entget en (list *md-app*))
            xd (cdr (assoc -3 ed)))
      (if (and (= (cdr (assoc 0 ed)) "INSERT") xd)
        (progn
          (setq v (mapcar 'cdr (cdr (car xd)))
                l1 (md:pedir "Largo del primer tramo" (nth 0 v))
                l2 (md:pedir "Largo del segundo tramo" (nth 1 v))
                f1 (md:pedir "Fondo del primer tramo" (nth 2 v))
                f2 (md:pedir "Fondo del segundo tramo" (nth 3 v))
                op (md:opciones (nth 4 v) (nth 5 v) (nth 6 v))
                giro (nth 7 v))
          (if (md:valido l1 l2 f1 f2)
            (if (setq nombre (md:bloque l1 l2 f1 f2 (nth 0 op) (nth 1 op) (nth 2 op) giro))
              (progn
                (setq ed (subst (cons 2 nombre) (assoc 2 ed) ed)
                      ed (subst (md:xdata l1 l2 f1 f2 (nth 0 op) (nth 1 op) (nth 2 op) giro)
                                (assoc -3 ed) ed))
                (entmod ed)
                (entupd en)
                (princ (strcat "\n[MESAESQ] Mesa actualizada: " nombre)))
              (princ "\n[MESAESQ] No se ha podido crear el bloque."))))
        (princ "\n[MESAESQ] Ese objeto no es una mesa creada con MESAESQ."))))
  (princ))

(princ "\nMesaEsquina cargado. Comandos: MESAESQ (crear) y MESAESQMOD (modificar).")
(princ)
