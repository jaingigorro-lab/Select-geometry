(vl-load-com)

;; ==========================================================
;; CONDUCTOS - Herramientas de trazado de conductos de climatizacion.
;;
;; CONDUCTO - Traza un recorrido de conducto (circular o rectangular)
;;   a doble linea y a escala real. En cada cambio de direccion NO se
;;   deja simplemente una esquina redondeada o mitrada: se inserta un
;;   BLOQUE de codo normalizado (con atributos DIAM/ANCHO, ANG y TIPO),
;;   al estilo de una pieza de catalogo -para poder contarlos despues
;;   en una lista de materiales, no solo dibujarlos-:
;;     - Circular: codo curvo con radio 1.5 x diametro (SMACNA).
;;     - Rectangular: codo a escuadra (90), sin radio.
;;   El bloque se crea UNA vez por cada combinacion de tipo+dimension+
;;   angulo que aparezca en el dibujo (se reutiliza si ya existe), y
;;   se inserta orientado y, si el giro es hacia el otro lado, espejado
;;   -no hace falta un bloque distinto para cada mano-. Los tramos
;;   rectos de pared se generan por separado, ya recortados para
;;   encajar exactamente con cada codo. Se avisa (sin bloquear el
;;   dibujo) si el angulo de un codo no es uno de los normalizados
;;   habituales.
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
;;     4. El comando genera los tramos rectos de pared y los bloques
;;        de codo en cada vertice, y conserva la polilinea de eje
;;        central trazada (sin redondear) como referencia, en gris y
;;        con linea de trazo-punto "CENTER".
;;
;; CONDUCTORAMAL - Inserta una union en T (un ramal) o en cruz (dos
;;   ramales opuestos) sobre un conducto principal YA EXISTENTE
;;   (trazado con CONDUCTO, o cualquier par de lineas/polilineas
;;   paralelas que representen sus dos paredes). El conducto principal
;;   NO se modifica: solo se lee para saber su ancho/diametro y por
;;   donde pasa. Cada ramal se traza con su propio tipo y dimension, y
;;   sus dos paredes se recortan automaticamente justo donde alcanzan
;;   la pared del conducto principal mas cercana a el. (Esta union no
;;   se genera todavia como pieza/bloque con atributos, solo como
;;   geometria -a diferencia de los codos de CONDUCTO-.)
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

;; Longitud de cada "pata" del codo a escuadra rectangular = este
;; factor x el ancho del conducto. No hay una formula fisica unica
;; para esto (a diferencia del radio circular): es solo el tamano que
;; se le da al bloque de la pieza para que tenga cuerpo visible y se
;; pueda etiquetar/contar; ajustalo si tu taller usa otra medida.
(setq *conducto-rect-elbow-leg-factor* 1.0)

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

;; Componente Z de v1 x v2, para dos vectores 2D -su signo dice si hay
;; que girar a la izquierda (positivo) o a la derecha (negativo) de v1
;; a v2.
(defun cross-2d (v1 v2)
  (- (* (car v1) (cadr v2)) (* (cadr v1) (car v2)))
)

