(vl-load-com)

;; ==========================================================
;; AREACUARTOS - Rotula automaticamente el area (en m2) de cada cuarto.
;;
;; Selecciona las polilineas cerradas que forman los cuartos y el
;; comando pone, en el centro de cada una, un rotulo "12.76 m2" (con
;; el 2 en superindice). Al terminar, dice cuantos cuartos ha
;; rotulado y la suma total.
;;
;;   Rotulo:
;;     Campo (por defecto) - el texto es un CAMPO de AutoCAD vinculado a
;;        la polilinea (el mismo que se crea a mano en Insertar > Campo >
;;        Objeto > Area), asi que si luego se modifica el cuarto el area
;;        se actualiza sola (con REGEN o ACTUALIZARCAMPO / UPDATEFIELD).
;;        Cada campo se comprueba al crearse; si AutoCAD no lo acepta,
;;        o muestra un valor distinto del esperado, se pone en su lugar
;;        texto fijo con el valor correcto, y se avisa.
;;     Texto - texto fijo, sin vinculo con la polilinea.
;;
;;   Unidades: el area siempre se rotula en m2, y se convierte desde las
;;   unidades del dibujo (m, cm o mm). NO hay que configurarlas: se
;;   detectan solas por el tamano de los cuartos seleccionados (y se
;;   dice cuales ha detectado). Si alguna vez se equivoca, la opcion
;;   Unidades permite fijarlas escribiendo m, cm o mm (o Auto para
;;   volver a detectarlas). Con el dibujo en metros no hay conversion.
;;
;;   Vuelve a ejecutarlo cuando quieras: los rotulos que ya hubiera
;;   dentro de cada cuarto (en la capa AREAS) se sustituyen por el
;;   nuevo, sin duplicarlos. Todo el comando se deshace con un solo U.
;;
;;   Solo trabaja con LWPOLYLINE cerradas (las que crea PLINE / RECTANG
;;   / BOUNDARY); las abiertas se omiten y se avisa. Si el cuarto es
;;   en L o con entrantes, el rotulo se coloca en un punto que cae
;;   DENTRO del cuarto, no en el centroide si este queda fuera.
;;
;;   Uso:
;;     1. Ejecutar AREACUARTOS.
;;     2. Elegir Campo / Texto (Intro = Campo).
;;     3. Seleccionar con ventana las polilineas de los cuartos.
;;     4. Intro para aceptar la altura de texto por defecto (0.20 m).
;; ==========================================================

;; --- Parametros ---

(setq *areas-text-m* 0.20)      ; altura de texto por defecto (en metros)
(setq *areas-precision* 2)      ; decimales del area
(setq *areas-layer* "AREAS")    ; capa de los rotulos
(setq *areas-arc-steps* 16)     ; puntos con que se muestrea cada tramo curvo
(setq *areas-unit* "m")         ; unidades con las que se esta trabajando: "m", "cm" o "mm"
(setq *areas-unit-forced* nil)  ; unidades elegidas a mano (opcion Unidades); nil = detectar solas

;; --- Utilidades ---

;; Unidades del dibujo -> factor para pasar el AREA a m2.
(defun areas-m2-factor ()
  (cond
    ((= *areas-unit* "mm") 0.000001)
    ((= *areas-unit* "cm") 0.0001)
    (T 1.0)
  )
)

;; Unidades de dibujo por metro (para la altura de texto por defecto).
(defun areas-scale ()
  (cond
    ((= *areas-unit* "mm") 1000.0)
    ((= *areas-unit* "cm") 100.0)
    (T 1.0)
  )
)

;; Interpreta lo que el usuario escribe como unidades: devuelve "m",
;; "cm", "mm" o "auto", o nil si no lo entiende. Se lee como TEXTO
;; libre (no con palabras clave de initget) porque "m", "cm" y "mm"
;; empiezan igual y AutoCAD puede darlas por ambiguas.
(defun areas-parse-unit (s / v)
  (setq v (strcase (vl-string-trim " " s) T))
  (cond
    ((or (= v "m") (= v "metro") (= v "metros") (= v "1")) "m")
    ((or (= v "cm") (= v "centimetro") (= v "centimetros") (= v "2")) "cm")
    ((or (= v "mm") (= v "milimetro") (= v "milimetros") (= v "3")) "mm")
    ((or (= v "") (= v "a") (= v "auto") (= v "automatico") (= v "automaticas") (= v "4")) "auto")
    (T nil)
  )
)

