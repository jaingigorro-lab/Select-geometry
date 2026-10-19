(vl-load-com)

;; ==========================================================
;; RDIRX - Reconstruye directrices EXPLOTADAS (texto + lineas/polilineas +
;; flecha SOLID/INSERT sueltas) como directrices multiples (MLEADER) reales,
;; con el mismo texto, la misma altura de texto y la misma capa.
;;
;; Correcciones respecto a la version anterior:
;;   - Sigue la CADENA COMPLETA de cada directriz (lineas encadenadas y
;;     vertices de polilinea), no solo el tramo pegado al texto: la punta
;;     de flecha queda donde estaba, aunque la directriz tuviera codos.
;;   - El emparejamiento texto <-> linea es GLOBAL por distancia (primero
;;     las parejas mas cercanas), asi directrices muy juntas no se roban
;;     las lineas entre si. La distancia se mide al contorno del texto, no
;;     a su punto de insercion (en MTEXT suele estar en una esquina).
;;   - Solo borra un INSERT si esta en la punta y es pequeno (del tamano
;;     de una flecha): un bloque normal seleccionado por error no se toca.
;;   - Si la flecha era un SOLID y la linea terminaba en su base, la punta
;;     de la directriz nueva va al vertice real de la flecha.
;;   - Crea el MLEADER con ActiveX (sin comando MLEADER ni texto "X"
;;     provisional), en el mismo espacio (modelo o presentacion) que el
;;     texto original, y sin tocar OSMODE.
;;   - Todo el lote se deshace con un solo U, y Esc no deja nada a medias.
;;   - Ignora objetos en capas bloqueadas.
;;
;; Uso: APPLOAD -> RDIRX -> selecciona textos, lineas/polilineas y flechas
;; (puedes seleccionar muchas directrices de una vez con una ventana).
;; ==========================================================

;; Distancia en planta (ignora Z).
(defun rdirx:d2 (a b)
  (distance (list (car a) (cadr a)) (list (car b) (cadr b))))

;; Quita puntos consecutivos repetidos.
(defun rdirx:dedup (pts / r)
  (foreach p pts
    (if (or (null r) (> (rdirx:d2 p (car r)) 1e-9)) (setq r (cons p r))))
  (reverse r))

;; Vertices (WCS) de una linea, polilinea o LEADER, en orden.
(defun rdirx:pts (ent / typ n i r)
  (setq typ (cdr (assoc 0 (entget ent))))
  (rdirx:dedup
    (cond
      ((= typ "LINE")
       (list (vlax-curve-getStartPoint ent) (vlax-curve-getEndPoint ent)))
      ((= typ "LEADER")
       (mapcar 'cdr (vl-remove-if-not '(lambda (x) (= (car x) 10)) (entget ent))))
      (T
       (setq n (fix (+ 0.5 (vlax-curve-getEndParam ent))) i 0)
       (repeat (1+ n)
         (setq r (cons (vlax-curve-getPointAtParam ent i) r) i (1+ i)))
       (reverse r)))))

