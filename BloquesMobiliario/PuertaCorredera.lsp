;;; ===========================================================================
;;; PuertaCorredera.lsp
;;;
;;; Puerta corredera empotrada (de cajon) en planta, de una o dos hojas, con
;;; medidas editables. Se dibuja como las del plano: cajon dentro del tabique,
;;; hoja recogida en el cajon en discontinua, canto que asoma por la boca,
;;; recorrido de cierre en discontinua y flecha de apertura.
;;;  - Dos hojas: un cajon a cada lado y el paso en el centro del tramo.
;;;  - Una hoja: el cajon en el lado del primer punto que se pincha.
;;; Las discontinuas estan dibujadas a trazos, asi que se ven igual con
;;; cualquier escala de tipo de linea.
;;;
;;; Unidades: se calcula en metros y se dibuja a la escala del dibujo, que se
;;; deduce del largo del tramo (1.30 son metros, 130 centimetros y 1300
;;; milimetros). Asi funciona aunque INSUNITS no coincida.
;;;
;;; Comandos:
;;;   CORREDERA     Pincha los dos extremos del tramo de pared en una de sus
;;;                 caras y despues un punto en la otra cara (da el grosor).
;;;                 Elige una o dos hojas y el ancho de paso (por defecto, el
;;;                 mayor que cabe). La puerta queda centrada en el tramo y las
;;;                 flechas en el lado de la cara pinchada.
;;;   CORREDERAMOD  Cambia el ancho de paso, el grosor o las hojas de una
;;;                 corredera ya insertada. Sigue centrada en el mismo punto.
;;;
;;; Cada combinacion es un bloque (p. ej. CORREDERA_2H_0.630x0.069: dos hojas,
;;; paso x grosor; con una hoja se anade _I o _D segun el lado del cajon). Las
;;; medidas se guardan en la insercion (XDATA "CORREDERA").
;;; ===========================================================================

(setq *pc-app*   "CORREDERA"
      *pc-k*     1.0            ; metros -> unidades del dibujo
      *pc-sx*    1.0            ; -1 para dibujar reflejado (cajon a la derecha)
      *pc-hojas* "Dos"
      *pc-e*     0.0            ; grosor del tabique en curso (m)
      *pc-s*     0.0            ; ancho del hueco del cajon
      *pc-t*     0.0            ; grueso de la hoja
      *pc-sol*   0.04           ; la hoja cerrada se queda 4 cm dentro del cajon
      *pc-sal*   0.03           ; la hoja abierta asoma 3 cm por la boca
      *pc-hol*   0.01)          ; holgura al fondo del cajon

;;; ---------------------------------------------------------------------------
;;; Primitivas: capa 0 y color PorCapa. Reciben metros en coordenadas de la
;;; puerta: x a lo largo de la pared (0 en el centro del paso), y = 0 en la
;;; cara pinchada e y = grosor en la otra.
;;; ---------------------------------------------------------------------------

(defun pc:p (x y) (list (* x *pc-sx* *pc-k*) (* y *pc-k*) 0.0))

(defun pc:linea (x1 y1 x2 y2)
  (entmake (list '(0 . "LINE") '(8 . "0") (cons 10 (pc:p x1 y1)) (cons 11 (pc:p x2 y2)))))

;; Discontinua a trazos de 5 cm con huecos de 2.5 cm, desde el primer punto
(defun pc:trazos (x1 y1 x2 y2 / l d0 d1 dx dy)
  (setq l (distance (list x1 y1) (list x2 y2))
        dx (- x2 x1)
        dy (- y2 y1)
        d0 0.0)
  (while (< d0 l)
    (setq d1 (min l (+ d0 0.05)))
    (pc:linea (+ x1 (* dx (/ d0 l))) (+ y1 (* dy (/ d0 l)))
              (+ x1 (* dx (/ d1 l))) (+ y1 (* dy (/ d1 l))))
    (setq d0 (+ d1 0.025))))

