(vl-load-com)

;; ==========================================================
;; CONDUCTO - Traza un recorrido de conducto de climatizacion (circular
;; o rectangular) a doble linea y a escala real, insertando en cada
;; cambio de direccion el codo normalizado correspondiente:
;;   - Circular: codo curvo con radio 1.5 x diametro (SMACNA), tangente
;;     a los dos tramos que conecta.
;;   - Rectangular: codo a escuadra (mitrado a 90), sin radio -la
;;     esquina recta habitual en conducto rectangular de chapa.
;; En ambos casos se avisa (sin bloquear el dibujo) si el angulo de un
;; codo no es uno de los normalizados habituales, para poder corregir
;; el recorrido con ORTHO/polar si hace falta.
;;
;; Uso:
;;   1. Ejecutar CONDUCTO.
;;   2. Elegir tipo de conducto (Circular/Rectangular) y su dimension
;;      (diametro, o ancho en planta).
;;   3. Trazar el recorrido como una polilinea normal (con ORTHO, polar
;;      u OSNAP si se quiere): un punto inicial, los puntos intermedios
;;      donde el conducto cambia de direccion, e Intro para terminar.
;;      No uses arcos dentro de esa polilinea: solo tramos rectos, los
;;      codos los pone el comando.
;;   4. El comando genera el doble contorno del conducto (dos lineas
;;      paralelas separadas la dimension indicada) con los codos
;;      normalizados ya insertados en cada vertice, y conserva la
;;      polilinea de eje central usada como base (con linea de
;;      trazo-punto "CENTER" si esta disponible en el dibujo).
;; ==========================================================

;; Radio de los codos circulares = este factor x el diametro (1.5xD,
;; el estandar SMACNA habitual para codos de conducto circular).
(setq *conducto-radius-factor* 1.5)

;; Angulos de codo normalizados (en grados) para conducto circular.
(setq *conducto-standard-angles* (list 90.0 45.0 30.0 22.5 15.0))

;; Tolerancia (grados) para avisar de un angulo de codo no normalizado.
(setq *conducto-angle-warn-tol-deg* 1.0)

;; Concatena una lista de cadenas de texto con un separador.
(defun implode-list (lst sep / result)
  (setq result "")
  (foreach s lst
    (setq result (if (= result "") s (strcat result sep s)))
  )
  result
)

;; AutoLISP no trae TAN por defecto (solo sin/cos/atan).
(defun tan (x) (/ (sin x) (cos x)))

;; Normaliza un angulo en radianes al rango (-pi, pi].
(defun norm-pi (a)
  (while (> a pi) (setq a (- a (* 2.0 pi))))
  (while (<= a (- pi)) (setq a (+ a (* 2.0 pi))))
  a
)

;; Angulo de desviacion (en grados, 0-180) que forma el conducto en el
;; vertice v, viniendo de a y saliendo hacia c.
(defun deflection-deg (a v c / hin hout)
  (setq hin (angle a v))
  (setq hout (angle v c))
  (* (abs (norm-pi (- hout hin))) (/ 180.0 pi))
)

;; De una lista de angulos estandar, devuelve (angulo-mas-cercano
;; diferencia-absoluta) respecto a deg.
(defun nearest-standard-angle (deg lst / best bestd d)
  (setq best (car lst))
  (setq bestd (abs (- deg (car lst))))
  (foreach a (cdr lst)
    (setq d (abs (- deg a)))
    (if (< d bestd) (progn (setq bestd d) (setq best a)))
  )
  (list best bestd)
)

