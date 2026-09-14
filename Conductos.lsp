(vl-load-com)

;; ==========================================================
;; CONDUCTOS - Herramientas de trazado de conductos de climatizacion.
;;
;; CONDUCTO - Traza un recorrido de conducto (circular o rectangular)
;;   a doble linea y a escala real, insertando en cada cambio de
;;   direccion el codo normalizado correspondiente:
;;     - Circular: codo curvo con radio 1.5 x diametro (SMACNA),
;;       tangente a los dos tramos que conecta.
;;     - Rectangular: codo a escuadra (mitrado a 90), sin radio -la
;;       esquina recta habitual en conducto rectangular de chapa-.
;;   En ambos casos se avisa (sin bloquear el dibujo) si el angulo de
;;   un codo no es uno de los normalizados habituales.
;;
;;   Uso:
;;     1. Ejecutar CONDUCTO.
;;     2. Elegir tipo de conducto (Circular/Rectangular) y su
;;        dimension (diametro, o ancho en planta).
;;     3. Trazar el recorrido como una polilinea normal: un punto
;;        inicial, los puntos intermedios donde el conducto cambia de
;;        direccion, e Intro para terminar. No uses arcos dentro de
;;        esa polilinea: solo tramos rectos, los codos los pone el
;;        comando. En rectangular se activa ORTHO automaticamente
;;        mientras se traza, para que el angulo salga a 90 sin tener
;;        que acordarse de activarlo (se puede saltar con MAYUS).
;;     4. El comando genera el doble contorno del conducto con los
;;        codos ya insertados, y conserva la polilinea de eje central
;;        usada como base, en gris y con linea de trazo-punto
;;        "CENTER".
;;
;; CONDUCTORAMAL - Inserta una union en T (un ramal) o en cruz (dos
;;   ramales opuestos) sobre un conducto principal YA EXISTENTE
;;   (trazado con CONDUCTO, o cualquier par de lineas/polilineas
;;   paralelas que representen sus dos paredes). El conducto principal
;;   NO se modifica: solo se lee para saber su ancho/diametro y por
;;   donde pasa. Cada ramal se traza con su propio tipo y dimension, y
;;   sus dos paredes se recortan automaticamente justo donde alcanzan
;;   la pared del conducto principal mas cercana a el.
;;
;;   Limitacion: la union debe hacerse sobre un tramo RECTO del
;;   conducto principal, no sobre un codo.
;;
;;   Uso:
;;     1. Ejecutar CONDUCTORAMAL.
;;     2. Elegir Te (un ramal) o Cruz (dos ramales opuestos, cada uno
;;        con su propio tipo/dimension).
;;     3. Seleccionar las DOS paredes del conducto principal, y pulsar
;;        un punto aproximado de conexion sobre el.
;;     4. Para cada ramal: elegir su tipo, su dimension, y pulsar su
;;        punto final. En Cruz, el segundo ramal usa automaticamente
;;        el punto opuesto (misma distancia, direccion contraria).
;; ==========================================================

;; --- Parametros ---

;; Radio de los codos circulares = este factor x el diametro (1.5xD,
;; el estandar SMACNA habitual para codos de conducto circular).
(setq *conducto-radius-factor* 1.5)

;; Angulos de codo normalizados (en grados) para conducto circular.
(setq *conducto-standard-angles* (list 90.0 45.0 30.0 22.5 15.0))

;; Tolerancia (grados) para avisar de un angulo de codo no normalizado.
(setq *conducto-angle-warn-tol-deg* 1.0)

;; Tolerancia (grados) para avisar de que un ramal no sale perpendicular.
(setq *ramal-angle-warn-tol-deg* 2.0)

;; --- Utilidades compartidas ---

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
      (princ (strcat "\n[CONDUCTOS] Aviso: fallo el desfase a " (rtos dist 2 2)
                     " (" (vl-catch-all-error-message result) ")."))
      nil
    )
    (vlax-safearray->list (vlax-variant-value result))
  )
)

