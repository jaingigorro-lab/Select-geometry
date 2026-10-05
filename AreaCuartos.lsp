(vl-load-com)

;; ==========================================================
;; AREACUARTOS - Rotula el nombre y el area (en m2) de cada cuarto.
;;
;; Se pulsa DENTRO de cada cuarto, y el comando detecta solo su
;; contorno (con -BOUNDARY, sin dejar ninguna polilinea en el dibujo),
;; calcula el area y pone un rotulo en el centro del cuarto:
;;
;;                      COCINA
;;                     12.76 m2        (el 2 en superindice)
;;
;; El nombre es opcional (Intro = sin nombre). Se sigue pulsando en
;; otros cuartos hasta dar Intro; al terminar dice cuantos ha rotulado
;; y la suma total.
;;
;;   Pulsar dentro de un cuarto:
;;     - Usa los objetos VISIBLES en pantalla (como BOUNDARY): hay que
;;       ver el cuarto entero, y sus paredes tienen que cerrarlo.
;;     - Si el contorno no se puede detectar (un hueco de puerta sin
;;       cerrar, el cuarto no cabe en pantalla...), el comando lo dice y
;;       pide las ESQUINAS del cuarto a mano, sin dibujar nada: se
;;       pulsa cada esquina (Deshacer quita la ultima) y se da Intro.
;;       Las esquinas tambien se pueden pedir directamente con la
;;       opcion Esquinas.
;;     - El rotulo es texto fijo (no hay polilinea a la que vincularlo).
;;
;;   Polilineas: para cuartos que YA son polilineas cerradas. Se
;;     seleccionan con ventana (todas de golpe) y se puede elegir:
;;       Campo (por defecto) - el area es un CAMPO de AutoCAD vinculado a
;;         la polilinea (como Insertar > Campo > Objeto > Area), asi que
;;         si luego se modifica el cuarto el area se actualiza sola
;;         (REGEN o ACTUALIZARCAMPO / UPDATEFIELD). Cada campo se
;;         comprueba al crearse; si AutoCAD no lo acepta, o muestra un
;;         valor distinto del esperado, se pone texto fijo con el
;;         valor correcto, y se avisa.
;;       Texto - texto fijo, sin vinculo con la polilinea.
;;     Opcionalmente pide el nombre de cada cuarto (resaltandolo).
;;
;;   Unidades: el area siempre se rotula en m2, y se convierte desde las
;;   unidades del dibujo (m, cm o mm). NO hay que configurarlas: se
;;   detectan solas por el tamano del primer cuarto (y se dice cuales
;;   ha detectado). Si alguna vez se equivoca, la opcion Unidades las
;;   fija escribiendo m, cm o mm (o Auto para volver a detectarlas).
;;
;;   Altura del texto: 0.20 m por defecto (0.2, 20 o 200 segun el dibujo
;;   este en m, cm o mm). La opcion Altura la cambia.
;;
;;   Rotulos repetidos: los que ya hubiera dentro de un cuarto (capa
;;   AREAS) se sustituyen por el nuevo, sin duplicarlos. Cada cuarto
;;   (o cada seleccion de polilineas) se deshace con un solo U.
;;
;;   En cuartos en L o con entrantes, el rotulo se coloca en un punto que
;;   cae DENTRO del cuarto, no en el centroide si este queda fuera.
;; ==========================================================

;; --- Parametros ---

(setq *areas-text-m* 0.20)      ; altura de texto por defecto (en metros)
(setq *areas-precision* 2)      ; decimales del area
(setq *areas-layer* "AREAS")    ; capa de los rotulos
(setq *areas-arc-steps* 16)     ; puntos con que se muestrea cada tramo curvo
(setq *areas-unit-forced* nil)  ; unidades elegidas a mano (opcion Unidades); nil = detectar solas
(setq *areas-height-user* nil)  ; altura de texto elegida a mano (unidades del dibujo); nil = automatica

;; Estado de UNA ejecucion del comando (se reinicia al empezar).
(setq *areas-unit* nil)         ; unidades detectadas/fijadas: "m", "cm" o "mm"
(setq *areas-total* 0.0)        ; suma de las areas rotuladas (m2)
(setq *areas-count* 0)          ; cuartos rotulados
(setq *areas-odd* 0)            ; cuartos con una superficie sospechosa
(setq *areas-saved* nil)        ; variables de sistema a restaurar (ver areas-restore-vars)

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
  (setq *areas-unit* nil)
  (princ (strcat "\n[AREACUARTOS] Unidades: " (if *areas-unit-forced* *areas-unit-forced* "Auto (se detectan solas)") "."))
)