;; Vertices (2D, en orden) de una LWPOLYLINE.
(defun get-polyline-points (ent / obj coordsList pts i n)
  (setq obj (vlax-ename->vla-object ent))
  (setq coordsList (vlax-safearray->list (vlax-variant-value (vla-get-Coordinates obj))))
  (setq pts '())
  (setq n (length coordsList))
  (setq i 0)
  (while (< i n)
    (setq pts (cons (list (nth i coordsList) (nth (1+ i) coordsList)) pts))
    (setq i (+ i 2))
  )
  (reverse pts)
)

;; Quita de una lista de puntos los duplicados consecutivos y los
;; vertices intermedios que no representan un cambio de direccion real
;; (practicamente colineales) -para que FILLET no se encuentre un
;; vertice "recto" al intentar redondearlos todos de una vez.
(defun simplify-points (pts tol / result i n prev cur nxt)
  (setq result (list (car pts)))
  (setq n (length pts))
  (setq i 1)
  (while (< i (1- n))
    (setq prev (last result))
    (setq cur (nth i pts))
    (setq nxt (nth (1+ i) pts))
    (if (and (> (distance prev cur) tol)
             (> (distance cur nxt) tol)
             (> (abs (norm-pi (- (angle cur nxt) (angle prev cur)))) (/ pi 360.0))
        )
      (setq result (append result (list cur)))
    )
    (setq i (1+ i))
  )
  (if (> (distance (last result) (last pts)) tol)
    (setq result (append result (list (last pts))))
  )
  result
)

;; Crea una LWPOLYLINE 2D abierta a partir de una lista de puntos, en
;; la capa actual. Devuelve su ename.
(defun make-polyline (pts / data pt)
  (setq data (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") '(100 . "AcDbPolyline")
                    (cons 90 (length pts)) '(70 . 0)))
  (foreach pt pts
    (setq data (append data (list (cons 10 (list (car pt) (cadr pt))))))
  )
  (entmakex data)
)

;; Desfasa (OFFSET) una curva "dist" unidades (con signo: + a un lado,
;; - al otro). Devuelve la lista de vla-objects resultantes, o nil si
;; ha fallado.
(defun offset-curve (ent dist / obj result)
  (setq obj (vlax-ename->vla-object ent))
  (setq result (vl-catch-all-apply 'vla-Offset (list obj dist)))
  (if (vl-catch-all-error-p result)
    (progn
      (princ (strcat "\n[CONDUCTO] Aviso: fallo el desfase a " (rtos dist 2 2)
                     " (" (vl-catch-all-error-message result) ")."))
      nil
    )
    (vlax-safearray->list (vlax-variant-value result))
  )
)

(defun c:CONDUCTO
  ( / tipo diametro ancho beforeEnt plEnt rawPts pts n radius half
      i a v c defl nearest warnCount tanlen offsets)

  (initget "Circular Rectangular")
  (setq tipo (getkword "\n[CONDUCTO] Tipo de conducto [Circular/Rectangular] <Circular>: "))
  (if (not tipo) (setq tipo "Circular"))

  (if (= tipo "Circular")
    (progn
      (setq diametro (getdist "\n[CONDUCTO] Diametro del conducto: "))
      (if (or (not diametro) (<= diametro 0))
        (progn (princ "\n[CONDUCTO] Cancelado.") (princ) (exit))
      )
    )
    (progn
      (setq ancho (getdist "\n[CONDUCTO] Ancho del conducto (dimension en planta): "))
      (if (or (not ancho) (<= ancho 0))
        (progn (princ "\n[CONDUCTO] Cancelado.") (princ) (exit))
      )
    )
  )

  (princ "\n[CONDUCTO] Traza el recorrido como una polilinea normal, solo tramos rectos (Intro para terminar): ")
  (setq beforeEnt (entlast))
  (command "_.PLINE")
  (while (> (getvar "CMDACTIVE") 0) (command pause))
  (setq plEnt (entlast))

  (if (or (not plEnt) (equal plEnt beforeEnt))
    (progn (princ "\n[CONDUCTO] No se ha trazado ningun recorrido. Cancelado.") (princ) (exit))
  )

  (setq rawPts (get-polyline-points plEnt))
  (if (< (length rawPts) 2)
    (progn
      (entdel plEnt)
      (princ "\n[CONDUCTO] El recorrido necesita al menos dos puntos. Cancelado.")
      (princ) (exit)
    )
  )

  ;; Se reconstruye la polilinea de eje a partir de los puntos ya
  ;; "limpios" (sin vertices colineales) para que FILLET, mas abajo,
  ;; no se encuentre ningun vertice recto al redondearlos todos a la
  ;; vez con la opcion Polilinea.
  (setq pts (simplify-points rawPts 1e-6))
  (entdel plEnt)
  (setq plEnt (make-polyline pts))

  (setq n (length pts))
  (setq warnCount 0)

  (if (= tipo "Circular")
    (progn
      (setq radius (* *conducto-radius-factor* diametro))
      (setq half (/ diametro 2.0))

      ;; Avisar de codos con angulo no normalizado, y de tramos
      ;; demasiado cortos para el radio, ANTES de fileter -una vez
      ;; fileteados los vertices pasan a ser arcos y ya no se puede
      ;; leer el angulo original directamente de los puntos.
      (if (>= n 3)
        (progn
          (setq i 1)
          (while (< i (1- n))
            (setq a (nth (1- i) pts))
            (setq v (nth i pts))
            (setq c (nth (1+ i) pts))
            (setq defl (deflection-deg a v c))
            (setq nearest (nearest-standard-angle defl *conducto-standard-angles*))
            (if (> (cadr nearest) *conducto-angle-warn-tol-deg*)
              (progn
                (princ (strcat "\n[CONDUCTO] Aviso: el codo en el vertice " (itoa (1+ i))
                               " tiene " (rtos defl 2 1) " grados, no es un angulo normalizado ("
                               (implode-list (mapcar '(lambda (x) (rtos x 2 1)) *conducto-standard-angles*) ", ")
                               "). Ajusta el recorrido con ORTHO/polar si hace falta."))
                (setq warnCount (1+ warnCount))
              )
            )
            (setq tanlen (* radius (tan (/ (* defl (/ pi 180.0)) 2.0))))
            (if (or (> tanlen (distance a v)) (> tanlen (distance v c)))
              (princ (strcat "\n[CONDUCTO] Aviso: el tramo junto al vertice " (itoa (1+ i))
                             " puede ser demasiado corto para un codo de radio " (rtos radius 2 1) "."))
            )
            (setq i (1+ i))
          )
          ;; Fileter TODOS los vertices interiores a la vez con el radio
          ;; estandar (1.5 x diametro): quedan como arcos tangentes, el
          ;; codo circular normalizado.
          (command "_.FILLET" "_R" radius "_P" plEnt)
        )
      )
    )
    (progn
      (setq half (/ ancho 2.0))
      ;; Sin fileter: las esquinas se quedan rectas, y el propio OFFSET
      ;; de una polilinea con esquinas rectas produce automaticamente
      ;; el codo a escuadra (mitrado) en cada vertice.
      (if (>= n 3)
        (progn
          (setq i 1)
          (while (< i (1- n))
            (setq a (nth (1- i) pts))
            (setq v (nth i pts))
            (setq c (nth (1+ i) pts))
            (setq defl (deflection-deg a v c))
            (if (> (abs (- defl 90.0)) *conducto-angle-warn-tol-deg*)
              (progn
                (princ (strcat "\n[CONDUCTO] Aviso: el codo en el vertice " (itoa (1+ i))
                               " tiene " (rtos defl 2 1) " grados; el codo a escuadra esta pensado para 90. "
                               "Ajusta el recorrido con ORTHO/polar si hace falta."))
                (setq warnCount (1+ warnCount))
              )
            )
            (setq i (1+ i))
          )
        )
      )
    )
  )

  ;; Doble contorno del conducto: dos desfases simetricos de la
  ;; polilinea de eje (ya con los codos, circulares o a escuadra, ya
  ;; resueltos), uno a cada lado. La linea de eje NO se borra: se deja
  ;; en el dibujo como referencia del recorrido, marcada con la linea
  ;; de trazo-punto "CENTER" tipica de un eje si esta cargada (o
  ;; disponible en acad.lin) -si no, se queda con el tipo de linea
  ;; continuo por defecto, sin que eso afecte al resto del comando.
  (setq offsets (append (offset-curve plEnt half) (offset-curve plEnt (- half))))

  ;; Cargar un tipo de linea con "-LINETYPE Load" puede abrir un cuadro
  ;; de dialogo de seleccion de archivo (si FILEDIA=1) y quedarse
  ;; esperando esa ventana en vez del texto que se le pasa por comando
  ;; -asi que, en vez de arriesgarse a eso, solo se aplica "CENTER" si
  ;; ya esta cargado en el dibujo; si no lo esta, se deja la linea de
  ;; eje en el tipo de linea continuo por defecto.
  (if (tblsearch "LTYPE" "CENTER")
    (vl-catch-all-apply 'vla-put-Linetype (list (vlax-ename->vla-object plEnt) "CENTER"))
  )

  (if offsets
    (princ (strcat "\n[CONDUCTO] Conducto " tipo " creado con " (itoa (max 0 (- n 2))) " codo(s)"
                   (if (> warnCount 0) (strcat ", " (itoa warnCount) " con aviso de angulo") "")
                   ". Eje central conservado."))
    (princ "\n[CONDUCTO] No se ha podido generar el doble contorno del conducto; se deja la linea de eje para revisar.")
  )
  (princ)
)

(princ "\nCONDUCTO cargado. Escribe 'CONDUCTO' para trazar un conducto circular o rectangular a doble linea, con codos normalizados.")
(princ)
