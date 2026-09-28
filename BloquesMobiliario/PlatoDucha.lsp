;;; ===========================================================================
;;; PlatoDucha.lsp
;;;
;;; Plato de ducha en planta ajustado a un hueco, con medidas editables:
;;;  - borde exterior y reborde interior de 3 cm con las esquinas redondeadas;
;;;  - desague centrado, de valvula junto a un lado (rejilla de 12 cm) o
;;;    lineal a lo largo de un lado (canaleta con rejilla);
;;;  - lineas de pendiente hacia la valvula o flecha hacia la canaleta.
;;;
;;; Unidades: el plato se calcula en metros y se dibuja a la escala del
;;; dibujo, que se deduce del tamano del hueco (0.88 son metros, 88
;;; centimetros y 880 milimetros). Asi funciona aunque INSUNITS no coincida
;;; con las unidades en que se ha dibujado.
;;;
;;; Comandos:
;;;   PLATODUCHA     Pincha dos esquinas opuestas del hueco (caras interiores
;;;                  de paredes y tabiques) y despues junto al lado donde va el
;;;                  desague, o elige Centrado. El plato ocupa el hueco justo.
;;;   PLATODUCHAMOD  Cambia el ancho, el largo o el desague de un plato ya
;;;                  insertado. La esquina de insercion no se mueve.
;;;
;;; Cada medida y desague es un bloque (p. ej. PLATODUCHA_0.879x1.595_LA:
;;; L = lineal, V = valvula, C = centrado; B/A/I/D = lado de abajo, arriba,
;;; izquierda o derecha). Las medidas se guardan en la insercion (XDATA
;;; "PLATODUCHA") para poder modificarlas despues.
;;; ===========================================================================

(setq *pd-app*  "PLATODUCHA"
      *pd-k*    1.0            ; metros -> unidades del dibujo
      *pd-tipo* "Valvula"
      *pd-w*    0.0            ; ancho y largo del plato en curso (m)
      *pd-l*    0.0
      *pd-b*    0.03           ; reborde
      *pd-r*    0.04)          ; radio de las esquinas del reborde

;;; ---------------------------------------------------------------------------
;;; Primitivas: capa 0 y color PorCapa. Reciben metros en coordenadas del
;;; plato (origen en la esquina inferior izquierda).
;;; ---------------------------------------------------------------------------

(defun pd:p (x y) (list (* x *pd-k*) (* y *pd-k*) 0.0))

(defun pd:linea (x1 y1 x2 y2)
  (entmake (list '(0 . "LINE") '(8 . "0") (cons 10 (pd:p x1 y1)) (cons 11 (pd:p x2 y2)))))

(defun pd:circulo (cx cy r)
  (entmake (list '(0 . "CIRCLE") '(8 . "0") (cons 10 (pd:p cx cy)) (cons 40 (* r *pd-k*)))))

;; Polilinea de puntos (x y [curvatura del tramo que sale de ese punto])
(defun pd:poli (pts cerrada / e l)
  (foreach e pts
    (setq l (cons (cons 10 (list (* (car e) *pd-k*) (* (cadr e) *pd-k*))) l))
    (if (caddr e) (setq l (cons (cons 42 (caddr e)) l))))
  (entmake (append (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") '(8 . "0")
                         '(100 . "AcDbPolyline") (cons 90 (length pts))
                         (cons 70 (if cerrada 1 0)))
                   (reverse l))))

(defun pd:rect (x1 y1 x2 y2)
  (pd:poli (list (list x1 y1) (list x2 y1) (list x2 y2) (list x1 y2)) T))

;; Rectangulo con las esquinas redondeadas (curvatura tan(90/4))
(defun pd:rect-r (x1 y1 x2 y2 r / b)
  (setq b 0.414213562373)
  (pd:poli (list (list (+ x1 r) y1) (list (- x2 r) y1 b) (list x2 (+ y1 r)) (list x2 (- y2 r) b)
                 (list (- x2 r) y2) (list (+ x1 r) y2 b) (list x1 (- y2 r)) (list x1 (+ y1 r) b))
           T))

;;; ---------------------------------------------------------------------------
;;; Coordenadas "del desague": u a lo largo del lado del desague y v
;;; alejandose de el. Para los otros lados se gira el plato.
;;; ---------------------------------------------------------------------------

