(vl-load-com)

;; ==========================================================
;; ORDENPRES - Reordena las presentaciones (pestanas de layout) del dibujo
;; desde UNA SOLA VENTANA con la lista de todas ellas, sin tener que
;; entrar en cada presentacion ni arrastrar las pestanas una a una.
;;
;; En la ventana:
;;   - Selecciona una o varias presentaciones de la lista (Ctrl/Shift
;;     para seleccionar varias a la vez).
;;   - "Al principio" / "Subir" / "Bajar" / "Al final" las mueven, todas
;;     juntas, conservando su orden relativo.
;;   - "Ordenar A-Z" ordena todas alfabeticamente.
;;   - "Ordenar por numero" ordena teniendo en cuenta los numeros del
;;     nombre (IN-2 antes que IN-10, que el orden alfabetico pondria al
;;     reves).
;;   - "Invertir" da la vuelta al orden completo.
;;   - "Aceptar" aplica el nuevo orden a las pestanas; "Cancelar" deja
;;     todo como estaba.
;;
;; El cambio se aplica de una vez (un solo paso de DESHACER) y no activa
;; ninguna presentacion: no se regeneran ni se abren una a una.
;;
;; Uso: APPLOAD -> carga este archivo -> comando ORDENPRES.
;; ==========================================================

;; ---------- utilidades de listas ----------

(defun ordp:swap (lst a b / va vb i r)
  (setq va (nth a lst) vb (nth b lst) i 0)
  (foreach x lst
    (setq r (cons (cond ((= i a) vb) ((= i b) va) (T x)) r)
          i (1+ i)))
  (reverse r))