;; Se asegura de que el tipo de linea "CENTER" este cargado en el
;; dibujo, cargandolo de acad.lin si hace falta. -LINETYPE Load puede
;; abrir un cuadro de dialogo de seleccion de archivo si FILEDIA=1, asi
;; que se pone FILEDIA a 0 mientras dura la carga (y se restaura
;; despues) para que el comando lea "acad.lin" del propio macro en vez
;; de quedarse esperando esa ventana. Devuelve T si al final esta
;; disponible (ya lo estuviera, o se haya podido cargar).
(defun ensure-center-linetype ( / oldFiledia)
  (if (not (tblsearch "LTYPE" "CENTER"))
    (progn
      (setq oldFiledia (getvar "FILEDIA"))
      (setvar "FILEDIA" 0)
      (vl-catch-all-apply 'command (list "_.-LINETYPE" "_Load" "CENTER" "acad.lin" ""))
      (setvar "FILEDIA" oldFiledia)
    )
  )
  (tblsearch "LTYPE" "CENTER")
)

;; Marca una entidad como "linea de eje": gris (color ACI 8) y linea de
;; trazo-punto "CENTER" si se ha podido cargar.
(defun mark-as-axis (ent / obj)
  (setq obj (vlax-ename->vla-object ent))
  (if (ensure-center-linetype)
    (vl-catch-all-apply 'vla-put-Linetype (list obj "CENTER"))
  )
  (vl-catch-all-apply 'vla-put-color (list obj 8))
)

;; Punto mas cercano a pt sobre la curva ent (LINE, LWPOLYLINE...).
(defun curve-closest-point (ent pt)
  (vlax-curve-getClosestPointTo (vlax-ename->vla-object ent) pt)
)

;; Direccion (angulo) tangente a la curva ent en el punto pt (que debe
;; estar sobre ella, p.ej. el resultado de curve-closest-point).
(defun curve-tangent-dir (ent pt / obj param deriv)
  (setq obj (vlax-ename->vla-object ent))
  (setq param (vlax-curve-getParamAtPoint obj pt))
  (setq deriv (vlax-curve-getFirstDeriv obj param))
  (angle (list 0.0 0.0 0.0) deriv)
)

;; Interseccion de la recta que pasa por p1 con direccion dir1, y la
;; que pasa por p2 con direccion dir2 (rectas infinitas). nil si son
;; paralelas.
(defun line-intersect (p1 dir1 p2 dir2)
  (inters p1 (polar p1 dir1 1.0) p2 (polar p2 dir2 1.0) nil)
)

;; --- CONDUCTO: trazado de un recorrido con codos automaticos ---

(defun c:CONDUCTO
  ( / tipo diametro ancho beforeEnt plEnt rawPts pts n radius half
      i a v c defl nearest warnCount tanlen offsets oldOrtho)

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

  ;; Para rectangular, el unico codo que se genera es a escuadra (90),
  ;; asi que se activa ORTHO mientras se traza para que el angulo salga
  ;; normalizado el solo, sin depender de que el usuario se acuerde de
  ;; activarlo (se puede seguir saltando puntualmente con MAYUS, y se
  ;; restaura el ORTHO que hubiera al terminar). Para circular NO se
  ;; fuerza -los codos normalizados admitidos (45/30/22.5/15) no son
  ;; solo 90, así que forzar ORTHO estorbaria mas de lo que ayuda-.
  (setq oldOrtho (getvar "ORTHOMODE"))
  (if (= tipo "Rectangular") (setvar "ORTHOMODE" 1))

  (princ "\n[CONDUCTO] Traza el recorrido como una polilinea normal, solo tramos rectos (Intro para terminar): ")
  (setq beforeEnt (entlast))
  (command "_.PLINE")
  (while (> (getvar "CMDACTIVE") 0) (command pause))
  (setq plEnt (entlast))

  (setvar "ORTHOMODE" oldOrtho)

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
  ;; en el dibujo como referencia del recorrido, en gris y con trazo-
  ;; punto "CENTER" (ver mark-as-axis).
  (setq offsets (append (offset-curve plEnt half) (offset-curve plEnt (- half))))

  (mark-as-axis plEnt)

  (if offsets
    (princ (strcat "\n[CONDUCTO] Conducto " tipo " creado con " (itoa (max 0 (- n 2))) " codo(s)"
                   (if (> warnCount 0) (strcat ", " (itoa warnCount) " con aviso de angulo") "")
                   ". Eje central conservado."))
    (princ "\n[CONDUCTO] No se ha podido generar el doble contorno del conducto; se deja la linea de eje para revisar.")
  )
  (princ)
)

;; --- CONDUCTORAMAL: uniones en T y en cruz sobre un conducto existente ---

(defun c:CONDUCTORAMAL
  ( / tipoUnion wall1 wall2 pctr p1 p2 centerPt halfMain
      nBranches k branchTipo branchDim far1 farPt branchDirAng
      crossDir dev1 dev2 defl nearPt tanDir branchCL wallEnts
      w wEnt wPts wNearPt wFarPt ip)

  (initget "Te Cruz")
  (setq tipoUnion (getkword "\n[CONDUCTORAMAL] Tipo de union [Te/Cruz] <Te>: "))
  (if (not tipoUnion) (setq tipoUnion "Te"))

  (setq wall1 (car (entsel "\n[CONDUCTORAMAL] Selecciona la primera pared del conducto principal: ")))
  (if (not wall1) (progn (princ "\n[CONDUCTORAMAL] Cancelado.") (princ) (exit)))
  (setq wall2 (car (entsel "\n[CONDUCTORAMAL] Selecciona la segunda pared (la opuesta): ")))
  (if (not wall2) (progn (princ "\n[CONDUCTORAMAL] Cancelado.") (princ) (exit)))

  (setq pctr (getpoint "\n[CONDUCTORAMAL] Punto aproximado de conexion sobre el conducto principal: "))
  (if (not pctr) (progn (princ "\n[CONDUCTORAMAL] Cancelado.") (princ) (exit)))

  (setq p1 (curve-closest-point wall1 pctr))
  (setq p2 (curve-closest-point wall2 pctr))
  (setq centerPt (list (/ (+ (car p1) (car p2)) 2.0) (/ (+ (cadr p1) (cadr p2)) 2.0)))
  (setq halfMain (/ (distance p1 p2) 2.0))
  ;; p1-p2 es, para un tramo recto, perpendicular al eje del conducto
  ;; principal (es la linea que une los dos pies de perpendicular desde
  ;; el mismo punto de union a cada pared paralela) -sirve tal cual
  ;; como referencia para comprobar si un ramal sale perpendicular.
  (setq crossDir (angle p1 p2))

  (setq nBranches (if (= tipoUnion "Cruz") 2 1))
  (setq k 1)
  (while (<= k nBranches)

    (initget "Circular Rectangular")
    (setq branchTipo (getkword (strcat "\n[CONDUCTORAMAL] Tipo del ramal " (itoa k) " [Circular/Rectangular] <Circular>: ")))
    (if (not branchTipo) (setq branchTipo "Circular"))
    (setq branchDim (getdist (strcat "\n[CONDUCTORAMAL] Dimension del ramal " (itoa k) " (diametro, o ancho en planta): ")))
    (if (or (not branchDim) (<= branchDim 0))
      (progn (princ "\n[CONDUCTORAMAL] Ramal cancelado.") (princ) (exit))
    )

    (if (and (= tipoUnion "Cruz") (= k 2))
      ;; El segundo ramal de una cruz sale automaticamente hacia el
      ;; lado opuesto al primero, misma distancia -no se vuelve a
      ;; preguntar el punto final.
      (setq farPt (list (- (* 2.0 (car centerPt)) (car far1)) (- (* 2.0 (cadr centerPt)) (cadr far1))))
      (progn
        (setq farPt (getpoint centerPt (strcat "\n[CONDUCTORAMAL] Punto final del ramal " (itoa k) ": ")))
        (if (not farPt) (progn (princ "\n[CONDUCTORAMAL] Ramal cancelado.") (princ) (exit)))
        (setq far1 farPt)
      )
    )

    (setq branchDirAng (angle centerPt farPt))

    ;; Aviso (no bloqueante) si el ramal no sale perpendicular al
    ;; conducto principal -comparando contra las dos direcciones
    ;; posibles de "cruzar" el conducto (una por cada lado).
    (setq dev1 (abs (norm-pi (- branchDirAng crossDir))))
    (setq dev2 (abs (norm-pi (- branchDirAng (+ crossDir pi)))))
    (setq defl (* (min dev1 dev2) (/ 180.0 pi)))
    (if (> defl *ramal-angle-warn-tol-deg*)
      (princ (strcat "\n[CONDUCTORAMAL] Aviso: el ramal " (itoa k) " no sale perpendicular al conducto principal ("
                     (rtos defl 2 1) " grados de desviacion)."))
    )

    ;; La pared del conducto principal mas cercana al ramal: contra esa
    ;; es contra la que se recortan sus dos paredes -el ramal no debe
    ;; atravesar el conducto principal ni quedarse corto antes de
    ;; llegar a el-.
    (if (< (distance farPt p1) (distance farPt p2))
      (progn (setq nearPt p1) (setq tanDir (curve-tangent-dir wall1 p1)))
      (progn (setq nearPt p2) (setq tanDir (curve-tangent-dir wall2 p2)))
    )

    ;; Eje y paredes del ramal (sin codos: un ramal es un tramo recto).
    (setq branchCL (make-polyline (list centerPt farPt)))
    (setq wallEnts (append (offset-curve branchCL (/ branchDim 2.0)) (offset-curve branchCL (- (/ branchDim 2.0)))))

    (foreach w wallEnts
      (setq wEnt (vlax-vla-object->ename w))
      (setq wPts (get-polyline-points wEnt))
      (if (< (distance (car wPts) centerPt) (distance (last wPts) centerPt))
        (progn (setq wNearPt (car wPts)) (setq wFarPt (last wPts)))
        (progn (setq wNearPt (last wPts)) (setq wFarPt (car wPts)))
      )
      (setq ip (line-intersect nearPt tanDir wNearPt branchDirAng))
      (if ip
        (progn (entdel wEnt) (make-polyline (list ip wFarPt)))
        (princ (strcat "\n[CONDUCTORAMAL] Aviso: no se ha podido recortar una pared del ramal " (itoa k)
                       " contra el conducto principal; se deja sin recortar."))
      )
    )

    (mark-as-axis branchCL)
    (setq k (1+ k))
  )

  (princ "\n[CONDUCTORAMAL] Union creada. El conducto principal no se ha modificado.")
  (princ)
)

(princ "\nCONDUCTOS cargado. Escribe 'CONDUCTO' para trazar un conducto circular o rectangular, o 'CONDUCTORAMAL' para insertar una union en T o en cruz.")
(princ)
