(vl-load-com)

;; ==========================================================
;; RDIRX - Reconstruye directrices EXPLOTADAS (texto + lineas/polilineas +
;; flecha SOLID/INSERT sueltas) como directrices multiples (MLEADER) reales,
;; con el mismo texto, la misma altura y la misma capa que el original.
;;
;; Como funciona, para cada texto:
;;   1. Busca el tramo con un extremo mas cerca del rectangulo REAL del texto
;;      (girado con el), a menos de 4 alturas de texto. El emparejamiento es
;;      global: primero las parejas texto-tramo mas cercanas de todo el lote.
;;   2. Desde ahi sigue la directriz tramo a tramo, SOLO por lineas de la
;;      MISMA CAPA y el MISMO COLOR que el primer tramo, y se detiene:
;;        - al llegar a la flecha (SOLID o bloque pequeno pegado al extremo),
;;        - donde el camino se bifurca (dos o mas tramos posibles),
;;        - o donde ya no hay continuacion.
;;      Asi no se "come" lineas del dibujo que toquen la directriz.
;;   3. Si junto al texto hay un subrayado (texto escrito sobre una raya y la
;;      diagonal saliendo de un extremo), lo incluye y lo convierte en el
;;      rellano del MLEADER, con el texto subrayado.
;;   4. Crea el MLEADER con el texto HORIZONTAL EN EL SCP ACTUAL (como la
;;      directriz nativa de AutoCAD), o, con la opcion "Original",
;;      conservando el angulo y el plano del texto original.
;;
;; Si el estilo de directriz multiple actual es anotativo, la directriz nueva
;; se deja NO anotativa, para que el texto tenga exactamente la altura real
;; del original (si no, AutoCAD la multiplicaria por la escala de anotacion).
;;
;; Todo el lote se deshace con un solo U, Esc no deja nada a medias y se
;; ignoran los objetos en capas bloqueadas.
;;
;; Uso: APPLOAD -> RDIRX -> elige orientacion -> selecciona textos,
;; lineas/polilineas y flechas.
;; ==========================================================

(if (null *rdirx-orient*) (setq *rdirx-orient* "Scp"))

;; ---------- vectores ----------

