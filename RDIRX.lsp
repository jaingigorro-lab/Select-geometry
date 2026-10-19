(vl-load-com)

;; ==========================================================
;; RDIRX - Reconstruye directrices EXPLOTADAS (texto + lineas/polilineas +
;; flecha SOLID/INSERT sueltas) como directrices multiples (MLEADER) reales,
;; con el mismo texto, la misma altura, la misma capa y la MISMA ORIENTACION
;; que el texto original.
;;
;; Como funciona:
;;   1. Une las lineas/polilineas seleccionadas en CADENAS (tramos que se
;;      tocan por sus extremos), en los dos sentidos, de modo que cada
;;      directriz original queda como una sola cadena con sus codos.
;;   2. Empareja cada texto con la cadena que tiene un EXTREMO mas cerca del
;;      rectangulo REAL del texto (girado con el, no la caja envolvente
;;      alineada con el SCU, que en un texto girado es enorme y "tocaba"
;;      lineas ajenas). El emparejamiento es global: primero las parejas mas
;;      cercanas de todo el lote, sin repetir texto ni cadena.
;;   3. El extremo de la cadena pegado al texto es el apoyo; el otro, la
;;      punta. Si en la punta hay un SOLID o un INSERT pequeno, es la flecha
;;      vieja (y si la linea acababa en la base del SOLID, la punta nueva se
;;      lleva a su vertice).
;;   4. Crea el MLEADER en el SISTEMA DEL PROPIO TEXTO (su plano y su
;;      angulo), no en el SCU: el texto nuevo queda orientado igual que el
;;      original, aunque se dibujara en un SCP girado o "visto desde abajo".
;;   5. Si el ultimo tramo era el subrayado horizontal bajo el texto
;;      (texto apoyado sobre una linea), lo convierte en el rellano del
;;      MLEADER con el texto subrayado, en lugar de un tramo mas.
;;
;; Todo el lote se deshace con un solo U, Esc no deja nada a medias y se
;; ignoran los objetos en capas bloqueadas.
;;
;; Uso: APPLOAD -> RDIRX -> selecciona textos, lineas/polilineas y flechas.
;; ==========================================================

;; ---------- vectores ----------