(defun ordp:pick (lst idxs)
  (mapcar '(lambda (i) (nth i lst)) idxs))

(defun ordp:without (lst idxs / i r)
  (setq i 0)
  (foreach x lst
    (if (not (member i idxs)) (setq r (cons x r)))
    (setq i (1+ i)))
  (reverse r))

(defun ordp:range (from n / r)
  (repeat n (setq r (cons (+ from (length r)) r)))
  (reverse r))

;; ---------- orden "natural" (IN-2 < IN-10) ----------

(defun ordp:digit-p (c) (wcmatch c "#"))

(defun ordp:natless (a b / la lb i j ca cb na nb res)
  (setq a (strcase a) b (strcase b) la (strlen a) lb (strlen b) i 1 j 1)
  (while (and (null res) (<= i la) (<= j lb))
    (setq ca (substr a i 1) cb (substr b j 1))
    (if (and (ordp:digit-p ca) (ordp:digit-p cb))
      (progn
        (setq na "")
        (while (and (<= i la) (ordp:digit-p (substr a i 1)))
          (setq na (strcat na (substr a i 1)) i (1+ i)))
        (setq nb "")
        (while (and (<= j lb) (ordp:digit-p (substr b j 1)))
          (setq nb (strcat nb (substr b j 1)) j (1+ j)))
        (cond ((< (atof na) (atof nb)) (setq res 'lt))
              ((> (atof na) (atof nb)) (setq res 'gt))))
      (progn
        (cond ((< ca cb) (setq res 'lt))
              ((> ca cb) (setq res 'gt)))
        (setq i (1+ i) j (1+ j)))))
  (cond ((eq res 'lt) T)
        ((eq res 'gt) nil)
        (T (< (- la i) (- lb j)))))

;; ---------- dialogo ----------

(defun ordp:write-dcl (path / f)
  (setq f (open path "w"))
  (foreach ln
    '("ordenpres : dialog {"
      "  label = \"Ordenar presentaciones\";"
      "  : row {"
      "    : list_box { key = \"lista\"; width = 50; height = 26; multiple_select = true; }"
      "    : column {"
      "      : button { key = \"prin\";  label = \"Al principio\";      width = 22; }"
      "      : button { key = \"subir\"; label = \"Subir\";             width = 22; }"
      "      : button { key = \"bajar\"; label = \"Bajar\";             width = 22; }"
      "      : button { key = \"final\"; label = \"Al final\";          width = 22; }"
      "      spacer_1;"
      "      : button { key = \"az\";    label = \"Ordenar A-Z\";       width = 22; }"
      "      : button { key = \"nat\";   label = \"Ordenar por numero\"; width = 22; }"
      "      : button { key = \"inv\";   label = \"Invertir\";          width = 22; }"
      "      spacer;"
      "    }"
      "  }"
      "  : text { key = \"info\"; }"
      "  ok_cancel;"
      "}")
    (write-line ln f))
  (close f))

(defun ordp:refresh ()
  (start_list "lista")
  (mapcar 'add_list *ordp-names*)
  (end_list)
  (if *ordp-sel*
    (set_tile "lista"
      (substr (apply 'strcat (mapcar '(lambda (i) (strcat " " (itoa i))) *ordp-sel*)) 2)))
  (set_tile "info" (strcat (itoa (length *ordp-names*)) " presentaciones. Selecciona y mueve; Aceptar aplica el orden.")))

(defun ordp:act (op / s n k picked newsel)
  (setq s (get_tile "lista")
        *ordp-sel* (if (= s "") nil (vl-sort (read (strcat "(" s ")")) '<))
        n (length *ordp-names*)
        k (length *ordp-sel*))
  (cond
    ((= op "subir")
     (foreach i *ordp-sel*
       (if (and (> i 0) (not (member (1- i) newsel)))
         (setq *ordp-names* (ordp:swap *ordp-names* i (1- i)) newsel (cons (1- i) newsel))
         (setq newsel (cons i newsel))))
     (setq *ordp-sel* (vl-sort newsel '<)))
    ((= op "bajar")
     (foreach i (reverse *ordp-sel*)
       (if (and (< i (1- n)) (not (member (1+ i) newsel)))
         (setq *ordp-names* (ordp:swap *ordp-names* i (1+ i)) newsel (cons (1+ i) newsel))
         (setq newsel (cons i newsel))))
     (setq *ordp-sel* (vl-sort newsel '<)))
    ((and (= op "prin") *ordp-sel*)
     (setq picked (ordp:pick *ordp-names* *ordp-sel*)
           *ordp-names* (append picked (ordp:without *ordp-names* *ordp-sel*))
           *ordp-sel* (ordp:range 0 k)))
    ((and (= op "final") *ordp-sel*)
     (setq picked (ordp:pick *ordp-names* *ordp-sel*)
           *ordp-names* (append (ordp:without *ordp-names* *ordp-sel*) picked)
           *ordp-sel* (ordp:range (- n k) k)))
    ((= op "az")
     (setq *ordp-names* (vl-sort *ordp-names* '(lambda (a b) (< (strcase a) (strcase b))))
           *ordp-sel* nil))
    ((= op "nat")
     (setq *ordp-names* (vl-sort *ordp-names* 'ordp:natless)
           *ordp-sel* nil))
    ((= op "inv")
     (setq *ordp-names* (reverse *ordp-names*)
           *ordp-sel* (mapcar '(lambda (i) (- n 1 i)) (reverse *ordp-sel*)))))
  (ordp:refresh))

;; ---------- comando ----------

(defun c:ORDENPRES ( / doc lays pairs dcl id res i)
  (setq doc  (vla-get-ActiveDocument (vlax-get-acad-object))
        lays (vla-get-Layouts doc))
  (vlax-for l lays
    (if (/= (strcase (vla-get-Name l)) "MODEL")
      (setq pairs (cons (cons (vla-get-TabOrder l) (vla-get-Name l)) pairs))))
  (setq *ordp-names* (mapcar 'cdr (vl-sort pairs '(lambda (a b) (< (car a) (car b)))))
        *ordp-sel* nil)
  (cond
    ((< (length *ordp-names*) 2)
     (princ "\n[ORDENPRES] El dibujo tiene menos de dos presentaciones: no hay nada que ordenar."))
    (T
     (setq dcl (vl-filename-mktemp "ordenpres.dcl"))
     (ordp:write-dcl dcl)
     (setq id (load_dialog dcl))
     (if (not (new_dialog "ordenpres" id))
       (princ "\n[ORDENPRES] No se pudo abrir la ventana.")
       (progn
         (ordp:refresh)
         (foreach k '("prin" "subir" "bajar" "final" "az" "nat" "inv")
           (action_tile k (strcat "(ordp:act \"" k "\")")))
         (action_tile "accept" "(done_dialog 1)")
         (action_tile "cancel" "(done_dialog 0)")
         (setq res (start_dialog))))
     (unload_dialog id)
     (vl-file-delete dcl)
     (if (= res 1)
       (progn
         (vla-StartUndoMark doc)
         (setq i 1)
         (foreach n *ordp-names*
           (vla-put-TabOrder (vla-Item lays n) i)
           (setq i (1+ i)))
         (vla-EndUndoMark doc)
         (princ (strcat "\n[ORDENPRES] Orden aplicado a " (itoa (length *ordp-names*)) " presentaciones.")))
       (princ "\n[ORDENPRES] Cancelado: no se ha cambiado nada."))))
  (setq *ordp-names* nil *ordp-sel* nil)
  (princ))

(princ "\n[ORDENPRES] Cargado. Escribe ORDENPRES para reordenar las presentaciones desde una lista.")
(princ)