(defun pd:g (lado u v)
  (cond ((= lado "Arriba")    (list (- *pd-w* u) (- *pd-l* v)))
        ((= lado "Izquierda") (list v u))
        ((= lado "Derecha")   (list (- *pd-w* v) u))
        (T                    (list u v))))          ; Abajo

(defun pd:gl (lado u1 v1 u2 v2 / a b)
  (setq a (pd:g lado u1 v1)
        b (pd:g lado u2 v2))
  (pd:linea (car a) (cadr a) (car b) (cadr b)))

(defun pd:gr (lado u1 v1 u2 v2 / a b)
  (setq a (pd:g lado u1 v1)
        b (pd:g lado u2 v2))
  (pd:rect (min (car a) (car b)) (min (cadr a) (cadr b))
           (max (car a) (car b)) (max (cadr a) (cadr b))))

;; Largo del lado del desague y distancia hasta el lado opuesto
(defun pd:medidas-lado (lado)
  (if (member lado '("Izquierda" "Derecha"))
    (list *pd-l* *pd-w*)
    (list *pd-w* *pd-l*)))

;;; ---------------------------------------------------------------------------
;;; Desagues
;;; ---------------------------------------------------------------------------

;; Rejilla redonda de 12 cm y lineas de pendiente desde las esquinas del
;; reborde (punto medio de cada curva)
(defun pd:valvula (cx cy / c e d)
  (pd:circulo cx cy 0.06)
  (pd:circulo cx cy 0.045)
  (pd:linea (- cx 0.03) cy (+ cx 0.03) cy)
  (pd:linea cx (- cy 0.03) cx (+ cy 0.03))
  (setq c (+ *pd-b* (* *pd-r* (- 1.0 (sqrt 0.5)))))
  (foreach e (list (list c c) (list (- *pd-w* c) c) (list (- *pd-w* c) (- *pd-l* c)) (list c (- *pd-l* c)))
    (setq d (distance e (list cx cy)))
    (if (> d 0.10)
      (pd:linea (car e) (cadr e)
                (+ cx (* (- (car e) cx) (/ 0.06 d)))
                (+ cy (* (- (cadr e) cy) (/ 0.06 d)))))))

;; Canaleta lineal de 6 cm junto al lado, con rejilla, y flecha de pendiente
;; en el centro del plato
(defun pd:lineal (lado / m a b n i vc f)
  (setq m (pd:medidas-lado lado)
        a (car m)
        b (cadr m))
  (pd:gr lado 0.06 0.05 (- a 0.06) 0.11)
  (pd:gr lado 0.07 0.06 (- a 0.07) 0.10)
  ;; ranuras de la rejilla, repartidas cada 2.5 cm aprox.
  (setq n (fix (+ (/ (- a 0.14) 0.025) 0.5))
        i 1)
  (while (< i n)
    (pd:gl lado (+ 0.07 (* i (/ (- a 0.14) n))) 0.065 (+ 0.07 (* i (/ (- a 0.14) n))) 0.095)
    (setq i (1+ i)))
  (setq vc (/ (+ 0.11 (- b *pd-b*)) 2.0)
        f  (/ (min 0.50 (* 0.6 (- b 0.14))) 2.0))
  (pd:gl lado (/ a 2.0) (+ vc f) (/ a 2.0) (- vc f))
  (pd:gl lado (/ a 2.0) (- vc f) (- (/ a 2.0) 0.025) (+ (- vc f) 0.06))
  (pd:gl lado (/ a 2.0) (- vc f) (+ (/ a 2.0) 0.025) (+ (- vc f) 0.06)))

;;; ---------------------------------------------------------------------------
;;; Plato completo
;;; ---------------------------------------------------------------------------

(defun pd:dibujar (w l tipo lado / c)
  (setq *pd-w* w
        *pd-l* l)
  (pd:rect 0.0 0.0 w l)
  (pd:rect-r *pd-b* *pd-b* (- w *pd-b*) (- l *pd-b*) *pd-r*)
  (cond
    ((= tipo "Lineal") (pd:lineal lado))
    ((= tipo "Valvula")
     (setq c (pd:g lado (/ (car (pd:medidas-lado lado)) 2.0) 0.16))
     (pd:valvula (car c) (cadr c)))
    (T (pd:valvula (/ w 2.0) (/ l 2.0)))))

;;; ---------------------------------------------------------------------------
;;; Bloque, insercion y datos
;;; ---------------------------------------------------------------------------

;; Metros -> unidades del dibujo, segun el lado mayor del hueco medido en
;; unidades del dibujo. Un plato mide de 0.60 a 3.00 m y los intervalos no
;; se solapan, asi que no hay ambiguedad. nil si no encaja en ninguno.
(defun pd:escala (s)
  (cond ((and (>= s 0.5) (< s 5.0)) 1.0)
        ((and (>= s 50.0) (< s 500.0)) 100.0)
        ((and (>= s 500.0) (< s 5000.0)) 1000.0)))

;; Redondea al milimetro (en metros)
(defun pd:mm (v) (/ (fix (+ (* v 1000.0) 0.5)) 1000.0))

;; Decimales para mostrar medidas en unidades del dibujo
(defun pd:dec () (cond ((= *pd-k* 1000.0) 0) ((= *pd-k* 100.0) 1) (T 3)))

(defun pd:nombre (w l tipo lado)
  (strcat "PLATODUCHA_" (rtos w 2 3) "x" (rtos l 2 3) "_"
          (cond ((= tipo "Lineal") "L") ((= tipo "Valvula") "V") (T "C"))
          (cond ((= tipo "Centrado") "")
                ((= lado "Arriba") "A") ((= lado "Izquierda") "I")
                ((= lado "Derecha") "D") (T "B"))
          (cond ((= *pd-k* 100.0) "_cm") ((= *pd-k* 1000.0) "_mm") (T ""))))

;; Crea la definicion si no existe. Devuelve el nombre, o nil si falla.
(defun pd:bloque (w l tipo lado / nombre)
  (setq nombre (pd:nombre w l tipo lado))
  (if (not (tblsearch "BLOCK" nombre))
    (progn
      (entmake (list '(0 . "BLOCK") (cons 2 nombre) '(70 . 0) '(10 0.0 0.0 0.0)))
      (pd:dibujar w l tipo lado)
      (if (not (entmake '((0 . "ENDBLK"))))
        (setq nombre nil))))
  nombre)

(defun pd:valido (w l)
  (if (or (< w 0.60) (< l 0.60) (> w 3.0) (> l 3.0))
    (progn (princ "\n[PLATODUCHA] Cada lado debe medir entre 0,60 y 3,00 m.") nil)
    T))

(defun pd:xdata (w l tipo lado)
  (list -3 (list *pd-app* (cons 1040 w) (cons 1040 l) (cons 1000 tipo) (cons 1000 lado)
                 (cons 1040 *pd-k*))))

;; Lado del rectangulo (esquina q, w x l en unidades del dibujo) mas cercano a p
(defun pd:lado-cercano (p q w l / dx1 dx2 dy1 dy2 m)
  (setq dx1 (abs (- (car p) (car q)))
        dx2 (abs (- (car p) (+ (car q) w)))
        dy1 (abs (- (cadr p) (cadr q)))
        dy2 (abs (- (cadr p) (+ (cadr q) l)))
        m (min dx1 dx2 dy1 dy2))
  (cond ((= m dy1) "Abajo") ((= m dy2) "Arriba") ((= m dx1) "Izquierda") (T "Derecha")))

(defun pd:pedir (msg v / r)
  (initget 6)
  (setq r (getdist (strcat "\n" msg " <" (rtos (* v *pd-k*) 2 (pd:dec)) ">: ")))
  (if r (pd:mm (/ r *pd-k*)) v))

;;; ---------------------------------------------------------------------------
;;; Comandos
;;; ---------------------------------------------------------------------------

(defun c:PLATODUCHA ( / p1 p2 dx dy q w l op tipo lado nombre ang)
  (setq p1 (getpoint "\nPrimera esquina del hueco de la ducha: "))
  (if p1 (setq p2 (getcorner p1 "\nEsquina opuesta: ")))
  (if p2
    (progn
      (setq dx (abs (- (car p2) (car p1)))
            dy (abs (- (cadr p2) (cadr p1))))
      (if (setq *pd-k* (pd:escala (max dx dy)))
        (progn
          (setq q (list (min (car p1) (car p2)) (min (cadr p1) (cadr p2)) 0.0)
                w (pd:mm (/ dx *pd-k*))
                l (pd:mm (/ dy *pd-k*)))
          (initget "Centrado")
          (setq op (getpoint "\nPincha junto al lado del desague o [Centrado] <Centrado>: "))
          (if (and op (listp op))
            (progn
              (setq lado (pd:lado-cercano op q dx dy))
              (initget "Valvula Lineal")
              (setq tipo (getkword (strcat "\nDesague [Valvula/Lineal] <" *pd-tipo* ">: ")))
              (if (not tipo) (setq tipo *pd-tipo*))
              (setq *pd-tipo* tipo))
            (setq tipo "Centrado"
                  lado ""))
          (if (pd:valido w l)
            (if (setq nombre (pd:bloque w l tipo lado))
              (progn
                (if (not (tblsearch "APPID" *pd-app*)) (regapp *pd-app*))
                (setq ang (angle (trans '(0.0 0.0 0.0) 1 0) (trans '(1.0 0.0 0.0) 1 0)))
                (if (entmake (list '(0 . "INSERT") (cons 2 nombre) (cons 10 (trans q 1 0))
                                   (cons 50 ang) (pd:xdata w l tipo lado)))
                  (princ (strcat "\n[PLATODUCHA] Insertado " nombre
                                 ". Para cambiar sus medidas: PLATODUCHAMOD."))
                  (princ "\n[PLATODUCHA] No se ha podido insertar el bloque.")))
              (princ "\n[PLATODUCHA] No se ha podido crear el bloque."))))
        (progn
          (setq *pd-k* 1.0)
          (princ (strcat "\n[PLATODUCHA] El hueco mide " (rtos dx 2 3) " x " (rtos dy 2 3)
                         ": no parece un plato de ducha en metros, centimetros ni milimetros."))))))
  (princ))

(defun c:PLATODUCHAMOD ( / sel en ed xd v w l tipo lado r nombre)
  (setq sel (entsel "\nSelecciona el plato de ducha: "))
  (if sel
    (progn
      (setq en (car sel)
            ed (entget en (list *pd-app*))
            xd (cdr (assoc -3 ed)))
      (if (and (= (cdr (assoc 0 ed)) "INSERT") xd)
        (progn
          (setq v (mapcar 'cdr (cdr (car xd)))
                *pd-k* (if (nth 4 v) (nth 4 v) 1.0)
                w (pd:pedir "Ancho (eje X del plato)" (nth 0 v))
                l (pd:pedir "Largo (eje Y del plato)" (nth 1 v))
                tipo (nth 2 v)
                lado (nth 3 v))
          (initget "Centrado Valvula Lineal")
          (if (setq r (getkword (strcat "\nDesague [Centrado/Valvula/Lineal] <" tipo ">: ")))
            (setq tipo r))
          (if (= tipo "Centrado")
            (setq lado "")
            (progn
              (if (= lado "") (setq lado "Abajo"))
              (initget "Abajo aRriba Izquierda Derecha")
              (if (setq r (getkword (strcat "\nLado del desague [Abajo/aRriba/Izquierda/Derecha] <"
                                            lado ">: ")))
                (setq lado r))))
          (if (pd:valido w l)
            (if (setq nombre (pd:bloque w l tipo lado))
              (progn
                (setq ed (subst (cons 2 nombre) (assoc 2 ed) ed)
                      ed (subst (pd:xdata w l tipo lado) (assoc -3 ed) ed))
                (entmod ed)
                (entupd en)
                (princ (strcat "\n[PLATODUCHA] Plato actualizado: " nombre)))
              (princ "\n[PLATODUCHA] No se ha podido crear el bloque."))))
        (princ "\n[PLATODUCHA] Ese objeto no es un plato creado con PLATODUCHA."))))
  (princ))

(princ "\nPlatoDucha cargado. Comandos: PLATODUCHA (crear) y PLATODUCHAMOD (modificar).")
(princ)