;; Unidades que corresponden a un area medida en unidades de dibujo al
;; cuadrado: un cuarto real mide entre ~1 y ~3000 m2, que en metros son
;; 1..3000, en cm2 son >= 10000 y en mm2 son >= 1000000.
(defun areas-unit-from-area (a)
  (cond
    ((< a 3000.0) "m")
    ((< a 1000000.0) "cm")
    (T "mm")
  )
)

;; Area MEDIANA (en unidades de dibujo al cuadrado) de las polilineas
;; cerradas de una seleccion, o nil si no hay ninguna con area.
(defun areas-median-area (ss / i en areas a n)
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
      (nth (/ n 2) areas)
    )
    nil
  )
)

;; Fija las unidades de esta ejecucion (las elegidas a mano, o las
;; detectadas con el area dada la primera vez) y lo dice. Devuelve las
;; unidades.
(defun areas-ensure-unit (rawArea)
  (if (not *areas-unit*)
    (progn
      (setq *areas-unit*
        (if *areas-unit-forced*
          *areas-unit-forced*
          (areas-unit-from-area (if rawArea rawArea 1.0))
        )
      )
      (princ (strcat "\n[AREACUARTOS] Unidades del dibujo: " *areas-unit*
                     (if *areas-unit-forced*
                       " (elegidas con la opcion Unidades)."
                       " (detectadas por el tamano del cuarto; si no son estas, usa la opcion Unidades).")))
    )
  )
  *areas-unit*
)

;; Altura del texto: la elegida a mano, o 0.20 m en las unidades del dibujo.
(defun areas-text-height ()
  (if *areas-height-user* *areas-height-user* (* *areas-text-m* (areas-scale)))
)