;; Caja envolvente (WCS) de un objeto: (minimo maximo).
;; nil si AutoCAD no puede calcularla (bloque vacio, texto vacio...).
(defun rdirx:box (obj / mn mx)
  (if (not (vl-catch-all-error-p (vl-catch-all-apply 'vla-GetBoundingBox (list obj 'mn 'mx))))
    (list (vlax-safearray->list mn) (vlax-safearray->list mx))))

;; Distancia en planta de un punto a una caja (0 si esta dentro).
(defun rdirx:dist-box (p box / mn mx dx dy)
  (setq mn (car box) mx (cadr box)
        dx (max 0.0 (- (car mn) (car p)) (- (car p) (car mx)))
        dy (max 0.0 (- (cadr mn) (cadr p)) (- (cadr p) (cadr mx))))
  (sqrt (+ (* dx dx) (* dy dy))))

;; Vertices (WCS) de un SOLID.
(defun rdirx:solid-pts (ent / ed)
  (setq ed (entget ent))
  (mapcar '(lambda (k) (trans (cdr (assoc k ed)) ent 0)) '(10 11 12 13)))

(defun c:RDIRX ( / *error* doc ss i ent typ obj txts curves arrows pairs
                   usedT usedC assigned ti ci rec used chain th tol tolA found
                   pts best bestD d tip prev arrowEnt space ml sa z count)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))

  (defun *error* (msg)
    (vla-EndUndoMark doc)
    (if (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*EXIT*"))
      (princ (strcat "\n[RDIRX] Error: " msg)))
    (princ))

  (prompt "\n[RDIRX] Selecciona las directrices explotadas (textos, lineas/polilineas y flechas): ")
  (if (setq ss (ssget "_:L" '((0 . "TEXT,MTEXT,LINE,LWPOLYLINE,POLYLINE,LEADER,SOLID,INSERT"))))
    (progn
      ;; 1. Clasificar
      (setq i 0)
      (repeat (sslength ss)
        (setq ent (ssname ss i)
              typ (cdr (assoc 0 (entget ent)))
              i (1+ i))
        (cond
          ((wcmatch typ "TEXT,MTEXT")
           (setq obj (vlax-ename->vla-object ent)
                 rec (rdirx:box obj))
           ;; sin caja: se usa el punto de insercion como caja de tamano cero
           (if (null rec)
             (setq rec (list (trans (cdr (assoc 10 (entget ent))) ent 0)
                             (trans (cdr (assoc 10 (entget ent))) ent 0))))
           (setq txts (cons (list ent rec (cdr (assoc 40 (entget ent)))) txts)))
          ((wcmatch typ "LINE,LWPOLYLINE,POLYLINE,LEADER")
           (if (>= (length (setq pts (rdirx:pts ent))) 2)
             (setq curves (cons (list ent pts) curves))))
          (T (setq arrows (cons ent arrows)))))
      (setq txts (reverse txts) curves (reverse curves))

      (if (not (and txts curves))
        (princ "\n[RDIRX] Faltan datos: la seleccion debe incluir textos y lineas.")
        (progn
          (vla-StartUndoMark doc)

          ;; 2. Emparejamiento global texto <-> linea por distancia
          (setq ti 0)
          (foreach tx txts
            (setq ci 0 th (caddr tx))
            (foreach cv curves
              (setq pts (cadr cv)
                    d (min (rdirx:dist-box (car pts) (cadr tx))
                           (rdirx:dist-box (last pts) (cadr tx))))
              (if (<= d (* 4.0 th))
                (setq pairs (cons (list d ti ci) pairs)))
              (setq ci (1+ ci)))
            (setq ti (1+ ti)))
          (setq pairs (vl-sort pairs '(lambda (a b) (< (car a) (car b)))))
          (foreach pr pairs
            (if (and (not (member (cadr pr) usedT)) (not (member (caddr pr) usedC)))
              (setq usedT (cons (cadr pr) usedT)
                    usedC (cons (caddr pr) usedC)
                    assigned (cons (cons (cadr pr) (caddr pr)) assigned))))
          (setq assigned (reverse assigned) count 0)

          ;; 3. Reconstruir cada directriz
          (foreach as assigned
            (setq rec (nth (car as) txts)
                  ent (car rec)
                  th (caddr rec)
                  tol (max 1e-6 (* 0.1 th))
                  tolA (* 2.0 th)
                  pts (cadr (nth (cdr as) curves))
                  ;; la cadena empieza en el extremo pegado al texto (apoyo)
                  chain (if (< (rdirx:dist-box (car pts) (cadr rec))
                               (rdirx:dist-box (last pts) (cadr rec)))
                          pts (reverse pts))
                  used (list (car (nth (cdr as) curves))))

            ;; seguir tramos encadenados hasta la punta
            (setq found T)
            (while found
              (setq found nil ci 0)
              (foreach cv curves
                (if (and (not found) (not (member ci usedC)))
                  (progn
                    (setq pts (cadr cv))
                    (cond
                      ((<= (rdirx:d2 (car pts) (last chain)) tol)
                       (setq found T chain (append chain (cdr pts))))
                      ((<= (rdirx:d2 (last pts) (last chain)) tol)
                       (setq found T chain (append chain (cdr (reverse pts))))))
                    (if found
                      (setq usedC (cons ci usedC) used (cons (car cv) used)))))
                (setq ci (1+ ci))))

            ;; buscar la flecha vieja en la punta
            (setq bestD 1e99 arrowEnt nil prev (nth (- (length chain) 2) chain))
            (foreach ar arrows
              (if (entget ar)
                (progn
                  (if (= (cdr (assoc 0 (entget ar))) "SOLID")
                    (setq d (apply 'min (mapcar '(lambda (p) (rdirx:d2 p (last chain))) (rdirx:solid-pts ar))))
                    (setq d (rdirx:d2 (trans (cdr (assoc 10 (entget ar))) ar 0) (last chain))
                          ;; un INSERT solo cuenta como flecha si es pequeno
                          rec (rdirx:box (vlax-ename->vla-object ar))
                          d (if (and rec (< (apply 'distance rec) (* 4.0 th))) d 1e99)))
                  (if (and (< d tolA) (< d bestD)) (setq bestD d arrowEnt ar)))))
            (if (and arrowEnt (= (cdr (assoc 0 (entget arrowEnt))) "SOLID"))
              (progn
                (setq tip (car (vl-sort (rdirx:solid-pts arrowEnt)
                                        '(lambda (a b) (> (rdirx:d2 a prev) (rdirx:d2 b prev))))))
                (if (> (rdirx:d2 tip prev) (rdirx:d2 (last chain) prev))
                  (setq chain (append (reverse (cdr (reverse chain))) (list tip))))))

            ;; crear el MLEADER: puntos de la punta al apoyo, a la cota Z del texto
            (setq obj (vlax-ename->vla-object ent)
                  z (caddr (car (cadr (nth (car as) txts))))
                  pts (apply 'append (mapcar '(lambda (p) (list (car p) (cadr p) z)) (reverse chain)))
                  sa (vlax-make-safearray vlax-vbDouble (cons 0 (1- (length pts)))))
            (vlax-safearray-fill sa pts)
            (setq space (vlax-ename->vla-object (cdr (assoc 330 (entget ent))))
                  ml (vl-catch-all-apply 'vla-AddMLeader (list space (vlax-make-variant sa) 0)))
            (if (vl-catch-all-error-p ml)
              (princ (strcat "\n[RDIRX] No se pudo crear una directriz: " (vl-catch-all-error-message ml)))
              (progn
                (vl-catch-all-apply 'vla-put-ContentType (list ml 2)) ; 2 = acMTextContent
                (vla-put-TextString ml (vla-get-TextString obj))
                (vla-put-Layer ml (vla-get-Layer obj))
                (vl-catch-all-apply 'vla-put-TextHeight (list ml th))
                ;; sin rellano extra: el texto se apoya en el ultimo punto original
                (vl-catch-all-apply 'vla-put-DogLegged (list ml :vlax-false))
                (entdel ent)
                (foreach c used (if (entget c) (entdel c)))
                (if arrowEnt (entdel arrowEnt))
                (setq arrows (vl-remove arrowEnt arrows)
                      count (1+ count)))))

          (vla-EndUndoMark doc)
          (princ (strcat "\n[RDIRX] " (itoa count) " directriz(es) reconstruida(s)"
                         (if (< count (length txts))
                           (strcat "; " (itoa (- (length txts) count)) " texto(s) sin linea cercana, sin tocar.")
                           ".")))))))
  (princ))

(princ "\n[RDIRX] Cargado. Escribe RDIRX para reconstruir directrices explotadas.")
(princ)