;; Convierte un numero en un fragmento de texto valido para un nombre
;; de bloque (sin el punto decimal, que no esta permitido).
(defun num-tag (x)
  (vl-string-subst "_" "." (rtos x 2 1))
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
;; (practicamente colineales).
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

;; Como make-polyline, pero a partir de una lista de (punto . bulge)
;; -el bulge de un vertice define el arco (si no es 0) del tramo que
;; va de ESE vertice al siguiente-. Devuelve su ename.
(defun make-polyline-b (ptBulges / data pb)
  (setq data (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") '(100 . "AcDbPolyline")
                    (cons 90 (length ptBulges)) '(70 . 0)))
  (foreach pb ptBulges
    (setq data (append data (list (cons 10 (list (car (car pb)) (cadr (car pb)))))))
    (if (/= (cdr pb) 0.0)
      (setq data (append data (list (cons 42 (cdr pb)))))
    )
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
;; dibujo, cargandolo de acad.lin si hace falta -con el metodo
;; AcadLineTypes.Load via ActiveX, no con el comando -LINETYPE, para no
;; depender en absoluto de la linea de comandos (ni de un posible
;; cuadro de dialogo de seleccion de archivo). Devuelve T si al final
;; esta disponible (ya lo estuviera, o se haya podido cargar).
(defun ensure-center-linetype ( / doc lts ltfile)
  (if (not (tblsearch "LTYPE" "CENTER"))
    (progn
      (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
      (setq lts (vla-get-Linetypes doc))
      ;; findfile busca "acad.lin" en las rutas de soporte de AutoCAD
      ;; y devuelve la ruta completa -pasarle solo "acad.lin" a
      ;; vla-Load, sin ruta, puede no encontrarlo segun la carpeta de
      ;; trabajo actual; con la ruta completa no depende de eso. Si
      ;; findfile no lo encuentra, se prueba tal cual como ultimo
      ;; recurso (y si tampoco existe "acadiso.lin", que en algunas
      ;; plantillas tiene tambien CENTER).
      (setq ltfile (findfile "acad.lin"))
      (vl-catch-all-apply 'vla-Load (list lts "CENTER" (if ltfile ltfile "acad.lin")))
      (if (not (tblsearch "LTYPE" "CENTER"))
        (progn
          (setq ltfile (findfile "acadiso.lin"))
          (if ltfile (vl-catch-all-apply 'vla-Load (list lts "CENTER" ltfile)))
        )
      )
    )
  )
  (tblsearch "LTYPE" "CENTER")
)

;; Marca una entidad como "linea de eje": gris (color ACI 8) y linea de
;; trazo-punto "CENTER" si se ha podido cargar, con una escala de linea
;; propia (parametro opcional "scale") -sin esto, si LTSCALE/CELTSCALE
;; del dibujo son grandes respecto al tamano real del conducto, el
;; patron de trazo-punto puede no llegar a verse nunca (un solo trazo
;; largo sin huecos visibles), aunque el tipo de linea este bien
;; puesto-. Informa por pantalla de si algun ajuste no ha surtido
;; efecto.
(defun mark-as-axis (ent scale / obj ltRes colRes lsRes)
  (setq obj (vlax-ename->vla-object ent))
  (if (ensure-center-linetype)
    (progn
      (setq ltRes (vl-catch-all-apply 'vla-put-Linetype (list obj "CENTER")))
      (if (vl-catch-all-error-p ltRes)
        (princ (strcat "\n[CONDUCTOS] Aviso: no se ha podido poner la linea CENTER al eje ("
                       (vl-catch-all-error-message ltRes) ")."))
      )
    )
    (princ "\n[CONDUCTOS] Aviso: no se ha podido cargar el tipo de linea CENTER; el eje se queda en linea continua.")
  )
  (setq colRes (vl-catch-all-apply 'vla-put-Color (list obj 8)))
  (if (vl-catch-all-error-p colRes)
    (princ (strcat "\n[CONDUCTOS] Aviso: no se ha podido poner el eje en gris ("
                   (vl-catch-all-error-message colRes) ")."))
  )
  (if (and scale (> scale 0.0))
    (progn
      (setq lsRes (vl-catch-all-apply 'vla-put-LinetypeScale (list obj scale)))
      (if (vl-catch-all-error-p lsRes)
        (princ (strcat "\n[CONDUCTOS] Aviso: no se ha podido ajustar la escala de linea del eje ("
                       (vl-catch-all-error-message lsRes) ")."))
      )
    )
  )
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
;; que pasa por p2 con direccion dir2 (rectas infinitas, en angulos).
;; nil si son paralelas.
(defun line-intersect (p1 dir1 p2 dir2)
  (inters p1 (polar p1 dir1 1.0) p2 (polar p2 dir2 1.0) nil)
)

;; --- Bloques de codo normalizado (piezas con atributos) ---
;;
;; Cada bloque se construye en un sistema LOCAL propio: se entra por
;; el punto de insercion (0,0,0) en direccion +X, y el codo gira hacia
;; la IZQUIERDA "ang" grados. Los giros hacia la derecha se consiguen
;; espejando el bloque al insertarlo (YScale = -1, ver insert-elbow),
;; no creando un bloque distinto para cada mano.

(defun elbow-block-name (tipo dim ang)
  (strcat "CODO_" (if (= tipo "Circular") "CIRC" "RECT") "_D" (num-tag dim) "_A" (num-tag ang))
)

;; True si el bloque "name" existe Y tiene contenido real (al menos
;; una entidad dentro). No basta con que el NOMBRE ya exista en la
;; tabla de bloques: un intento anterior fallido (a media creacion)
;; puede haber dejado una definicion vacia con ese mismo nombre, que
;; se reutilizaria para siempre -insertando un codo invisible, sin
;; geometria- si solo se comprobara con tblsearch.
(defun block-has-content (name / ent obj cnt)
  (setq ent (tblobjname "BLOCK" name))
  (if (not ent)
    nil
    (progn
      (setq obj (vl-catch-all-apply 'vlax-ename->vla-object (list ent)))
      (if (vl-catch-all-error-p obj)
        nil
        (progn
          (setq cnt (vl-catch-all-apply 'vla-get-Count (list obj)))
          (and (not (vl-catch-all-error-p cnt)) (> cnt 0))
        )
      )
    )
  )
)

;; Construye la definicion de bloque "name" a partir de una lista de
;; entidades YA CREADAS en el espacio modelo (via entmake, en el
;; sistema local propio del bloque, alrededor del origen), usando el
;; comando -BLOCK (sin dialogo) -el camino mas clasico y probado en
;; AutoLISP para crear un bloque a partir de geometria ya dibujada, en
;; vez de construirlo entidad a entidad con metodos ActiveX (vla-Add,
;; vla-AddArc...) que no se han podido verificar-. Limpia cualquier
;; entidad que quede suelta despues (tanto si el bloque se creo bien
;; como si DELOBJ dejaba copias sin borrar). Devuelve "name" si el
;; bloque quedo creado, o nil si no.
(defun build-block-from-entities (name ents labels / ss e i failMsg existed)
  (setq failMsg "")
  (setq i 0)
  (foreach e ents
    (if (not e) (setq failMsg (strcat failMsg (nth i labels) " ")))
    (setq i (1+ i))
  )
  (if (/= failMsg "")
    (progn
      (princ (strcat "\n[CONDUCTO] Aviso: fallo al crear la geometria del bloque \"" name "\" (" failMsg ")."))
      (foreach e ents (if (and e (entget e)) (entdel e)))
      nil
    )
    (progn
      (setq ss (ssadd))
      (foreach e ents (setq ss (ssadd e ss)))
      ;; Si el nombre de bloque YA existe (de un intento anterior en
      ;; este mismo dibujo), -BLOCK pregunta "Desea redefinirlo?
      ;; [Si/No]" antes de pedir el punto base -y si no se cuenta con
      ;; esa pregunta, el punto base (0,0,0) se cuela como respuesta a
      ;; ella y el comando se cancela ("Si o No.")-. Se contesta a esa
      ;; pregunta SOLO cuando existe, para no desajustar la secuencia
      ;; de prompts cuando el bloque es nuevo. Se usa "_Yes" -la
      ;; palabra clave CANONICA en ingles, con el prefijo "_"- para que
      ;; AutoCAD la traduzca sola al idioma de la sesion (p.ej. "Si" en
      ;; español); escribir "_Si" no serviria, porque no es una palabra
      ;; clave en ingles reconocida para traducir.
      (setq existed (tblsearch "BLOCK" name))
      (if existed
        (command "_.-BLOCK" name "_Yes" (list 0.0 0.0 0.0) ss "")
        (command "_.-BLOCK" name (list 0.0 0.0 0.0) ss "")
      )
      (foreach e ents (if (entget e) (entdel e)))
      (if (tblsearch "BLOCK" name)
        name
        (progn
          (princ (strcat "\n[CONDUCTO] Aviso: el comando -BLOCK no ha dejado creado \"" name "\"."))
          nil
        )
      )
    )
  )
)

;; Codo CIRCULAR: dos arcos concentricos (pared exterior/interior) de
;; radio 1.5xD +/- media dimension, mas 3 atributos (DIAM, ANG, TIPO).
;; Devuelve el nombre del bloque (creandolo si hace falta), o nil si
;; algo ha fallado.
(defun ensure-circular-elbow-block (dim ang / name R Ttan angRad center outerR innerR attH ents)
  (setq name (elbow-block-name "Circular" dim ang))
  (if (block-has-content name)
    name
    (progn
      (setq R (* *conducto-radius-factor* dim))
      (setq angRad (* ang (/ pi 180.0)))
      (setq Ttan (* R (tan (/ angRad 2.0))))
      (setq center (list 0.0 R 0.0))
      (setq outerR (+ R (/ dim 2.0)))
      (setq innerR (- R (/ dim 2.0)))
      (setq attH (max 1.0 (* dim 0.12)))
      (setq ents
        (list
          (entmakex (list '(0 . "ARC") (cons 10 center) (cons 40 outerR)
                          (cons 50 (* 1.5 pi)) (cons 51 (+ (* 1.5 pi) angRad))))
          (entmakex (list '(0 . "ARC") (cons 10 center) (cons 40 innerR)
                          (cons 50 (* 1.5 pi)) (cons 51 (+ (* 1.5 pi) angRad))))
          (entmakex (list '(0 . "ATTDEF") '(100 . "AcDbEntity") '(100 . "AcDbText")
                          (cons 10 (list (+ Ttan (* dim 0.1)) (* dim -0.1) 0.0))
                          (cons 40 attH) (cons 1 (rtos dim 2 0)) '(100 . "AcDbAttributeDefinition")
                          (cons 3 "Diametro") (cons 2 "DIAM") '(70 . 0)))
          (entmakex (list '(0 . "ATTDEF") '(100 . "AcDbEntity") '(100 . "AcDbText")
                          (cons 10 (list (+ Ttan (* dim 0.1)) (- (* dim -0.1) (* attH 1.4)) 0.0))
                          (cons 40 attH) (cons 1 (rtos ang 2 1)) '(100 . "AcDbAttributeDefinition")
                          (cons 3 "Angulo") (cons 2 "ANG") '(70 . 0)))
          (entmakex (list '(0 . "ATTDEF") '(100 . "AcDbEntity") '(100 . "AcDbText")
                          (cons 10 (list (+ Ttan (* dim 0.1)) (- (* dim -0.1) (* attH 2.8)) 0.0))
                          (cons 40 attH) (cons 1 "CIRCULAR") '(100 . "AcDbAttributeDefinition")
                          (cons 3 "Tipo") (cons 2 "TIPO") '(70 . 0)))
        )
      )
      (if (build-block-from-entities name ents (list "arco-exterior" "arco-interior" "attdef-diametro" "attdef-angulo" "attdef-tipo"))
        name
        (progn
          (princ (strcat "\n[CONDUCTO] Aviso: no se ha podido crear el bloque de codo \"" name "\"."))
          nil
        )
      )
    )
  )
)

;; Codo RECTANGULAR a escuadra: dos "patas" (cada una de longitud
;; *conducto-rect-elbow-leg-factor* x ancho) que se encuentran en un
;; vertice a inglete, con sus dos paredes -mismo calculo de esquina a
;; inglete que produce un OFFSET, pero resuelto aqui con interseccion
;; de rectas porque la geometria vive en un sistema local propio,
;; alrededor del origen, antes de convertirse en bloque-, mas 3
;; atributos (ANCHO, ANG, TIPO). Devuelve el nombre del bloque, o nil
;; si algo ha fallado.
(defun ensure-rect-elbow-block (dim ang / name angRad Tr half cosA sinA v s
                                 nearPt vOffset cornerPt farPt attH ents)
  (setq name (elbow-block-name "Rectangular" dim ang))
  (if (block-has-content name)
    name
    (progn
      (setq angRad (* ang (/ pi 180.0)))
      (setq Tr (* *conducto-rect-elbow-leg-factor* dim))
      (setq half (/ dim 2.0))
      (setq cosA (cos angRad))
      (setq sinA (sin angRad))
      (setq v (list Tr 0.0))
      (setq ents '())
      (foreach s (list 1.0 -1.0)
        (setq nearPt (list 0.0 (* s half)))
        (setq vOffset (list (- Tr (* s half sinA)) (* s half cosA)))
        (setq cornerPt (line-intersect nearPt 0.0 vOffset angRad))
        (if cornerPt
          (progn
            (setq farPt (list (+ (car vOffset) (* Tr cosA)) (+ (cadr vOffset) (* Tr sinA))))
            (setq ents (append ents (list
              (entmakex (list '(0 . "LINE")
                (cons 10 (append nearPt (list 0.0))) (cons 11 (append cornerPt (list 0.0)))))
              (entmakex (list '(0 . "LINE")
                (cons 10 (append cornerPt (list 0.0))) (cons 11 (append farPt (list 0.0)))))
            )))
          )
          (setq ents (append ents (list nil)))
        )
      )
      (setq attH (max 1.0 (* dim 0.12)))
      (setq ents (append ents (list
        (entmakex (list '(0 . "ATTDEF") '(100 . "AcDbEntity") '(100 . "AcDbText")
                  (cons 10 (list (+ Tr (* dim 0.1)) (* dim -0.1) 0.0))
                  (cons 40 attH) (cons 1 (rtos dim 2 0)) '(100 . "AcDbAttributeDefinition")
                  (cons 3 "Ancho") (cons 2 "ANCHO") '(70 . 0)))
        (entmakex (list '(0 . "ATTDEF") '(100 . "AcDbEntity") '(100 . "AcDbText")
                  (cons 10 (list (+ Tr (* dim 0.1)) (- (* dim -0.1) (* attH 1.4)) 0.0))
                  (cons 40 attH) (cons 1 (rtos ang 2 1)) '(100 . "AcDbAttributeDefinition")
                  (cons 3 "Angulo") (cons 2 "ANG") '(70 . 0)))
        (entmakex (list '(0 . "ATTDEF") '(100 . "AcDbEntity") '(100 . "AcDbText")
                  (cons 10 (list (+ Tr (* dim 0.1)) (- (* dim -0.1) (* attH 2.8)) 0.0))
                  (cons 40 attH) (cons 1 "RECTANGULAR") '(100 . "AcDbAttributeDefinition")
                  (cons 3 "Tipo") (cons 2 "TIPO") '(70 . 0)))
      )))
      (if (build-block-from-entities name ents
            (list "linea-lado1-a" "linea-lado1-b" "linea-lado2-a" "linea-lado2-b"
                  "attdef-ancho" "attdef-angulo" "attdef-tipo"))
        name
        (progn
          (princ (strcat "\n[CONDUCTO] Aviso: no se ha podido crear el bloque de codo \"" name "\"."))
          nil
        )
      )
    )
  )
)

;; Inserta una instancia del bloque de codo "blkName" en insPt, girada
;; rotAng (radianes, el eje +X local pasa a coincidir con la direccion
;; de entrada real), y espejada (YScale=-1) si isLeft es nil -los
;; bloques se construyen siempre para giro a la izquierda-. Devuelve el
;; objeto insertado, o nil si ha fallado.
(defun insert-elbow (blkName insPt rotAng isLeft / doc ms result)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq ms (vla-get-ModelSpace doc))
  ;; vla-InsertBlock exige el punto como VARIANTE (a diferencia de
  ;; entmake, que acepta listas de LISP normales) -sin vlax-3d-point,
  ;; falla con "el valor lisp no tiene coercion con VARIANTE".
  (setq result (vl-catch-all-apply 'vla-InsertBlock
                 (list ms (vlax-3d-point (append insPt (list 0.0))) blkName 1.0 (if isLeft 1.0 -1.0) 1.0 rotAng)))
  (if (vl-catch-all-error-p result)
    (progn
      (princ (strcat "\n[CONDUCTO] Aviso: fallo al insertar el codo (" (vl-catch-all-error-message result) ")."))
      nil
    )
    result
  )
)

;; --- CONDUCTO: trazado de un recorrido con codos automaticos ---

(defun c:CONDUCTO
  ( / tipo diametro ancho dim half beforeEnt plEnt rawPts pts n
      i a v c defl nearest warnCount tlen oldOrtho badVertices bv
      boundaries p1 p2 crossSign rotAng blkName inserted nElbows
      segCL off1 off2 nSegs axisData bulgeVal axisEnt axisObj)

  (initget "Circular Rectangular")
  (setq tipo (getkword "\n[CONDUCTO] Tipo de conducto [Circular/Rectangular] <Circular>: "))
  (if (not tipo) (setq tipo "Circular"))

  (if (= tipo "Circular")
    (progn
      (setq diametro (getdist "\n[CONDUCTO] Diametro del conducto: "))
      (if (or (not diametro) (<= diametro 0))
        (progn (princ "\n[CONDUCTO] Cancelado.") (princ) (exit))
      )
      (setq dim diametro)
    )
    (progn
      (setq ancho (getdist "\n[CONDUCTO] Ancho del conducto (dimension en planta): "))
      (if (or (not ancho) (<= ancho 0))
        (progn (princ "\n[CONDUCTO] Cancelado.") (princ) (exit))
      )
      (setq dim ancho)
    )
  )
  (setq half (/ dim 2.0))

  ;; Para rectangular, el unico codo que se genera es a escuadra (90),
  ;; asi que se activa ORTHO mientras se traza para que el angulo salga
  ;; normalizado el solo (se puede saltar puntualmente con MAYUS, y se
  ;; restaura el ORTHO que hubiera al terminar). Para circular NO se
  ;; fuerza -los codos normalizados admitidos (45/30/22.5/15) no son
  ;; solo 90-.
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

  (setq pts (simplify-points rawPts 1e-6))
  (entdel plEnt)

  (setq n (length pts))
  (setq warnCount 0)
  (setq nElbows 0)
  (setq nSegs 0)

  ;; Validacion de angulos ANTES de crear nada: un codo con un angulo
  ;; que no sea uno de los normalizados no llega a dibujarse -se
  ;; rechaza el recorrido ENTERO (no se crea ni un tramo ni un codo) y
  ;; hay que corregirlo y volver a ejecutar CONDUCTO-, en vez de
  ;; crearlo igual con solo un aviso.
  (setq badVertices '())
  (if (>= n 3)
    (progn
      (setq i 1)
      (while (< i (1- n))
        (setq a (nth (1- i) pts))
        (setq v (nth i pts))
        (setq c (nth (1+ i) pts))
        (setq defl (deflection-deg a v c))
        (if (= tipo "Circular")
          (progn
            (setq nearest (nearest-standard-angle defl *conducto-standard-angles*))
            (if (> (cadr nearest) *conducto-angle-warn-tol-deg*)
              (setq badVertices (append badVertices (list (list (1+ i) defl))))
            )
          )
          (if (> (abs (- defl 90.0)) *conducto-angle-warn-tol-deg*)
            (setq badVertices (append badVertices (list (list (1+ i) defl))))
          )
        )
        (setq i (1+ i))
      )
    )
  )
  (if badVertices
    (progn
      (princ (strcat "\n[CONDUCTO] Recorrido RECHAZADO: hay codo(s) sin angulo normalizado"
                     (if (= tipo "Circular")
                       (strcat " (validos: " (implode-list (mapcar '(lambda (x) (rtos x 2 1)) *conducto-standard-angles*) ", ") ")")
                       " (solo se admite 90 en rectangular)"
                     )
                     ":"))
      (foreach bv badVertices
        (princ (strcat "\n  - vertice " (itoa (car bv)) ": " (rtos (cadr bv) 2 1) " grados"))
      )
      (princ "\n[CONDUCTO] No se ha creado ningun tramo ni codo. Corrige el recorrido (usa ORTHO/polar) y vuelve a ejecutar CONDUCTO.")
      (princ)
      (exit)
    )
  )

  ;; "boundaries" es la lista de puntos reales donde empieza/termina
  ;; cada TRAMO RECTO de pared: el inicio y el fin del recorrido, y los
  ;; dos puntos de conexion (tangencia en circular, union a inglete en
  ;; rectangular) de cada codo interior -en vez del vertice en bruto-.
  (setq boundaries (list (car pts)))

  ;; "axisData" es la lista (punto . bulge) del EJE de referencia:
  ;; a diferencia de "boundaries" (que solo marca donde empiezan/
  ;; terminan los tramos rectos), este SI seguira la forma real del
  ;; conducto en cada codo -un arco (bulge) en circular, o pasando por
  ;; el vertice real en rectangular- en vez de quedarse con las
  ;; esquinas en bruto del recorrido trazado.
  (setq axisData (list (cons (car pts) 0.0)))

  (setq i 1)
  (while (< i (1- n))
    (setq a (nth (1- i) pts))
    (setq v (nth i pts))
    (setq c (nth (1+ i) pts))
    (setq defl (deflection-deg a v c))

    ;; El angulo ya se valido como normalizado antes de llegar aqui
    ;; (si no lo fuera, el recorrido entero se habria rechazado mas
    ;; arriba); aqui solo hace falta la longitud de conexion del codo.
    (setq tlen
      (if (= tipo "Circular")
        (* (* *conducto-radius-factor* dim) (tan (/ (* defl (/ pi 180.0)) 2.0)))
        (* *conducto-rect-elbow-leg-factor* dim)
      )
    )

    (if (or (> tlen (distance a v)) (> tlen (distance v c)))
      (progn
        (princ (strcat "\n[CONDUCTO] Aviso: el tramo junto al vertice " (itoa (1+ i))
                       " puede ser demasiado corto para el codo (necesita " (rtos tlen 2 1) " a cada lado)."))
        (setq warnCount (1+ warnCount))
      )
    )

    ;; Puntos de conexion del codo con los tramos rectos vecinos.
    (setq p1 (polar v (angle v a) tlen))
    (setq p2 (polar v (angle v c) tlen))
    (setq boundaries (append boundaries (list p1)))

    ;; Bloque del codo (creado si hace falta, reutilizado si ya existe
    ;; uno igual), insertado orientado hacia la direccion de entrada, y
    ;; espejado si el giro es hacia la derecha.
    (setq crossSign (cross-2d (polar (list 0.0 0.0) (angle a v) 1.0) (polar (list 0.0 0.0) (angle v c) 1.0)))
    (setq rotAng (angle a v))

    ;; El eje sigue la MISMA curva que el codo: en circular, un arco de
    ;; bulge = tan(angulo/4) (positivo si gira a la izquierda, negativo
    ;; si a la derecha -el mismo signo que crossSign-); en rectangular
    ;; no hay arco, pero el eje pasa por el vertice real (no por una
    ;; cuerda recta p1-p2, que cortaria la esquina).
    (if (= tipo "Circular")
      (progn
        (setq bulgeVal (tan (/ (* defl (/ pi 180.0)) 4.0)))
        (if (< crossSign 0.0) (setq bulgeVal (- bulgeVal)))
        (setq axisData (append axisData (list (cons p1 bulgeVal) (cons p2 0.0))))
      )
      (setq axisData (append axisData (list (cons p1 0.0) (cons v 0.0) (cons p2 0.0))))
    )
    (setq blkName
      (if (= tipo "Circular")
        (ensure-circular-elbow-block dim defl)
        (ensure-rect-elbow-block dim defl)
      )
    )
    (if blkName
      (progn
        (setq inserted (insert-elbow blkName p1 rotAng (>= crossSign 0.0)))
        (if inserted (setq nElbows (1+ nElbows)))
      )
      (princ (strcat "\n[CONDUCTO] Aviso: no se ha podido crear/insertar el codo del vertice " (itoa (1+ i)) "."))
    )

    (setq boundaries (append boundaries (list p2)))
    (setq i (1+ i))
  )

  (setq boundaries (append boundaries (list (last pts))))
  (setq axisData (append axisData (list (cons (last pts) 0.0))))

  ;; El eje de referencia: sigue el recorrido real, con arco en cada
  ;; codo circular (bulge) o pasando por el vertice en rectangular -a
  ;; diferencia de "boundaries", que es solo para generar las paredes-.
  (setq axisEnt (make-polyline-b axisData))
  (mark-as-axis axisEnt (/ dim 20.0))
  (setq axisObj (vlax-ename->vla-object axisEnt))
  (princ (strcat "\n[CONDUCTO] Eje: color=" (itoa (vla-get-Color axisObj))
                 " tipolinea=" (vla-get-Linetype axisObj)))

  ;; "boundaries" alterna HUECO-DE-TRAMO-RECTO, HUECO-DE-CODO, tramo,
  ;; codo, ..., tramo: (inicio, p1-codo1, p2-codo1, p1-codo2, p2-codo2,
  ;; ..., fin). Los pares que empiezan en indice PAR (0,2,4...) son
  ;; tramos rectos de pared; los que empiezan en indice IMPAR son el
  ;; hueco que ya ocupa el bloque del codo -ahi NO hay que dibujar
  ;; nada, o saldria una pared diagonal atravesando el propio codo-.
  (setq i 0)
  (while (< i (1- (length boundaries)))
    (setq a (nth i boundaries))
    (setq v (nth (1+ i) boundaries))
    (if (and (= (rem i 2) 0) (> (distance a v) 1e-6))
      (progn
        (setq segCL (make-polyline (list a v)))
        (setq off1 (offset-curve segCL half))
        (setq off2 (offset-curve segCL (- half)))
        (if (and off1 off2)
          (setq nSegs (1+ nSegs))
          (princ "\n[CONDUCTO] Aviso: fallo al generar un tramo recto de pared.")
        )
        (entdel segCL)
      )
    )
    (setq i (1+ i))
  )

  (command "_.REGEN")

  (princ (strcat "\n[CONDUCTO] Conducto " tipo " creado: " (itoa nSegs) " tramo(s) recto(s) y "
                 (itoa nElbows) " codo(s) normalizado(s) insertado(s) como bloque"
                 (if (> warnCount 0) (strcat ", " (itoa warnCount) " con aviso de tramo corto") "")
                 ". Eje central conservado."))
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
  ;; principal -sirve tal cual como referencia para comprobar si un
  ;; ramal sale perpendicular.
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

    (mark-as-axis branchCL (/ branchDim 20.0))
    (setq k (1+ k))
  )

  (command "_.REGEN")
  (princ "\n[CONDUCTORAMAL] Union creada. El conducto principal no se ha modificado.")
  (princ)
)

(princ "\nCONDUCTOS cargado. Escribe 'CONDUCTO' para trazar un conducto circular o rectangular con codos como bloques, o 'CONDUCTORAMAL' para insertar una union en T o en cruz.")
(princ)