(defun rdirx:v- (a b) (mapcar '- a b))
(defun rdirx:dot (a b) (apply '+ (mapcar '* a b)))
(defun rdirx:cross (a b)
  (list (- (* (cadr a) (caddr b)) (* (caddr a) (cadr b)))
        (- (* (caddr a) (car b)) (* (car a) (caddr b)))
        (- (* (car a) (cadr b)) (* (cadr a) (car b)))))
(defun rdirx:unit (v / l)
  (setq l (distance '(0.0 0.0 0.0) v))
  (if (> l 1e-12) (mapcar '(lambda (x) (/ x l)) v) v))

;; ---------- geometria de las piezas ----------

;; Quita puntos consecutivos repetidos.
(defun rdirx:dedup (pts / r)
  (foreach p pts
    (if (or (null r) (> (distance p (car r)) 1e-9)) (setq r (cons p r))))
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

;; Caja envolvente (WCS) de un objeto: (minimo maximo), o nil si AutoCAD no
;; puede calcularla.
(defun rdirx:box (obj / mn mx)
  (if (not (vl-catch-all-error-p (vl-catch-all-apply 'vla-GetBoundingBox (list obj 'mn 'mx))))
    (list (vlax-safearray->list mn) (vlax-safearray->list mx))))

;; Vertices (WCS) de un SOLID.
(defun rdirx:solid-pts (ent / ed)
  (setq ed (entget ent))
  (mapcar '(lambda (k) (trans (cdr (assoc k ed)) ent 0)) '(10 11 12 13)))

;; Sistema PROPIO de un texto: (origen ejeX ejeY ejeZ xmin xmax ymin ymax),
;; todo en WCS salvo el rectangulo, que va en coordenadas locales del texto
;; (X a lo largo de la linea de texto, Y hacia arriba de las letras).
(defun rdirx:frame (ent / ed typ N O X ang tb w h ap col row xmin xmax ymin ymax)
  (setq ed  (entget ent)
        typ (cdr (assoc 0 ed))
        N   (rdirx:unit (cond ((cdr (assoc 210 ed))) ('(0.0 0.0 1.0)))))
  (if (= typ "TEXT")
    (setq O    (trans (cdr (assoc 10 ed)) ent 0)
          ang  (cdr (assoc 50 ed))
          X    (rdirx:unit (trans (list (cos ang) (sin ang) 0.0) N 0 T))
          tb   (cond ((textbox ed)) ('((0.0 0.0 0.0) (0.0 0.0 0.0))))
          xmin (car (car tb))  ymin (cadr (car tb))
          xmax (car (cadr tb)) ymax (cadr (cadr tb)))
    (setq O    (cdr (assoc 10 ed))
          X    (rdirx:unit
                 (cond ((cdr (assoc 11 ed)))
                       (T (setq ang (cond ((cdr (assoc 50 ed))) (0.0)))
                          (trans (list (cos ang) (sin ang) 0.0) N 0 T))))
          w    (cond ((cdr (assoc 42 ed))) (0.0))
          h    (cond ((cdr (assoc 43 ed))) ((cdr (assoc 40 ed))))
          ap   (cond ((cdr (assoc 71 ed))) (1))
          col  (rem (1- ap) 3)   ; 0 izquierda, 1 centro, 2 derecha
          row  (/ (1- ap) 3)     ; 0 arriba, 1 medio, 2 abajo
          xmin (* -0.5 col w)            xmax (+ xmin w)
          ymin (- (* 0.5 row h) h)       ymax (+ ymin h)))
  (list O X (rdirx:unit (rdirx:cross N X)) N xmin xmax ymin ymax))

;; Punto WCS -> coordenadas locales del sistema fr.
(defun rdirx:local (p fr / d)
  (setq d (rdirx:v- p (car fr)))
  (list (rdirx:dot d (nth 1 fr)) (rdirx:dot d (nth 2 fr)) (rdirx:dot d (nth 3 fr))))

;; Distancia de un punto WCS al rectangulo REAL (girado) del texto.
(defun rdirx:dist-text (p fr / l dx dy)
  (setq l  (rdirx:local p fr)
        dx (max 0.0 (- (nth 4 fr) (car l)) (- (car l) (nth 5 fr)))
        dy (max 0.0 (- (nth 6 fr) (cadr l)) (- (cadr l) (nth 7 fr))))
  (sqrt (+ (* dx dx) (* dy dy))))

;; Alarga "chain" por su ultimo punto con tramos no usados que empiecen o
;; terminen ahi. Usa y modifica curves, usedC, ents y tol de c:RDIRX
;; (ambito dinamico de AutoLISP).
(defun rdirx:grow (chain / found ci pts)
  (setq found T)
  (while found
    (setq found nil ci 0)
    (foreach cv curves
      (if (and (not found) (not (member ci usedC)))
        (progn
          (setq pts (cadr cv))
          (cond
            ((<= (distance (car pts) (last chain)) tol)
             (setq found T chain (append chain (cdr pts))))
            ((<= (distance (last pts) (last chain)) tol)
             (setq found T chain (append chain (cdr (reverse pts))))))
          (if found (setq usedC (cons ci usedC) ents (cons (car cv) ents)))))
      (setq ci (1+ ci))))
  chain)

;; ---------- comando ----------

(defun c:RDIRX ( / *error* doc ss i ent typ obj txts curves arrows comps pairs
                   usedT usedC assigned ti ci fr th tol tolA chain ents pts d
                   bestD arrowEnt prev tip lpts a b dog dlen ddir space ml sa
                   rot count minTh)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))

  (defun *error* (msg)
    (vla-EndUndoMark doc)
    (if (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*EXIT*"))
      (princ (strcat "\n[RDIRX] Error: " msg)))
    (princ))

  (prompt "\n[RDIRX] Selecciona las directrices explotadas (textos, lineas/polilineas y flechas): ")
  (if (setq ss (ssget "_:L" '((0 . "TEXT,MTEXT,LINE,LWPOLYLINE,POLYLINE,LEADER,SOLID,INSERT"))))
    (progn
      ;; 1. Clasificar: txts = (ent sistema altura), curves = (ent puntos)
      (setq i 0)
      (repeat (sslength ss)
        (setq ent (ssname ss i)
              typ (cdr (assoc 0 (entget ent)))
              i (1+ i))
        (cond
          ((wcmatch typ "TEXT,MTEXT")
           (setq th (cdr (assoc 40 (entget ent)))
                 txts (cons (list ent (rdirx:frame ent) th) txts)
                 minTh (if minTh (min minTh th) th)))
          ((wcmatch typ "LINE,LWPOLYLINE,POLYLINE,LEADER")
           (if (>= (length (setq pts (rdirx:pts ent))) 2)
             (setq curves (cons (list ent pts) curves))))
          (T (setq arrows (cons ent arrows)))))
      (setq txts (reverse txts) curves (reverse curves))

      (if (not (and txts curves))
        (princ "\n[RDIRX] Faltan datos: la seleccion debe incluir textos y lineas.")
        (progn
          (vla-StartUndoMark doc)

          ;; 2. Unir los tramos en cadenas (en los dos sentidos)
          (setq tol (max 1e-6 (* 0.1 minTh)) ci 0)
          (foreach cv curves
            (if (not (member ci usedC))
              (progn
                (setq usedC (cons ci usedC)
                      ents  (list (car cv))
                      chain (rdirx:grow (cadr cv))
                      chain (reverse (rdirx:grow (reverse chain)))
                      comps (cons (list chain ents) comps))))
            (setq ci (1+ ci)))
          (setq comps (reverse comps))

          ;; 3. Emparejar texto <-> cadena por la distancia de un EXTREMO de la
          ;;    cadena al rectangulo real del texto
          (setq ti 0)
          (foreach tx txts
            (setq ci 0 fr (cadr tx) th (caddr tx))
            (foreach cp comps
              (setq chain (car cp)
                    a (rdirx:dist-text (car chain) fr)
                    b (rdirx:dist-text (last chain) fr))
              (if (<= (min a b) (* 4.0 th))
                (setq pairs (cons (list (min a b) ti ci (< b a)) pairs)))
              (setq ci (1+ ci)))
            (setq ti (1+ ti)))
          (setq pairs (vl-sort pairs '(lambda (p q) (< (car p) (car q)))))
          (foreach pr pairs
            (if (and (not (member (nth 1 pr) usedT)) (not (member (nth 2 pr) assigned)))
              (setq usedT (cons (nth 1 pr) usedT)
                    assigned (cons (nth 2 pr) assigned)
                    comps (subst (append (nth (nth 2 pr) comps) (list (nth 1 pr) (nth 3 pr)))
                                 (nth (nth 2 pr) comps) comps))))
          (setq count 0)

          ;; 4. Reconstruir cada directriz
          (foreach cp comps
            (if (>= (length cp) 4)
              (progn
                (setq ti    (nth 2 cp)
                      ent   (car (nth ti txts))
                      fr    (cadr (nth ti txts))
                      th    (caddr (nth ti txts))
                      tolA  (* 2.0 th)
                      ents  (cadr cp)
                      ;; cadena del apoyo (junto al texto) a la punta
                      chain (if (nth 3 cp) (reverse (car cp)) (car cp)))

                ;; flecha vieja en la punta
                (setq bestD 1e99 arrowEnt nil prev (nth (- (length chain) 2) chain))
                (foreach ar arrows
                  (if (entget ar)
                    (progn
                      (if (= (cdr (assoc 0 (entget ar))) "SOLID")
                        (setq d (apply 'min (mapcar '(lambda (p) (distance p (last chain))) (rdirx:solid-pts ar))))
                        (setq d (distance (trans (cdr (assoc 10 (entget ar))) ar 0) (last chain))
                              ;; un INSERT solo cuenta como flecha si es pequeno
                              b (rdirx:box (vlax-ename->vla-object ar))
                              d (if (and b (< (apply 'distance b) (* 4.0 th))) d 1e99)))
                      (if (and (< d tolA) (< d bestD)) (setq bestD d arrowEnt ar)))))
                (if (and arrowEnt (= (cdr (assoc 0 (entget arrowEnt))) "SOLID"))
                  (progn
                    (setq tip (car (vl-sort (rdirx:solid-pts arrowEnt)
                                            '(lambda (p q) (> (distance p prev) (distance q prev))))))
                    (if (> (distance tip prev) (distance (last chain) prev))
                      (setq chain (append (reverse (cdr (reverse chain))) (list tip))))))

                ;; puntos en el sistema del texto (plano del texto, Z local = 0),
                ;; de la punta al apoyo
                (setq lpts (mapcar '(lambda (p / l) (setq l (rdirx:local p fr)) (list (car l) (cadr l) 0.0))
                                   (reverse chain))
                      dog nil)

                ;; subrayado bajo el texto -> rellano del MLEADER
                (if (>= (length lpts) 3)
                  (progn
                    (setq a (nth (- (length lpts) 2) lpts)   ; codo
                          b (last lpts))                     ; extremo junto al texto
                    (if (and (> (abs (- (car b) (car a))) 1e-9)
                             (<= (abs (- (cadr b) (cadr a))) (* 0.1 (abs (- (car b) (car a))))))
                      (setq dog  T
                            dlen (max (* 0.2 th) (- (abs (- (car b) (car a))) (- (nth 5 fr) (nth 4 fr))))
                            ddir (if (> (car b) (car a)) 1.0 -1.0)
                            lpts (reverse (cdr (reverse lpts)))))))

                (setq pts (apply 'append lpts)
                      sa  (vlax-make-safearray vlax-vbDouble (cons 0 (1- (length pts)))))
                (vlax-safearray-fill sa pts)
                (setq obj   (vlax-ename->vla-object ent)
                      space (vlax-ename->vla-object (cdr (assoc 330 (entget ent))))
                      ml    (vl-catch-all-apply 'vla-AddMLeader (list space (vlax-make-variant sa) 0)))
                (if (vl-catch-all-error-p ml)
                  (princ (strcat "\n[RDIRX] No se pudo crear una directriz: " (vl-catch-all-error-message ml)))
                  (progn
                    (vl-catch-all-apply 'vla-put-ContentType (list ml 2)) ; 2 = acMTextContent
                    (vla-put-TextString ml (vla-get-TextString obj))
                    (vla-put-Layer ml (vla-get-Layer obj))
                    (vl-catch-all-apply 'vla-put-TextHeight (list ml th))
                    (vl-catch-all-apply 'vla-put-TextRotation (list ml 0.0))
                    (if dog
                      (progn
                        (vl-catch-all-apply 'vla-put-DogLegged (list ml :vlax-true))
                        (vl-catch-all-apply 'vla-put-DoglegLength (list ml dlen))
                        (vl-catch-all-apply 'vla-SetDoglegDirection (list ml 0 (vlax-3d-point (list ddir 0.0 0.0))))
                        ;; 8 = acAttachmentAllLine: texto subrayado, como el original
                        (vl-catch-all-apply 'vla-put-TextLeftAttachmentType (list ml 8))
                        (vl-catch-all-apply 'vla-put-TextRightAttachmentType (list ml 8)))
                      (vl-catch-all-apply 'vla-put-DogLegged (list ml :vlax-false)))

                    ;; llevar el MLEADER del plano XY al sistema del texto
                    (setq rot (mapcar '(lambda (k)
                                         (list (nth k (nth 1 fr)) (nth k (nth 2 fr)) (nth k (nth 3 fr)) (nth k (car fr))))
                                      '(0 1 2)))
                    (vla-TransformBy ml (vlax-tmatrix (append rot '((0.0 0.0 0.0 1.0)))))

                    (entdel ent)
                    (foreach c ents (if (entget c) (entdel c)))
                    (if arrowEnt (entdel arrowEnt))
                    (setq arrows (vl-remove arrowEnt arrows)
                          count (1+ count)))))))

          (vla-EndUndoMark doc)
          (princ (strcat "\n[RDIRX] " (itoa count) " directriz(es) reconstruida(s)"
                         (if (< count (length txts))
                           (strcat "; " (itoa (- (length txts) count)) " texto(s) sin linea cercana, sin tocar.")
                           ".")))))))
  (princ))

(princ "\n[RDIRX] Cargado. Escribe RDIRX para reconstruir directrices explotadas.")
(princ)