;; Pregunta las unidades del dibujo (opcion Unidades). "Auto" (o Intro
;; sobre un valor ya automatico) deja que se detecten solas por el
;; tamano de los cuartos, que es lo normal: no se fia de INSUNITS
;; porque las plantillas lo dejan en milimetros aunque se dibuje en
;; metros.
(defun areas-ask-units ( / s u)
  (setq u nil)
  (while (not u)
    (setq s (getstring (strcat "\n[AREACUARTOS] Unidades del dibujo: m, cm, mm o Auto <"
                               (if *areas-unit-forced* *areas-unit-forced* "Auto") ">: ")))
    (setq u (if (= s "")
              (if *areas-unit-forced* *areas-unit-forced* "auto")
              (areas-parse-unit s)))
    (if (not u)
      (princ "\n[AREACUARTOS] No entiendo esa respuesta: escribe m, cm, mm o Auto.")
    )
  )
  (setq *areas-unit-forced* (if (= u "auto") nil u))
)

;; Detecta las unidades del dibujo por la superficie MEDIANA de las
;; polilineas cerradas seleccionadas (area en unidades del dibujo al
;; cuadrado): un cuarto real mide entre ~1 y ~3000 m2, que en metros
;; son 1..3000, en cm2 son >= 10000 y en mm2 son >= 1000000.
(defun areas-detect-unit (ss / i en areas a n med)
  (setq areas '() i 0)
  (while (< i (sslength ss))
    (setq en (ssname ss i))
    (if (= 1 (logand 1 (cdr (assoc 70 (entget en)))))
      (progn
        (setq a (vla-get-Area (vlax-ename->vla-object en)))
        (if (> a 1e-9) (setq areas (cons a areas)))
      )
    )
    (setq i (1+ i))
  )
  (if areas
    (progn
      (setq areas (vl-sort areas '<))
      (setq n (length areas))
      (setq med (nth (/ n 2) areas))
      (cond
        ((< med 3000.0) "m")
        ((< med 1000000.0) "cm")
        (T "mm")
      )
    )
    "m"
  )
)

;; Crea la capa "name" si no existe.
(defun areas-ensure-layer (name)
  (if (not (tblsearch "LAYER" name))
    (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLayerTableRecord")
                   (cons 2 name) '(70 . 0) '(62 . 7) '(6 . "Continuous")))
  )
  name
)

(defun areas-pt2d (p) (list (car p) (cadr p)))

;; Puntos 2D (en WCS) del contorno de una LWPOLYLINE, en orden; los
;; tramos con bulge (arco) se muestrean con *areas-arc-steps* puntos.
;; Los puntos se piden a la propia curva (vlax-curve), no al DXF, para
;; que salgan en WCS aunque la polilinea tenga otro plano de trabajo.
(defun areas-room-points (ent / n bulges i j pts d)
  (setq n 0)
  (setq bulges '())
  (foreach d (entget ent)
    (cond
      ((= (car d) 10) (setq n (1+ n)) (setq bulges (cons 0.0 bulges)))
      ((= (car d) 42) (setq bulges (cons (cdr d) (cdr bulges))))
    )
  )
  (setq bulges (reverse bulges))
  (setq pts '())
  (setq i 0)
  (while (< i n)
    (setq pts (cons (areas-pt2d (vlax-curve-getPointAtParam ent i)) pts))
    (if (> (abs (nth i bulges)) 1e-9)
      (progn
        (setq j 1)
        (while (< j *areas-arc-steps*)
          (setq pts (cons (areas-pt2d (vlax-curve-getPointAtParam ent
                            (+ i (/ (float j) *areas-arc-steps*)))) pts))
          (setq j (1+ j))
        )
      )
    )
    (setq i (1+ i))
  )
  (reverse pts)
)

;; Centroide de un poligono (formula del cordon). Se calcula respecto al
;; primer vertice para no perder precision con coordenadas grandes.
;; nil si el poligono no tiene area.
(defun areas-centroid (pts / o n i p q cr a cx cy)
  (setq o (car pts))
  (setq n (length pts))
  (setq a 0.0 cx 0.0 cy 0.0 i 0)
  (while (< i n)
    (setq p (nth i pts))
    (setq q (nth (rem (1+ i) n) pts))
    (setq cr (- (* (- (car p) (car o)) (- (cadr q) (cadr o)))
                (* (- (car q) (car o)) (- (cadr p) (cadr o)))))
    (setq a (+ a cr))
    (setq cx (+ cx (* (+ (- (car p) (car o)) (- (car q) (car o))) cr)))
    (setq cy (+ cy (* (+ (- (cadr p) (cadr o)) (- (cadr q) (cadr o))) cr)))
    (setq i (1+ i))
  )
  (if (< (abs a) 1e-12)
    nil
    (list (+ (car o) (/ cx (* 3.0 a))) (+ (cadr o) (/ cy (* 3.0 a))))
  )
)

;; True si el punto cae dentro del poligono (regla par-impar).
(defun areas-inside (pt pts / n i p q x y inside)
  (setq x (car pt) y (cadr pt))
  (setq n (length pts) i 0 inside nil)
  (while (< i n)
    (setq p (nth i pts))
    (setq q (nth (rem (1+ i) n) pts))
    (if (and (/= (> (cadr p) y) (> (cadr q) y))
             (< x (+ (car p) (/ (* (- y (cadr p)) (- (car q) (car p)))
                                (- (cadr q) (cadr p))))))
      (setq inside (not inside))
    )
    (setq i (1+ i))
  )
  inside
)

;; Punto donde poner el rotulo: el centroide si cae dentro del cuarto;
;; si no (cuartos en L, en U...), el centro del tramo interior mas largo
;; de la horizontal que pasa por el centroide; y, en ultimo extremo, el
;; centro del rectangulo envolvente.
(defun areas-label-point (pts / c y n i p q xs x best bestLen a b)
  (setq c (areas-centroid pts))
  (if (and c (areas-inside c pts))
    c
    (progn
      (setq y (if c (cadr c) (cadr (car pts))))
      (setq n (length pts) i 0 xs '())
      (while (< i n)
        (setq p (nth i pts))
        (setq q (nth (rem (1+ i) n) pts))
        (if (/= (> (cadr p) y) (> (cadr q) y))
          (setq xs (cons (+ (car p) (/ (* (- y (cadr p)) (- (car q) (car p)))
                                        (- (cadr q) (cadr p)))) xs))
        )
        (setq i (1+ i))
      )
      (setq xs (vl-sort xs '<))
      (setq best nil bestLen -1.0 i 0)
      (while (< (1+ i) (length xs))
        (setq a (nth i xs) b (nth (1+ i) xs))
        (if (> (- b a) bestLen) (setq bestLen (- b a) best (list (/ (+ a b) 2.0) y)))
        (setq i (+ i 2))
      )
      (if best
        best
        (list (/ (+ (apply 'min (mapcar 'car pts)) (apply 'max (mapcar 'car pts))) 2.0)
              (/ (+ (apply 'min (mapcar 'cadr pts)) (apply 'max (mapcar 'cadr pts))) 2.0))
      )
    )
  )
)

;; --- Rotulos ---

;; Cadena de ObjectID que AutoCAD usa dentro de los campos, o nil.
(defun areas-object-id (vlaObj / util id)
  (setq util (vla-get-Utility (vla-get-ActiveDocument (vlax-get-acad-object))))
  (setq id (vl-catch-all-apply 'vla-GetObjectIdString (list util vlaObj :vlax-false)))
  (if (vl-catch-all-error-p id) nil id)
)

;; Texto de un campo "Area de este objeto" en m2, seguido de " m2" (con
;; el 2 en superindice, via \U+00B2 para no meter caracteres no ASCII
;; en el archivo). El factor de conversion solo se anade si hace falta.
(defun areas-field-string (id fac)
  (strcat "%<\\AcObjProp Object(%<\\_ObjId " id ">%).Area \\f \"%lu2%pr"
          (itoa *areas-precision*)
          (if (/= fac 1.0) (strcat "%ct8[" (rtos fac 2 8) "]") "")
          "\">%"
          " m\\U+00B2")
)

;; Texto fijo "12.76 m2".
(defun areas-static-string (areaM2)
  (strcat (rtos areaM2 2 *areas-precision*) " m\\U+00B2")
)

;; Crea un MTEXT centrado en pt, en la capa de rotulos, con "str" como
;; contenido (que puede llevar codigos de campo). Devuelve el objeto.
(defun areas-add-mtext (pt str height / ms obj)
  (setq ms (vla-get-ModelSpace (vla-get-ActiveDocument (vlax-get-acad-object))))
  (setq obj (vla-AddMText ms (vlax-3d-point (list (car pt) (cadr pt) 0.0)) 0.0 str))
  (vla-put-Height obj height)
  (vla-put-AttachmentPoint obj 5)                      ; centro-medio
  (vla-put-InsertionPoint obj (vlax-3d-point (list (car pt) (cadr pt) 0.0)))
  (vla-put-Layer obj *areas-layer*)
  obj
)

;; True si el MTEXT "ent" lleva un campo (diccionario ACAD_FIELD).
(defun areas-has-field (ent / xd)
  (setq xd (cdr (assoc 360 (entget ent))))
  (and xd (dictsearch xd "ACAD_FIELD") T)
)

;; Texto que muestra ahora el MTEXT (el valor ya evaluado del campo).
(defun areas-shown-text (ent)
  (cdr (assoc 1 (entget ent)))
)

;; Borra los rotulos de la capa AREAS cuyo punto de insercion cae dentro
;; del poligono, y devuelve cuantos ha borrado.
(defun areas-delete-old (pts / ss i en ip n)
  (setq n 0)
  (setq ss (ssget "_X" (list '(0 . "MTEXT") (cons 8 *areas-layer*) '(410 . "Model"))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq en (ssname ss i))
        (setq ip (cdr (assoc 10 (entget en))))
        (if (and ip (areas-inside ip pts))
          (progn (entdel en) (setq n (1+ n)))
        )
        (setq i (1+ i))
      )
    )
  )
  n
)

;; Rotula un cuarto. Devuelve (area-m2 tipo-de-rotulo-creado punto), con
;; tipo "campo" o "texto", o nil si no se ha podido (area nula).
(defun areas-label-room (ent useField height / vlaObj areaM2 pts pt id fac obj en kind txt)
  (setq vlaObj (vlax-ename->vla-object ent))
  (setq fac (areas-m2-factor))
  (setq areaM2 (* (vla-get-Area vlaObj) fac))
  (setq pts (areas-room-points ent))
  (if (or (< areaM2 1e-9) (< (length pts) 3))
    nil
    (progn
      (setq pt (areas-label-point pts))
      (areas-delete-old pts)
      (setq kind "texto")
      (if useField
        (progn
          (setq id (areas-object-id vlaObj))
          (if id
            (progn
              (setq obj (vl-catch-all-apply 'areas-add-mtext
                          (list pt (areas-field-string id fac) height)))
              (if (vl-catch-all-error-p obj)
                (setq obj nil)
              )
              (if obj
                (progn
                  (setq en (vlax-vla-object->ename obj))
                  (setq txt (areas-shown-text en))
                  (setq txt (if txt (vl-string-subst "." "," txt) ""))
                  (if (and (areas-has-field en)
                           (vl-string-search (rtos areaM2 2 *areas-precision*) txt))
                    (setq kind "campo")
                    ;; El campo no se ha creado, o no muestra lo esperado:
                    ;; se descarta y se pone texto fijo con el valor bueno.
                    (progn (entdel en) (setq obj nil))
                  )
                )
              )
            )
          )
        )
      )
      (if (/= kind "campo")
        (areas-add-mtext pt (areas-static-string areaM2) height)
      )
      (list areaM2 kind pt)
    )
  )
)

;; --- Comando ---

(defun c:AREACUARTOS
  ( / *error* doc k kw done useField h ss i en ed res total nField nText nSkip nBad nOdd nShown)

  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (defun *error* (msg)
    (vl-catch-all-apply 'vla-EndUndoMark (list doc))
    (if (and msg (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\n[AREACUARTOS] Error: " msg))
    )
    (princ)
  )

  ;; Tipo de rotulo (y opcion de fijar las unidades a mano).
  (setq done nil)
  (while (not done)
    (initget "Campo Texto Unidades")
    (setq kw (getkword "\n[AREACUARTOS] Rotulo [Campo/Texto/Unidades] <Campo>: "))
    (cond
      ((= kw "Unidades") (areas-ask-units))
      ((= kw "Texto") (setq useField nil done T))
      (T (setq useField T done T))
    )
  )

  (princ "\n[AREACUARTOS] Selecciona las polilineas cerradas de los cuartos: ")
  (setq ss (ssget '((0 . "LWPOLYLINE"))))
  (if (not ss)
    (princ "\n[AREACUARTOS] No se ha seleccionado ninguna polilinea.")
    (progn
      ;; Unidades: las elegidas a mano o, si no, las detectadas por el
      ;; tamano de los cuartos. Se dice cuales son para que se vea.
      (setq *areas-unit* (if *areas-unit-forced* *areas-unit-forced* (areas-detect-unit ss)))
      (princ (strcat "\n[AREACUARTOS] Unidades del dibujo: " *areas-unit*
                     (if *areas-unit-forced*
                       " (elegidas con la opcion Unidades)."
                       " (detectadas por el tamano de los cuartos; si no son estas, usa la opcion Unidades).")))

      ;; Altura del texto (la ultima usada pasa a ser la siguiente por defecto).
      (setq k (areas-scale))
      (initget 6)
      (setq h (getdist (strcat "\n[AREACUARTOS] Altura del texto <" (rtos (* *areas-text-m* k) 2 3) ">: ")))
      (if (not h) (setq h (* *areas-text-m* k)))
      (setq *areas-text-m* (/ h k))

      (areas-ensure-layer *areas-layer*)
      (vla-StartUndoMark doc)
      (setq total 0.0 nField 0 nText 0 nSkip 0 nBad 0 nOdd 0 nShown 0 i 0)
      (while (< i (sslength ss))
        (setq en (ssname ss i))
        (setq ed (entget en))
        (if (= 1 (logand 1 (cdr (assoc 70 ed))))
          (progn
            (setq res (areas-label-room en useField h))
            (cond
              ((not res) (setq nBad (1+ nBad)))
              (T
                (setq total (+ total (car res)))
                (if (= (cadr res) "campo") (setq nField (1+ nField)) (setq nText (1+ nText)))
                (if (or (< (car res) 0.3) (> (car res) 3000.0)) (setq nOdd (1+ nOdd)))
                ;; Una linea por cuarto (los 10 primeros) para ver donde y que se ha puesto.
                (if (< nShown 10)
                  (progn
                    (setq nShown (1+ nShown))
                    (princ (strcat "\n  - " (rtos (car res) 2 *areas-precision*) " m2 (" (cadr res)
                                   ") en (" (rtos (car (caddr res)) 2 2) ", " (rtos (cadr (caddr res)) 2 2) ")"))
                  )
                )
              )
            )
          )
          (setq nSkip (1+ nSkip))
        )
        (setq i (1+ i))
      )
      (vla-EndUndoMark doc)
      (princ (strcat "\n[AREACUARTOS] " (itoa (+ nField nText)) " cuarto(s) rotulado(s)"
                     (if (> nField 0) (strcat ", " (itoa nField) " con campo") "")
                     (if (> nText 0) (strcat ", " (itoa nText) " con texto fijo") "")
                     ". Superficie total: " (rtos total 2 *areas-precision*) " m2."))
      (if (and useField (> nText 0))
        (princ "\n[AREACUARTOS] Aviso: algun rotulo no ha podido crearse como campo; se ha puesto texto fijo (no se actualiza solo).")
      )
      (if (> nSkip 0)
        (princ (strcat "\n[AREACUARTOS] " (itoa nSkip) " polilinea(s) abierta(s) omitida(s): cierralas (opcion Cerrar de PEDIT) y repite."))
      )
      (if (> nBad 0)
        (princ (strcat "\n[AREACUARTOS] " (itoa nBad) " polilinea(s) sin area omitida(s)."))
      )
      (if (> nOdd 0)
        (princ (strcat "\n[AREACUARTOS] Aviso: " (itoa nOdd) " cuarto(s) con una superficie fuera de lo normal"
                       " (menos de 0.3 o mas de 3000 m2). Si las areas no cuadran, usa la opcion Unidades"
                       " para indicar si el dibujo esta en m, cm o mm."))
      )
    )
  )
  (princ)
)

(princ "\n[AREACUARTOS] Cargado. Escribe AREACUARTOS para rotular el area de cada cuarto.")
(princ)
