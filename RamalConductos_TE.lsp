(vl-load-com)

;; ==========================================================
;; CONDUCTORAMAL - Inserta una union en T (un ramal) o en cruz (dos
;; ramales opuestos) sobre un conducto principal YA EXISTENTE (trazado
;; con CONDUCTO, o cualquier par de lineas/polilineas paralelas que
;; representen sus dos paredes). El conducto principal NO se modifica
;; ni se recorta: solo se lee para saber su ancho/diametro y por donde
;; pasa. Cada ramal se traza con su propio tipo y dimension, y sus dos
;; paredes se recortan automaticamente justo donde alcanzan la pared
;; del conducto principal mas cercana a el -asi el ramal queda "pegado"
;; al conducto principal, sin atravesarlo ni dejarlo a medias-.
;;
;; Limitacion: la union debe hacerse sobre un tramo RECTO del conducto
;; principal, no sobre un codo -el recorte se calcula con la tangente
;; local de la pared en ese punto, que en un codo (un arco) no
;; representaria bien la geometria real de la conexion.
;;
;; Uso:
;;   1. Ejecutar CONDUCTORAMAL.
;;   2. Elegir Te (un ramal) o Cruz (dos ramales opuestos, misma linea
;;      de conexion pero cada uno con su propio tipo/dimension).
;;   3. Seleccionar las DOS paredes del conducto principal (las dos
;;      lineas/polilineas paralelas de un mismo conducto), y pulsar un
;;      punto aproximado de conexion sobre el.
;;   4. Para cada ramal: elegir su tipo (Circular/Rectangular), su
;;      dimension, y pulsar su punto final -el tramo sale del punto de
;;      conexion hacia ese punto-. En Cruz, el segundo ramal usa
;;      automaticamente el punto opuesto (misma distancia, direccion
;;      contraria), sin volver a preguntarlo.
;; ==========================================================

;; Tolerancia (grados) para avisar de que un ramal no sale perpendicular.
(setq *ramal-angle-warn-tol-deg* 2.0)

;; Normaliza un angulo en radianes al rango (-pi, pi].
(defun norm-pi (a)
  (while (> a pi) (setq a (- a (* 2.0 pi))))
  (while (<= a (- pi)) (setq a (+ a (* 2.0 pi))))
  a
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
      (princ (strcat "\n[CONDUCTORAMAL] Aviso: fallo el desfase a " (rtos dist 2 2)
                     " (" (vl-catch-all-error-message result) ")."))
      nil
    )
    (vlax-safearray->list (vlax-variant-value result))
  )
)

;; Se asegura de que el tipo de linea "CENTER" este cargado en el
;; dibujo (ver explicacion en CONDUCTO: FILEDIA se pone a 0 para evitar
;; el cuadro de dialogo de seleccion de archivo de -LINETYPE Load).
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

(princ "\nCONDUCTORAMAL cargado. Escribe 'CONDUCTORAMAL' para insertar una union en T o en cruz sobre un conducto existente.")
(princ)