(defun pc:rect (x1 y1 x2 y2 / e l)
  (foreach e (list (list x1 y1) (list x2 y1) (list x2 y2) (list x1 y2))
    (setq l (cons (cons 10 (list (car (pc:p (car e) (cadr e))) (cadr (pc:p (car e) (cadr e))))) l)))
  (entmake (append (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") '(8 . "0")
                         '(100 . "AcDbPolyline") '(90 . 4) '(70 . 1))
                   (reverse l))))

;; Flecha de xa a xb a la altura y, con la punta en xb
(defun pc:flecha (xa xb y / d h)
  (setq d (if (> xb xa) -1.0 1.0)
        h (min 0.08 (* 0.35 (abs (- xb xa)))))
  (pc:linea xa y xb y)
  (pc:linea xb y (+ xb (* d h 0.906)) (+ y (* h 0.423)))
  (pc:linea xb y (+ xb (* d h 0.906)) (- y (* h 0.423))))

;;; ---------------------------------------------------------------------------
;;; Puerta
;;; ---------------------------------------------------------------------------

;; Largo del cajon para una hoja que cubre w de paso
(defun pc:cajon-largo (w) (+ w *pc-sol* (- *pc-sal*) *pc-hol*))

;; Cajon con la boca en x = xm, hacia d (-1 izquierda, 1 derecha), de largo
;; lc, con la hoja recogida (puerta abierta)
(defun pc:cajon (xm d lc / yc y1 y2 xf xh ht hc)
  (setq yc (/ *pc-e* 2.0)
        y1 (- yc (/ *pc-s* 2.0))
        y2 (+ yc (/ *pc-s* 2.0))
        xf (+ xm (* d lc))                     ; fondo del cajon
        xh (- xf (* d *pc-hol*))               ; trasera de la hoja
        ht (/ *pc-t* 2.0)
        hc (min (+ ht 0.004) (/ *pc-s* 2.0)))  ; medio canto con el tirador
  ;; hueco del cajon dentro del tabique y jambas de la boca
  (pc:linea xm y1 xf y1)
  (pc:linea xm y2 xf y2)
  (pc:linea xf y1 xf y2)
  (pc:linea xm 0.0 xm y1)
  (pc:linea xm y2 xm *pc-e*)
  ;; hoja recogida: caras ocultas en discontinua y trasera
  (pc:trazos xm (- yc ht) xh (- yc ht))
  (pc:trazos xm (+ yc ht) xh (+ yc ht))
  (pc:linea xh (- yc ht) xh (+ yc ht))
  ;; canto que asoma por la boca
  (pc:rect (- xm (* d *pc-sal*)) (- yc hc) xm (+ yc hc)))

;; Dibuja la puerta. hojas "Dos": cajones a los dos lados y paso centrado en
;; x = 0. hojas "Una": sistema centrado en x = 0 con el cajon a la izquierda
;; (lado "I") o reflejado a la derecha (lado "D").
(defun pc:dibujar (a e hojas lado / h lc x1 xm yc ya)
  (setq *pc-e* e
        *pc-s* (min 0.06 (max 0.035 (- e 0.05)))
        *pc-t* (min 0.04 (- *pc-s* 0.012))
        *pc-sx* (if (= lado "D") -1.0 1.0)
        yc (/ e 2.0)
        ya -0.12)
  (if (= hojas "Dos")
    (progn
      (setq h (/ a 2.0)
            lc (pc:cajon-largo h))
      (pc:cajon (- h) -1.0 lc)
      (pc:cajon h 1.0 lc)
      ;; hojas cerradas, del centro a cada boca (con un hueco en el centro,
      ;; donde se juntan), y flechas de apertura
      (pc:trazos -0.0125 yc (- *pc-sal* h) yc)
      (pc:trazos 0.0125 yc (- h *pc-sal*) yc)
      (pc:flecha (* -0.2 h) (* -0.8 h) ya)
      (pc:flecha (* 0.2 h) (* 0.8 h) ya))
    (progn
      (setq lc (pc:cajon-largo a)
            x1 (/ (+ a lc) 2.0)                ; jamba del lado sin cajon
            xm (- x1 a))                       ; boca del cajon
      (pc:cajon xm -1.0 lc)
      (pc:linea x1 0.0 x1 e)
      (pc:trazos x1 yc (+ xm *pc-sal*) yc)
      (pc:flecha (+ xm (* 0.8 a)) (+ xm (* 0.2 a)) ya)))
  (setq *pc-sx* 1.0))

;;; ---------------------------------------------------------------------------
;;; Bloque, insercion y datos
;;; ---------------------------------------------------------------------------

;; Metros -> unidades del dibujo segun el largo del tramo en unidades del
;; dibujo (de 0.80 a 8 m). Los intervalos no se solapan. nil si no encaja.
(defun pc:escala (s)
  (cond ((and (>= s 0.8) (< s 8.0)) 1.0)
        ((and (>= s 80.0) (< s 800.0)) 100.0)
        ((and (>= s 800.0) (< s 8000.0)) 1000.0)))

;; Redondea al milimetro (en metros)
(defun pc:mm (v) (/ (fix (+ (* v 1000.0) 0.5)) 1000.0))

;; Decimales para mostrar medidas en unidades del dibujo
(defun pc:dec () (cond ((= *pc-k* 1000.0) 0) ((= *pc-k* 100.0) 1) (T 3)))

;; Ancho de una hoja y largo de su cajon
(defun pc:hoja (a hojas) (+ (if (= hojas "Dos") (/ a 2.0) a) *pc-sol*))

(defun pc:nombre (a e hojas lado)
  (strcat "CORREDERA_" (if (= hojas "Dos") "2H" "1H") "_" (rtos a 2 3) "x" (rtos e 2 3)
          (if (= hojas "Dos") "" (strcat "_" lado))
          (cond ((= *pc-k* 100.0) "_cm") ((= *pc-k* 1000.0) "_mm") (T ""))))

;; Crea la definicion si no existe. Devuelve el nombre, o nil si falla.
(defun pc:bloque (a e hojas lado / nombre)
  (setq nombre (pc:nombre a e hojas lado))
  (if (not (tblsearch "BLOCK" nombre))
    (progn
      (entmake (list '(0 . "BLOCK") (cons 2 nombre) '(70 . 0) '(10 0.0 0.0 0.0)))
      (pc:dibujar a e hojas lado)
      (if (not (entmake '((0 . "ENDBLK"))))
        (setq nombre nil))))
  nombre)

(defun pc:valido (a e hojas / h)
  (setq h (pc:hoja a hojas))
  (cond ((or (< h 0.30) (> h 1.30))
         (princ "\n[CORREDERA] Cada hoja debe medir entre 0,30 y 1,30 m.") nil)
        ((or (< e 0.05) (> e 0.40))
         (princ "\n[CORREDERA] El grosor de la pared debe estar entre 0,05 y 0,40 m.") nil)
        (T T)))

(defun pc:xdata (a e hojas lado)
  (list -3 (list *pc-app* (cons 1040 a) (cons 1040 e) (cons 1000 hojas) (cons 1000 lado)
                 (cons 1040 *pc-k*))))

(defun pc:pedir (msg v / r)
  (initget 6)
  (setq r (getdist (strcat "\n" msg " <" (rtos (* v *pc-k*) 2 (pc:dec)) ">: ")))
  (if r (pc:mm (/ r *pc-k*)) v))

(defun pc:informe (nombre a e hojas / h)
  (setq h (pc:hoja a hojas))
  (princ (strcat "\n[CORREDERA] " nombre ": paso de " (rtos a 2 3) " m, "
                 (if (= hojas "Dos") "dos hojas de " "una hoja de ") (rtos h 2 3) " m y "
                 (if (= hojas "Dos") "cajones de " "cajon de ")
                 (rtos (pc:cajon-largo (- h *pc-sol*)) 2 3) " m."))
  (if (< e 0.09)
    (princ (strcat "\n[CORREDERA] Aviso: la pared mide " (rtos (* e 100.0) 2 1)
                   " cm. Los cajones de corredera suelen pedir un tabique terminado"
                   " de unos 10 cm; compruebalo con el modelo que vayas a poner."))))

;;; ---------------------------------------------------------------------------
;;; Comandos
;;; ---------------------------------------------------------------------------

(defun c:CORREDERA ( / p1 p2 p3 ang l d e r amax a lado nombre rot)
  (setq p1 (getpoint "\nPrimer extremo del tramo de pared, en una de sus caras: "))
  (if p1 (setq p2 (getpoint p1 "\nSegundo extremo del tramo: ")))
  (if p2 (setq p3 (getpoint p2 "\nPunto en la otra cara de la pared (da el grosor): ")))
  (if p3
    (progn
      (setq p1 (trans p1 1 0)
            p2 (trans p2 1 0)
            p3 (trans p3 1 0)
            ang (angle p1 p2)
            l (distance p1 p2)
            ;; distancia de p3 a la cara pinchada, con signo (+ = a la izquierda)
            d (+ (* (- (car p3) (car p1)) (- (sin ang))) (* (- (cadr p3) (cadr p1)) (cos ang))))
      (if (setq *pc-k* (pc:escala l))
        (progn
          (setq l (/ l *pc-k*)
                e (pc:mm (/ (abs d) *pc-k*)))
          (initget "Una Dos")
          (if (setq r (getkword (strcat "\nHojas [Una/Dos] <" *pc-hojas* ">: ")))
            (setq *pc-hojas* r))
          ;; paso maximo que cabe en el tramo, redondeado al mm por abajo
          ;; (con una tolerancia para los decimales de los puntos pinchados)
          (setq amax (/ (fix (+ (* (- l (if (= *pc-hojas* "Dos") 0.04 0.02)) 500.0) 1e-6)) 1000.0)
                a (pc:pedir "Ancho de paso" amax))
          (if (> a amax)
            (progn
              (princ (strcat "\n[CORREDERA] En este tramo cabe un paso de " (rtos amax 2 3)
                             " m como maximo; se usa ese."))
              (setq a amax)))
          ;; la otra cara tiene que quedar en +y del bloque: si esta a la
          ;; derecha, se gira media vuelta y el primer punto queda a la derecha
          (setq rot (if (< d 0.0) (+ ang pi) ang)
                lado (cond ((= *pc-hojas* "Dos") "") ((< d 0.0) "D") (T "I")))
          (if (pc:valido a e *pc-hojas*)
            (if (setq nombre (pc:bloque a e *pc-hojas* lado))
              (progn
                (if (not (tblsearch "APPID" *pc-app*)) (regapp *pc-app*))
                (if (entmake (list '(0 . "INSERT") (cons 2 nombre)
                                   (cons 10 (list (/ (+ (car p1) (car p2)) 2.0)
                                                  (/ (+ (cadr p1) (cadr p2)) 2.0)
                                                  (/ (+ (caddr p1) (caddr p2)) 2.0)))
                                   (cons 50 rot) (pc:xdata a e *pc-hojas* lado)))
                  (progn
                    (pc:informe nombre a e *pc-hojas*)
                    (princ "\n[CORREDERA] Para cambiarla: CORREDERAMOD."))
                  (princ "\n[CORREDERA] No se ha podido insertar el bloque.")))
              (princ "\n[CORREDERA] No se ha podido crear el bloque."))))
        (progn
          (setq *pc-k* 1.0)
          (princ (strcat "\n[CORREDERA] El tramo mide " (rtos l 2 3)
                         ": no parece una puerta en metros, centimetros ni milimetros."))))))
  (princ))

(defun c:CORREDERAMOD ( / sel en ed xd v a e hojas lado r nombre)
  (setq sel (entsel "\nSelecciona la puerta corredera: "))
  (if sel
    (progn
      (setq en (car sel)
            ed (entget en (list *pc-app*))
            xd (cdr (assoc -3 ed)))
      (if (and (= (cdr (assoc 0 ed)) "INSERT") xd)
        (progn
          (setq v (mapcar 'cdr (cdr (car xd)))
                *pc-k* (nth 4 v)
                a (pc:pedir "Ancho de paso" (nth 0 v))
                e (pc:pedir "Grosor de la pared" (nth 1 v))
                hojas (nth 2 v)
                lado (nth 3 v))
          (initget "Una Dos")
          (if (setq r (getkword (strcat "\nHojas [Una/Dos] <" hojas ">: ")))
            (setq hojas r))
          (if (= hojas "Una")
            (progn
              (if (= lado "") (setq lado "I"))
              (initget "Si No")
              (if (= (getkword "\nCambiar el cajon de lado [Si/No] <No>: ") "Si")
                (setq lado (if (= lado "I") "D" "I"))))
            (setq lado ""))
          (if (pc:valido a e hojas)
            (if (setq nombre (pc:bloque a e hojas lado))
              (progn
                (setq ed (subst (cons 2 nombre) (assoc 2 ed) ed)
                      ed (subst (pc:xdata a e hojas lado) (assoc -3 ed) ed))
                (entmod ed)
                (entupd en)
                (pc:informe nombre a e hojas))
              (princ "\n[CORREDERA] No se ha podido crear el bloque."))))
        (princ "\n[CORREDERA] Ese objeto no es una puerta creada con CORREDERA."))))
  (princ))

(princ "\nPuertaCorredera cargado. Comandos: CORREDERA (crear) y CORREDERAMOD (modificar).")
(princ)