(defun rdirx:v- (a b) (mapcar '- a b))
(defun rdirx:v+ (a b) (mapcar '+ a b))
(defun rdirx:vs (v s) (mapcar '(lambda (x) (* x s)) v))
(defun rdirx:dot (a b) (apply '+ (mapcar '* a b)))
(defun rdirx:cross (a b)
  (list (- (* (cadr a) (caddr b)) (* (caddr a) (cadr b)))
        (- (* (caddr a) (car b)) (* (car a) (caddr b)))
        (- (* (car a) (cadr b)) (* (cadr a) (car b)))))
(defun rdirx:unit (v / l)
  (setq l (distance '(0.0 0.0 0.0) v))
  (if (> l 1e-12) (rdirx:vs v (/ 1.0 l)) v))

;; Distancia de un punto a un segmento (3D).
(defun rdirx:seg-dist (p a b / ab l2 k)
  (setq ab (rdirx:v- b a) l2 (rdirx:dot ab ab))
  (if (< l2 1e-18)
    (distance p a)
    (progn
      (setq k (max 0.0 (min 1.0 (/ (rdirx:dot (rdirx:v- p a) ab) l2))))
      (distance p (rdirx:v+ a (rdirx:vs ab k))))))

;; Distancia de un punto a una caja alineada (min max), 0 si esta dentro.
(defun rdirx:dist-aabb (p box)
  (distance p (mapcar '(lambda (x lo hi) (max lo (min hi x))) p (car box) (cadr box))))

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

;; Capa y color (256 = PorCapa) de una entidad.
(defun rdirx:props (ent / ed)
  (setq ed (entget ent))
  (list (strcase (cdr (assoc 8 ed))) (cond ((cdr (assoc 62 ed))) (256))))

;; Caja envolvente (WCS) de un objeto: (minimo maximo), o nil si AutoCAD no
;; puede calcularla.
(defun rdirx:box (obj / mn mx)
  (if (not (vl-catch-all-error-p (vl-catch-all-apply 'vla-GetBoundingBox (list obj 'mn 'mx))))
    (list (vlax-safearray->list mn) (vlax-safearray->list mx))))

;; Vertices (WCS) de un SOLID, en el orden de sus aristas.
(defun rdirx:solid-pts (ent / ed)
  (setq ed (entget ent))
  (mapcar '(lambda (k) (trans (cdr (assoc k ed)) ent 0)) '(10 11 13 12)))

;; Distancia de un punto al contorno de un SOLID.
(defun rdirx:solid-dist (p ent / v)
  (setq v (rdirx:solid-pts ent))
  (min (rdirx:seg-dist p (nth 0 v) (nth 1 v)) (rdirx:seg-dist p (nth 1 v) (nth 2 v))
       (rdirx:seg-dist p (nth 2 v) (nth 3 v)) (rdirx:seg-dist p (nth 3 v) (nth 0 v))))

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

;; Punto WCS -> coordenadas locales del sistema fr (origen ejeX ejeY ejeZ ...).
(defun rdirx:local (p fr / d)
  (setq d (rdirx:v- p (car fr)))
  (list (rdirx:dot d (nth 1 fr)) (rdirx:dot d (nth 2 fr)) (rdirx:dot d (nth 3 fr))))

;; Distancia de un punto WCS al rectangulo REAL (girado) del texto.
(defun rdirx:dist-text (p fr / l dx dy)
  (setq l  (rdirx:local p fr)
        dx (max 0.0 (- (nth 4 fr) (car l)) (- (car l) (nth 5 fr)))
        dy (max 0.0 (- (nth 6 fr) (cadr l)) (- (cadr l) (nth 7 fr))))
  (sqrt (+ (* dx dx) (* dy dy))))

;; ---------- seguimiento de la directriz ----------
;; Estas funciones leen curves, arrows, usedA y tol de c:RDIRX (ambito
;; dinamico de AutoLISP).

;; Flecha (SOLID, o INSERT pequeno) pegada al punto p, o nil.
(defun rdirx:arrow-at (p th / best bd d b)
  (setq bd (* 0.25 th))
  (foreach ar arrows
    (if (and (not (member ar usedA)) (entget ar))
      (progn
        (if (= (cdr (assoc 0 (entget ar))) "SOLID")
          (setq d (rdirx:solid-dist p ar))
          (setq b (rdirx:box (vlax-ename->vla-object ar))
                d (if (and b (< (distance (car b) (cadr b)) (* 4.0 th))) (rdirx:dist-aabb p b) 1e99)))
        (if (<= d bd) (setq bd d best ar)))))
  best)

;; Indices de los tramos no tomados, de esa capa y color, que tocan p.
(defun rdirx:cands (p taken lay col / ci r)
  (setq ci 0)
  (foreach cv curves
    (if (and (not (member ci taken))
             (equal (nth 2 cv) (list lay col))
             (or (<= (distance (car (cadr cv)) p) tol) (<= (distance (last (cadr cv)) p) tol)))
      (setq r (cons ci r)))
    (setq ci (1+ ci)))
  r)

;; Puntos del tramo ci empezando por su extremo mas cercano a p.
(defun rdirx:oriented (ci p / pts)
  (setq pts (cadr (nth ci curves)))
  (if (<= (distance (car pts) p) (distance (last pts) p)) pts (reverse pts)))

;; Alarga la cadena por su final hasta la flecha, una bifurcacion o el fin.
;; Devuelve (cadena tomados flecha).
(defun rdirx:grow-fwd (chain taken lay col th / c n arr)
  (setq n 0)
  (while (and (not (setq arr (rdirx:arrow-at (last chain) th)))
              (< n 10)
              (= (length (setq c (rdirx:cands (last chain) taken lay col))) 1))
    (setq chain (append chain (cdr (rdirx:oriented (car c) (last chain))))
          taken (cons (car c) taken)
          n (1+ n)))
  (list chain taken arr))

;; Alarga la cadena por su principio (lado del texto) solo con tramos que
;; siguen pegados al texto (el subrayado). Devuelve (cadena tomados).
(defun rdirx:grow-back (chain taken lay col tf th / c pts n go)
  (setq n 0 go T)
  (while (and go (< n 3) (= (length (setq c (rdirx:cands (car chain) taken lay col))) 1))
    (setq pts (rdirx:oriented (car c) (car chain)))
    (if (<= (rdirx:dist-text (last pts) tf) (* 4.0 th))
      (setq chain (append (reverse (cdr pts)) chain)
            taken (cons (car c) taken)
            n (1+ n))
      (setq go nil)))
  (list chain taken))

;; Directriz del texto ti empezando por el tramo ci. Prueba los dos sentidos
;; del tramo y se queda con el que llega a una flecha (o, si ninguno, con el
;; que acaba mas lejos del texto). Devuelve (cadena tomados flecha), con la
;; cadena del apoyo (junto al texto) a la punta.
(defun rdirx:build (ti ci / tf th lp pA ra rb best bk)
  (setq tf (cadr (nth ti txts))
        th (caddr (nth ti txts))
        lp (nth 2 (nth ci curves))
        pA (cadr (nth ci curves))
        pA (if (<= (rdirx:dist-text (car pA) tf) (rdirx:dist-text (last pA) tf)) pA (reverse pA))
        ra (rdirx:grow-fwd pA (cons ci usedC) (car lp) (cadr lp) th))
  (if (<= (rdirx:dist-text (last pA) tf) (* 4.0 th))
    (setq rb (rdirx:grow-fwd (reverse pA) (cons ci usedC) (car lp) (cadr lp) th)))
  (setq best ra)
  (if (and rb (> (+ (if (caddr rb) 1e9 0.0) (rdirx:dist-text (last (car rb)) tf))
                 (+ (if (caddr ra) 1e9 0.0) (rdirx:dist-text (last (car ra)) tf))))
    (setq best rb))
  (setq bk (rdirx:grow-back (car best) (cadr best) (car lp) (cadr lp) tf th))
  (list (car bk) (cadr bk) (caddr best)))

;; ---------- comando ----------

(defun c:RDIRX ( / *error* doc oldEcho kw ss i ent typ obj txts curves arrows
                   pairs usedT usedC usedA jobs ti ci r newC tf mf th tol
                   chain arr prev tip lpts a b dog dlen ddir space ml mle sa
                   rot count minTh ux uy)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
        oldEcho (getvar "CMDECHO"))

  (defun *error* (msg)
    (setvar "CMDECHO" oldEcho)
    (vla-EndUndoMark doc)
    (if (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*EXIT*"))
      (princ (strcat "\n[RDIRX] Error: " msg)))
    (princ))

  (initget "Scp Original")
  (if (setq kw (getkword (strcat "\n[RDIRX] Orientacion del texto [Scp/Original] <" *rdirx-orient* ">: ")))
    (setq *rdirx-orient* kw))

  (prompt "\n[RDIRX] Selecciona las directrices explotadas (textos, lineas/polilineas y flechas): ")
  (if (setq ss (ssget "_:L" '((0 . "TEXT,MTEXT,LINE,LWPOLYLINE,POLYLINE,LEADER,SOLID,INSERT"))))
    (progn
      ;; 1. Clasificar: txts = (ent sistema altura), curves = (ent puntos (capa color))
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
           (if (>= (length (setq r (rdirx:pts ent))) 2)
             (setq curves (cons (list ent r (rdirx:props ent)) curves))))
          (T (setq arrows (cons ent arrows)))))
      (setq txts (reverse txts) curves (reverse curves))

      (if (not (and txts curves))
        (princ "\n[RDIRX] Faltan datos: la seleccion debe incluir textos y lineas.")
        (progn
          (vla-StartUndoMark doc)
          (setq tol (max 1e-6 (* 0.05 minTh)))

          ;; 2. Parejas texto <-> tramo por distancia de un extremo al texto
          (setq ti 0)
          (foreach tx txts
            (setq ci 0 tf (cadr tx) th (caddr tx))
            (foreach cv curves
              (setq a (min (rdirx:dist-text (car (cadr cv)) tf)
                           (rdirx:dist-text (last (cadr cv)) tf)))
              (if (<= a (* 4.0 th)) (setq pairs (cons (list a ti ci) pairs)))
              (setq ci (1+ ci)))
            (setq ti (1+ ti)))
          (setq pairs (vl-sort pairs '(lambda (p q) (< (car p) (car q)))))

          ;; 3. Seguir cada directriz, de la pareja mas cercana a la mas lejana
          (foreach pr pairs
            (if (and (not (member (cadr pr) usedT)) (not (member (caddr pr) usedC)))
              (progn
                (setq r    (rdirx:build (cadr pr) (caddr pr))
                      newC (vl-remove-if '(lambda (x) (member x usedC)) (cadr r))
                      usedT (cons (cadr pr) usedT)
                      usedC (cadr r))
                (if (caddr r) (setq usedA (cons (caddr r) usedA)))
                (setq jobs (cons (list (cadr pr) (car r) (caddr r)
                                       (mapcar '(lambda (x) (car (nth x curves))) newC))
                                 jobs)))))
          (setq jobs (reverse jobs) count 0
                ux (rdirx:unit (getvar "UCSXDIR"))
                uy (rdirx:unit (getvar "UCSYDIR")))

          ;; 4. Crear los MLEADER
          (foreach jb jobs
            (setq ent   (car (nth (car jb) txts))
                  tf    (cadr (nth (car jb) txts))
                  th    (caddr (nth (car jb) txts))
                  chain (cadr jb)
                  arr   (caddr jb)
                  prev  (nth (- (length chain) 2) chain))

            ;; llevar la punta al vertice real de la flecha vieja
            (if arr
              (progn
                (setq tip (if (= (cdr (assoc 0 (entget arr))) "SOLID")
                            (car (vl-sort (rdirx:solid-pts arr)
                                          '(lambda (p q) (> (distance p prev) (distance q prev)))))
                            (trans (cdr (assoc 10 (entget arr))) arr 0)))
                (if (> (distance tip prev) (distance (last chain) prev))
                  (setq chain (append (reverse (cdr (reverse chain))) (list tip))))))

            ;; sistema del MLEADER: SCP actual, o el del propio texto
            (setq mf (if (= *rdirx-orient* "Original")
                       (list (car tf) (nth 1 tf) (nth 2 tf) (nth 3 tf))
                       (list (car tf) ux uy (rdirx:unit (rdirx:cross ux uy))))
                  lpts (mapcar '(lambda (p / l) (setq l (rdirx:local p mf)) (list (car l) (cadr l) 0.0))
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
                        dlen (max (* 0.2 th) (- (abs (- (car b) (car a))) (- (nth 5 tf) (nth 4 tf))))
                        ddir (if (> (car b) (car a)) 1.0 -1.0)
                        lpts (reverse (cdr (reverse lpts)))))))

            (setq r  (apply 'append lpts)
                  sa (vlax-make-safearray vlax-vbDouble (cons 0 (1- (length r)))))
            (vlax-safearray-fill sa r)
            (setq obj   (vlax-ename->vla-object ent)
                  space (vlax-ename->vla-object (cdr (assoc 330 (entget ent))))
                  ml    (vl-catch-all-apply 'vla-AddMLeader (list space (vlax-make-variant sa) 0)))
            (if (vl-catch-all-error-p ml)
              (princ (strcat "\n[RDIRX] No se pudo crear una directriz: " (vl-catch-all-error-message ml)))
              (progn
                ;; estilo anotativo: dejarla no anotativa para que la altura sea la real
                (setq mle (vlax-vla-object->ename ml))
                (if (assoc -3 (entget mle '("AcadAnnotative")))
                  (progn
                    (setvar "CMDECHO" 0)
                    (vl-catch-all-apply 'vl-cmdf (list "_.CHPROP" mle "" "_Annotative" "_No" ""))
                    (setvar "CMDECHO" oldEcho)))
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

                ;; llevar el MLEADER del plano XY al sistema elegido
                (setq rot (mapcar '(lambda (k)
                                     (list (nth k (nth 1 mf)) (nth k (nth 2 mf)) (nth k (nth 3 mf)) (nth k (car mf))))
                                  '(0 1 2)))
                (vla-TransformBy ml (vlax-tmatrix (append rot '((0.0 0.0 0.0 1.0)))))

                (entdel ent)
                (foreach c (nth 3 jb) (if (entget c) (entdel c)))
                (if (and arr (entget arr)) (entdel arr))
                (setq count (1+ count)))))

          (vla-EndUndoMark doc)
          (princ (strcat "\n[RDIRX] " (itoa count) " directriz(es) reconstruida(s)"
                         (if (< count (length txts))
                           (strcat "; " (itoa (- (length txts) count)) " texto(s) sin linea cercana, sin tocar.")
                           ".")))))))
  (princ))

(princ "\n[RDIRX] Cargado. Escribe RDIRX para reconstruir directrices explotadas.")
(princ)