;; Opcion Altura: Intro = volver a la altura automatica.
(defun areas-ask-height ()
  (initget 6)
  (setq *areas-height-user*
    (getdist "\n[AREACUARTOS] Altura del texto en unidades del dibujo (0.2 si esta en m, 20 en cm, 200 en mm), o Intro = automatica: "))
  (princ (if *areas-height-user*
           (strcat "\n[AREACUARTOS] Altura del texto: " (rtos *areas-height-user* 2 3) ".")
           "\n[AREACUARTOS] Altura del texto: automatica (0.20 m)."))
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

;; Limpia un nombre para meterlo en un MTEXT: los caracteres con
;; significado especial en MTEXT (\ { } y los < > de los campos) se
;; sustituyen por otros inofensivos.
(defun areas-clean-name (s)
  (vl-string-translate "\\{}<>" "/()()" (vl-string-trim " " s))
)

;; Pide el nombre del cuarto (Intro = sin nombre).
(defun areas-ask-name ()
  (areas-clean-name (getstring T "\n[AREACUARTOS] Nombre del cuarto (Intro = sin nombre): "))
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
    (setq pts (cons (areas-pt2d (vlax-curve-getPointAtParam ent (float i))) pts))
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

;; Area de un poligono de lados rectos (formula del cordon), siempre
;; positiva. Se calcula respecto al primer vertice para no perder
;; precision con coordenadas grandes.
(defun areas-poly-area (pts / o n i p q a)
  (setq o (car pts))
  (setq n (length pts))
  (setq a 0.0 i 0)
  (while (< i n)
    (setq p (nth i pts))
    (setq q (nth (rem (1+ i) n) pts))
    (setq a (+ a (- (* (- (car p) (car o)) (- (cadr q) (cadr o)))
                    (* (- (car q) (car o)) (- (cadr p) (cadr o))))))
    (setq i (1+ i))
  )
  (/ (abs a) 2.0)
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

;; Pone el rotulo de un cuarto ya medido: "pts" es su contorno (lista de
;; puntos 2D), "areaD" su area en unidades de dibujo al cuadrado, "fent"
;; la polilinea a la que vincular el campo (o nil), "name" el nombre (""
;; o nil = sin nombre) y "useField" si se quiere campo en vez de texto
;; fijo. Con nombre: el nombre va arriba y el area debajo, centrados
;; respecto al punto del cuarto; sin nombre, el area sola en el punto.
;; Devuelve (area-m2 tipo-de-rotulo punto), con tipo "campo" o "texto".
(defun areas-place (pts areaD fent name useField height
                    / fac areaM2 pt apt off id vlaObj obj en kind txt)
  (setq fac (areas-m2-factor))
  (setq areaM2 (* areaD fac))
  (setq pt (areas-label-point pts))
  (areas-delete-old pts)
  (setq off (* 0.75 height))
  (setq apt pt)
  (if (and name (/= name ""))
    (progn
      (areas-add-mtext (list (car pt) (+ (cadr pt) off)) name height)
      (setq apt (list (car pt) (- (cadr pt) off)))
    )
  )
  (setq kind "texto")
  (if (and useField fent)
    (progn
      (setq vlaObj (vlax-ename->vla-object fent))
      (setq id (areas-object-id vlaObj))
      (if id
        (progn
          (setq obj (vl-catch-all-apply 'areas-add-mtext
                      (list apt (areas-field-string id fac) height)))
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
    (areas-add-mtext apt (areas-static-string areaM2) height)
  )
  (list areaM2 kind pt)
)

;; Rotula una polilinea cerrada ya existente. nil si no tiene area.
(defun areas-label-room (ent useField height name / areaD pts)
  (setq areaD (vla-get-Area (vlax-ename->vla-object ent)))
  (setq pts (areas-room-points ent))
  (if (or (< areaD 1e-9) (< (length pts) 3))
    nil
    (areas-place pts areaD ent name useField height)
  )
)

;; Anota un cuarto rotulado en las cuentas de la ejecucion y lo cuenta
;; por pantalla (las 12 primeras lineas, para no inundar la linea de
;; ordenes con selecciones grandes).
(defun areas-record (res name)
  (setq *areas-total* (+ *areas-total* (car res)))
  (setq *areas-count* (1+ *areas-count*))
  (if (or (< (car res) 0.3) (> (car res) 3000.0))
    (setq *areas-odd* (1+ *areas-odd*))
  )
  (if (<= *areas-count* 12)
    (princ (strcat "\n  - " (if (and name (/= name "")) (strcat name ": ") "")
                   (rtos (car res) 2 *areas-precision*) " m2 (" (cadr res) ") en ("
                   (rtos (car (caddr res)) 2 2) ", " (rtos (cadr (caddr res)) 2 2) ")"))
  )
)

;; --- Contorno a partir de un punto interior (sin polilinea previa) ---

;; Lanza -BOUNDARY en el punto pt. Es una funcion propia, y NO
;; (vl-catch-all-apply 'command ...), porque AutoCAD no admite COMMAND
;; como funcion a aplicar de forma indirecta ("funcion erronea: COMMAND").
(defun areas-run-boundary (pt)
  (command "_.-BOUNDARY" pt "")
)

;; Devuelve a su valor las variables de sistema que areas-boundary-at
;; cambia. Tambien la llama *error*, por si algo falla a mitad.
(defun areas-restore-vars ( / v)
  (if *areas-saved*
    (progn
      (foreach v *areas-saved*
        (vl-catch-all-apply 'setvar (list (car v) (cadr v)))
      )
      (setq *areas-saved* nil)
    )
  )
)

;; Detecta el contorno del cuarto que rodea al punto "pt" (en UCS) con
;; -BOUNDARY, lee el resultado y BORRA lo que el comando haya creado.
;; Devuelve (puntos area-en-unidades-de-dibujo^2), o nil si no ha
;; podido. Si hay islas (columnas, mobiliario cerrado...) se queda con
;; el contorno exterior, que es el de mayor area. OSMODE se apaga
;; mientras tanto para que el punto no salte a un snap.
(defun areas-boundary-at (pt / hb last0 e news best bestA a pts res)
  ;; HPBOUND decide si BOUNDARY crea polilineas (1) o regiones (0); se
  ;; fuerza a polilinea mientras dura (si esta version no la tiene, se ignora).
  (setq hb (vl-catch-all-apply 'getvar (list "HPBOUND")))
  (if (vl-catch-all-error-p hb) (setq hb nil))
  (setq *areas-saved* (list (list "OSMODE" (getvar "OSMODE"))
                            (list "CMDECHO" (getvar "CMDECHO"))))
  (if hb (setq *areas-saved* (cons (list "HPBOUND" hb) *areas-saved*)))
  (setvar "OSMODE" 0)
  (setvar "CMDECHO" 0)
  (if hb (setvar "HPBOUND" 1))
  (setq last0 (entlast))
  (setq res (vl-catch-all-apply 'areas-run-boundary (list pt)))
  (if (> (getvar "CMDACTIVE") 0) (command))
  (areas-restore-vars)
  ;; Entidades nuevas creadas por el comando.
  (setq news '())
  (setq e (if last0 (entnext last0) (entnext)))
  (while e
    (setq news (cons e news))
    (setq e (entnext e))
  )
  (setq best nil bestA 0.0)
  (foreach e news
    (if (and (= (cdr (assoc 0 (entget e))) "LWPOLYLINE")
             (= 1 (logand 1 (cdr (assoc 70 (entget e))))))
      (progn
        (setq a (vla-get-Area (vlax-ename->vla-object e)))
        (if (> a bestA) (setq best e bestA a))
      )
    )
  )
  (setq pts (if best (areas-room-points best) nil))
  (foreach e news (entdel e))
  (if (and pts (>= (length pts) 3)) (list pts bestA) nil)
)

;; --- Contorno pulsando las esquinas ---

;; Dibuja provisionalmente el contorno que se lleva pulsado.
(defun areas-draw-outline (pts / i)
  (redraw)
  (setq i 0)
  (while (< (1+ i) (length pts))
    (grdraw (nth i pts) (nth (1+ i) pts) 7)
    (setq i (1+ i))
  )
)

;; Pide las esquinas del cuarto una a una. Devuelve la lista de puntos
;; 2D en WCS (vacia si se cancela).
(defun areas-pick-corners ( / pts p done out)
  (setq pts '() done nil)
  (while (not done)
    (initget "Deshacer")
    (setq p
      (if pts
        (getpoint (last pts)
                  (strcat "\n[AREACUARTOS] Esquina " (itoa (1+ (length pts)))
                          " [Deshacer] (Intro = terminar): "))
        (getpoint "\n[AREACUARTOS] Esquina 1 del cuarto (Intro = cancelar): ")
      )
    )
    (cond
      ((not p) (setq done T))
      ((listp p)
        (setq pts (append pts (list p)))
        (areas-draw-outline pts)
      )
      ((= p "Deshacer")
        (if pts (setq pts (reverse (cdr (reverse pts)))))
        (areas-draw-outline pts)
      )
    )
  )
  (redraw)
  (setq out '())
  (foreach p pts (setq out (cons (areas-pt2d (trans p 1 0)) out)))
  (reverse out)
)

;; Rotula un cuarto a partir de las esquinas pulsadas a mano.
(defun areas-do-corners ( / pts a name res)
  (setq pts (areas-pick-corners))
  (cond
    ((< (length pts) 3)
      (princ "\n[AREACUARTOS] Cancelado: hacen falta al menos 3 esquinas.")
    )
    (T
      (setq a (areas-poly-area pts))
      (if (< a 1e-9)
        (princ "\n[AREACUARTOS] Las esquinas no forman una superficie. Cancelado.")
        (progn
          (areas-ensure-unit a)
          (setq name (areas-ask-name))
          (setq res (areas-place pts a nil name nil (areas-text-height)))
          (areas-record res name)
        )
      )
    )
  )
)

;; Rotula el cuarto en el que se ha pulsado: detecta su contorno y, si
;; no puede, pide las esquinas. Cada cuarto es un grupo de deshacer.
(defun areas-do-click (pt doc / b name res)
  (vla-StartUndoMark doc)
  (setq b (areas-boundary-at pt))
  (if b
    (progn
      (areas-ensure-unit (cadr b))
      (setq name (areas-ask-name))
      (setq res (areas-place (car b) (cadr b) nil name nil (areas-text-height)))
      (areas-record res name)
    )
    (progn
      (princ "\n[AREACUARTOS] No se ha podido detectar el contorno de ese cuarto (hueco de puerta sin cerrar, o no se ve entero en pantalla).")
      (princ "\n[AREACUARTOS] Pulsa sus esquinas a mano:")
      (areas-do-corners)
    )
  )
  (vla-EndUndoMark doc)
)

;; --- Cuartos que ya son polilineas ---

(defun areas-run-polylines (doc / kw useField namesYes ss i en ed name res nSkip nBad)
  (initget "Campo Texto")
  (setq kw (getkword "\n[AREACUARTOS] Rotulo [Campo/Texto] <Campo>: "))
  (setq useField (/= kw "Texto"))
  (princ "\n[AREACUARTOS] Selecciona las polilineas cerradas de los cuartos: ")
  (setq ss (ssget '((0 . "LWPOLYLINE"))))
  (if (not ss)
    (princ "\n[AREACUARTOS] No se ha seleccionado ninguna polilinea.")
    (progn
      (initget "Si No")
      (setq namesYes (getkword "\n[AREACUARTOS] Poner nombre a cada cuarto? [Si/No] <No>: "))
      (areas-ensure-unit (areas-median-area ss))
      (vla-StartUndoMark doc)
      (setq nSkip 0 nBad 0 i 0)
      (while (< i (sslength ss))
        (setq en (ssname ss i))
        (setq ed (entget en))
        (if (= 1 (logand 1 (cdr (assoc 70 ed))))
          (progn
            ;; Con nombres, se resalta cada polilinea mientras se pide el suyo.
            (setq name "")
            (if (= namesYes "Si")
              (progn
                (redraw en 3)
                (setq name (areas-ask-name))
                (redraw en 4)
              )
            )
            (setq res (areas-label-room en useField (areas-text-height) name))
            (if res
              (progn
                (areas-record res name)
                (if (and useField (= (cadr res) "texto"))
                  (princ "\n  (aviso: este rotulo no ha podido crearse como campo; es texto fijo y no se actualiza solo)")
                )
              )
              (setq nBad (1+ nBad))
            )
          )
          (setq nSkip (1+ nSkip))
        )
        (setq i (1+ i))
      )
      (vla-EndUndoMark doc)
      (if (> nSkip 0)
        (princ (strcat "\n[AREACUARTOS] " (itoa nSkip) " polilinea(s) abierta(s) omitida(s): cierralas (opcion Cerrar de PEDIT) y repite."))
      )
      (if (> nBad 0)
        (princ (strcat "\n[AREACUARTOS] " (itoa nBad) " polilinea(s) sin area omitida(s)."))
      )
    )
  )
)

;; --- Comando ---

(defun c:AREACUARTOS
  ( / *error* doc p done)

  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (defun *error* (msg)
    (vl-catch-all-apply 'vla-EndUndoMark (list doc))
    (areas-restore-vars)
    (redraw)
    (if (and msg (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\n[AREACUARTOS] Error: " msg))
    )
    (princ)
  )

  (setq *areas-unit* nil *areas-total* 0.0 *areas-count* 0 *areas-odd* 0)
  (areas-ensure-layer *areas-layer*)

  (setq done nil)
  (while (not done)
    (initget "Polilineas Esquinas Altura Unidades")
    (setq p (getpoint "\n[AREACUARTOS] Pulsa DENTRO de un cuarto [Polilineas/Esquinas/Altura/Unidades] <terminar>: "))
    ;; getpoint devuelve un punto (lista), una palabra clave (cadena) o
    ;; nil con Intro; se distingue por tipo antes de comparar palabras.
    (cond
      ((not p) (setq done T))
      ((listp p) (areas-do-click p doc))
      ((= p "Polilineas") (areas-run-polylines doc))
      ((= p "Esquinas")
        (vla-StartUndoMark doc)
        (areas-do-corners)
        (vla-EndUndoMark doc)
      )
      ((= p "Altura") (areas-ask-height))
      ((= p "Unidades") (areas-ask-units))
    )
  )

  (if (> *areas-count* 0)
    (progn
      (princ (strcat "\n[AREACUARTOS] " (itoa *areas-count*) " cuarto(s) rotulado(s). Superficie total: "
                     (rtos *areas-total* 2 *areas-precision*) " m2."))
      (if (> *areas-odd* 0)
        (princ (strcat "\n[AREACUARTOS] Aviso: " (itoa *areas-odd*) " cuarto(s) con una superficie fuera de lo normal"
                       " (menos de 0.3 o mas de 3000 m2). Si las areas no cuadran, usa la opcion Unidades"
                       " para indicar si el dibujo esta en m, cm o mm."))
      )
    )
    (princ "\n[AREACUARTOS] No se ha rotulado ningun cuarto.")
  )
  (princ)
)

(princ "\n[AREACUARTOS] Cargado. Escribe AREACUARTOS y pulsa dentro de cada cuarto.")
(princ)
