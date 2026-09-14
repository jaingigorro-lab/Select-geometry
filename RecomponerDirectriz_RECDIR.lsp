(vl-load-com)

;; ==========================================================
;; RECDIR - Recompone, en un solo lote, varias lineas/polilineas sueltas,
;; sus puntas de flecha (SOLID/INSERT) y un texto en una DIRECTRIZ propia
;; de CAD (un MULTILEADER real), con el MISMO TEXTO que el seleccionado.
;; Pensado para arreglar directrices que hayan quedado descompuestas en
;; piezas sueltas (por ejemplo, tras un EXPLODE de un LEADER/MLEADER
;; antiguo, o una importacion que las dejo sin relacion). Reconstruye la
;; CADENA COMPLETA de cada directriz (no solo el tramo mas cercano al
;; texto: si el original tenia un codo de dos tramos, se conservan los
;; dos), respetando la posicion original de cada vertice -no se inventa
;; ni se endereza nada de la geometria-, y limpia las puntas de flecha
;; sueltas (SOLID/INSERT) que hayan quedado separadas.
;;
;; El MULTILEADER resultante lleva su PROPIO texto -copiado tal cual del
;; texto original (mismo contenido)-, de forma que la directriz queda
;; como una unica entidad nativa de CAD (texto + linea + flecha
;; asociados entre si, editables y desplazables como un todo). El texto
;; suelto original, una vez copiado su contenido al MULTILEADER, se
;; borra para no dejar un texto duplicado en el dibujo.
;;
;; Uso:
;;   1. Ejecutar RECDIR.
;;   2. Seleccionar TODO de una vez: los textos, las lineas/polilineas
;;      sueltas de todas las directrices que se quieran recomponer, y
;;      (si las hay) las puntas de flecha sueltas (SOLID o bloques
;;      INSERT). No hace falta agrupar nada por directriz: el comando
;;      empareja cada texto con su cadena de lineas mas cercana el solo.
;;   3. Elegir el estilo de directriz (MLeaderStyle) a usar, de los que
;;      ya existan en el dibujo.
;;   4. El comando reconstruye un MULTILEADER real por cada texto, con el
;;      mismo texto que tenia el original, orientado del extremo mas
;;      alejado del texto (punta de flecha) al mas cercano, y borra tanto
;;      las lineas sueltas y la flecha vieja ya recompuestas como el
;;      texto original suelto (su contenido ya vive en el MULTILEADER).
;; ==========================================================

;; Tolerancia (en unidades de dibujo) para considerar que dos extremos de
;; linea son "el mismo punto" al reconstruir la cadena de una directriz.
(setq *recdir-chain-tolerance* 0.5)

;; Una punta de flecha suelta (SOLID/INSERT) se borra si esta a menos de
;; este factor x la altura del texto, de distancia de la punta de la
;; directriz reconstruida.
(setq *recdir-arrow-cleanup-factor* 2.0)

;; True si dos puntos estan a menos de tol de distancia.
(defun points-match (p1 p2 tol)
  (< (distance p1 p2) tol)
)

;; Concatena una lista de cadenas de texto con un separador.
(defun implode-list (lst sep / result)
  (setq result "")
  (foreach s lst
    (setq result (if (= result "") s (strcat result sep s)))
  )
  result
)

;; Extiende una cadena que empieza en el segmento "seed" (p1 . p2),
;; consumiendo tantos segmentos de "pool" como se puedan seguir
;; encadenando por sus extremos (en cualquiera de los dos sentidos).
;; Devuelve (cadenaDePuntos . segmentosNoConsumidosDeEsePool).
(defun grow-chain (seed pool tol / chain remaining head tail found)
  (setq chain (list (car seed) (cdr seed)))
  (setq remaining pool)
  (setq found T)
  (while (and remaining found)
    (setq head (car chain))
    (setq tail (last chain))
    (setq found nil)
    (foreach s remaining
      (if (not found)
        (cond
          ((points-match (car s) tail tol)
            (setq chain (append chain (list (cdr s))))
            (setq remaining (vl-remove s remaining))
            (setq found T)
          )
          ((points-match (cdr s) tail tol)
            (setq chain (append chain (list (car s))))
            (setq remaining (vl-remove s remaining))
            (setq found T)
          )
          ((points-match (car s) head tol)
            (setq chain (cons (cdr s) chain))
            (setq remaining (vl-remove s remaining))
            (setq found T)
          )
          ((points-match (cdr s) head tol)
            (setq chain (cons (car s) chain))
            (setq remaining (vl-remove s remaining))
            (setq found T)
          )
        )
      )
    )
  )
  (cons chain remaining)
)

;; Divide una lista de segmentos en sus componentes conexas -cada una, la
;; cadena ordenada de puntos de UNA directriz completa, con sus posibles
;; codos intermedios-. Devuelve una lista de cadenas.
(defun split-into-chains (segments tol / remaining components result)
  (setq remaining segments)
  (setq components '())
  (while remaining
    (setq result (grow-chain (car remaining) (cdr remaining) tol))
    (setq components (cons (car result) components))
    (setq remaining (cdr result))
  )
  (reverse components)
)

;; Vertices (en orden) de una LWPOLYLINE, como lista de puntos 3D (Z=0).
(defun polyline-points (ent / obj coordsList pts i n)
  (setq obj (vlax-ename->vla-object ent))
  (setq coordsList (vlax-safearray->list (vlax-variant-value (vla-get-Coordinates obj))))
  (setq pts '())
  (setq n (length coordsList))
  (setq i 0)
  (while (< i n)
    (setq pts (cons (list (nth i coordsList) (nth (1+ i) coordsList) 0.0) pts))
    (setq i (+ i 2))
  )
  (reverse pts)
)

;; Lista de segmentos (p1 . p2) consecutivos a partir de una lista de puntos.
(defun consecutive-pairs (pts / result rest)
  (setq result '())
  (setq rest pts)
  (while (cdr rest)
    (setq result (cons (cons (car rest) (cadr rest)) result))
    (setq rest (cdr rest))
  )
  (reverse result)
)

;; Extrae todos los segmentos de una lista de enames de LINE y/o LWPOLYLINE.
(defun extract-segments (entList / segs edata etype)
  (setq segs '())
  (foreach ent entList
    (setq edata (entget ent))
    (setq etype (cdr (assoc 0 edata)))
    (cond
      ((= etype "LINE")
        (setq segs (cons (cons (cdr (assoc 10 edata)) (cdr (assoc 11 edata))) segs))
      )
      ((= etype "LWPOLYLINE")
        (setq segs (append segs (consecutive-pairs (polyline-points ent))))
      )
    )
  )
  segs
)

;; True si algun tramo consecutivo de la lista de puntos "pts" coincide
;; (en cualquier sentido) con el segmento p1-p2, con tolerancia tol.
(defun points-contain-segment (pts p1 p2 tol / found)
  (setq found nil)
  (foreach seg (consecutive-pairs pts)
    (if (or (and (points-match (car seg) p1 tol) (points-match (cdr seg) p2 tol))
            (and (points-match (car seg) p2 tol) (points-match (cdr seg) p1 tol)))
      (setq found T)
    )
  )
  found
)

;; Dada una cadena de puntos ya reconstruida y consumida, identifica que
;; entidades originales (de entList) aportaron sus tramos -para poder
;; borrar solo lo que de verdad se ha usado, y no tocar nada que se
;; hubiera seleccionado de mas sin llegar a formar parte de ninguna
;; directriz reconstruida.
(defun entities-for-chain (chainPts entList tol / result edata etype p1 p2 used)
  (setq result '())
  (foreach seg (consecutive-pairs chainPts)
    (setq p1 (car seg))
    (setq p2 (cdr seg))
    (foreach ent entList
      (setq edata (entget ent))
      (setq etype (cdr (assoc 0 edata)))
      (setq used nil)
      (cond
        ((= etype "LINE")
          (setq used
            (or (and (points-match (cdr (assoc 10 edata)) p1 tol) (points-match (cdr (assoc 11 edata)) p2 tol))
                (and (points-match (cdr (assoc 10 edata)) p2 tol) (points-match (cdr (assoc 11 edata)) p1 tol))))
        )
        ((= etype "LWPOLYLINE")
          (setq used (points-contain-segment (polyline-points ent) p1 p2 tol))
        )
      )
      (if (and used (not (member ent result)))
        (setq result (cons ent result))
      )
    )
  )
  result
)

;; Nombres de todos los MLeaderStyle definidos en el dibujo. MLeaderStyle
;; no tiene una coleccion ActiveX propia (a diferencia de Layers, Blocks,
;; TextStyles...) porque se anadio despues via el Diccionario de Objetos
;; Nombrados (NOD) en vez de una tabla/coleccion clasica -asi que se lee
;; directamente de ahi, sin ActiveX. Si por lo que sea no se encuentra el
;; diccionario (nombre distinto en alguna version), devuelve nil y el
;; llamador recurre solo al estilo activo.
(defun list-mleader-styles ( / dictData names pair)
  (setq dictData (dictsearch (namedobjdict) "ACAD_MLEADERSTYLE"))
  (setq names '())
  (if dictData
    (foreach pair dictData
      (if (= (car pair) 3) (setq names (cons (cdr pair) names)))
    )
  )
  (reverse names)
)

(defun c:RECDIR
  ( / doc modelSpace ss n i ent edata etype textList lineList solidList
      allSegs chains availableStyles currentStyle chosenStyle
      txtEnt txtObj txtStr txtHeight txtPt bestChain bestDist c d0 d1
      arrowPt chainUCS p usedLines usedTexts
      solidEnt solidClosest solidClosestDist solPt dd
      mlEnt mlObj usedSolids doneCount)

  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq modelSpace (vla-get-ModelSpace doc))

  (princ "\n[RECDIR] Selecciona TODO lo de las directrices a recomponer (textos, lineas/polilineas, y flechas sueltas si las hay): ")
  (setq ss (ssget '((0 . "TEXT,MTEXT,LINE,LWPOLYLINE,SOLID,INSERT"))))
  (if (not ss)
    (progn (princ "\n[RECDIR] Nada seleccionado. Cancelado.") (princ) (exit))
  )

  (setq textList '() lineList '() solidList '())
  (setq n (sslength ss))
  (setq i 0)
  (while (< i n)
    (setq ent (ssname ss i))
    (setq edata (entget ent))
    (setq etype (cdr (assoc 0 edata)))
    (cond
      ((member etype (list "TEXT" "MTEXT")) (setq textList (cons ent textList)))
      ((member etype (list "LINE" "LWPOLYLINE")) (setq lineList (cons ent lineList)))
      ((member etype (list "SOLID" "INSERT")) (setq solidList (cons ent solidList)))
    )
    (setq i (1+ i))
  )

  (if (or (not textList) (not lineList))
    (progn
      (princ "\n[RECDIR] Hacen falta al menos un texto y alguna linea/polilinea en la seleccion.")
      (princ)
      (exit)
    )
  )

  ;; Todas las cadenas (una por cada directriz completa, codos incluidos).
  (setq allSegs (extract-segments lineList))
  (setq chains (split-into-chains allSegs *recdir-chain-tolerance*))
  (if (not chains)
    (progn (princ "\n[RECDIR] No se ha podido extraer ninguna cadena de las lineas seleccionadas.") (princ) (exit))
  )

  ;; Estilo de directriz: se elige entre los MLeaderStyle ya existentes en
  ;; el dibujo (no se inventa uno nuevo). Si no se ha podido leer la lista
  ;; (ver list-mleader-styles), se usa directamente el estilo activo, sin
  ;; preguntar algo que no se podria validar de todos modos.
  (setq availableStyles (list-mleader-styles))
  (setq currentStyle (getvar "CMLEADERSTYLE"))
  (setq chosenStyle currentStyle)
  (if availableStyles
    (progn
      (princ (strcat "\n[RECDIR] Estilos de directriz disponibles: " (implode-list availableStyles ", ")))
      (setq chosenStyle (getstring T (strcat "\n[RECDIR] Estilo a usar <" currentStyle ">: ")))
      (if (or (not chosenStyle) (= chosenStyle "")) (setq chosenStyle currentStyle))
      (if (not (member chosenStyle availableStyles))
        (progn
          (princ (strcat "\n[RECDIR] \"" chosenStyle "\" no existe; se usa el estilo activo (" currentStyle ")."))
          (setq chosenStyle currentStyle)
        )
      )
    )
    (princ (strcat "\n[RECDIR] No se ha podido listar los estilos de directriz; se usa el activo (" currentStyle ")."))
  )
  (if (/= chosenStyle currentStyle)
    (vl-catch-all-apply 'setvar (list "CMLEADERSTYLE" chosenStyle))
  )

  (setq usedSolids '())
  (setq usedLines '())
  (setq usedTexts '())
  (setq doneCount 0)

  (foreach txtEnt textList
    (setq txtObj (vlax-ename->vla-object txtEnt))
    ;; vla-get-TextString funciona igual para TEXT y para MTEXT (en este
    ;; ultimo caso, devuelve el contenido completo con sus codigos de
    ;; formato/parrafo, que un MULTILEADER tambien admite como texto).
    (setq txtStr (vla-get-TextString txtObj))
    (setq edata (entget txtEnt))
    (setq txtHeight (cdr (assoc 40 edata)))
    (if (not txtHeight) (setq txtHeight 2.5))
    (setq txtPt (trans (cdr (assoc 10 edata)) txtEnt 0))

    ;; Cadena mas cercana a este texto (por cualquiera de sus dos extremos).
    (setq bestChain nil)
    (setq bestDist 1e99)
    (foreach c chains
      (setq d0 (distance txtPt (car c)))
      (setq d1 (distance txtPt (last c)))
      (if (< (min d0 d1) bestDist)
        (progn (setq bestDist (min d0 d1)) (setq bestChain c))
      )
    )

    (if bestChain
      (progn
        (setq chains (vl-remove bestChain chains))

        ;; Orientar la cadena: el extremo que se conecta con el texto (el
        ;; mas cercano a el) queda al final -asi el ultimo punto que se
        ;; envia a MLEADER es el enganche, y el primero, la punta de
        ;; flecha, exactamente como estaban en la geometria original.
        (if (>= (distance (last bestChain) txtPt) (distance (car bestChain) txtPt))
          (setq bestChain (reverse bestChain))
        )
        (setq arrowPt (car bestChain))

        ;; Los puntos que se pasan a (command) se interpretan en el SCP
        ;; activo, no en el mundo: hay que convertirlos.
        (setq chainUCS (mapcar '(lambda (p) (trans p 0 1)) bestChain))

        ;; --- crear el MULTILEADER: solo se dan los puntos; el texto NO
        ;; se escribe durante la creacion (el editor en linea se cierra
        ;; con Escape en vez de con Intro -Escape nunca se cuela como
        ;; texto ni repite el comando si ya ha terminado, al contrario que
        ;; una cadena vacia-). El contenido real se asigna justo despues,
        ;; con vla-put-TextString, copiando tal cual el texto original. ---
        (command "_.MLEADER")
        (foreach p chainUCS (command "_non" p))
        (command "" (chr 27) (chr 27) (chr 27))
        (while (> (getvar "CMDACTIVE") 0) (command (chr 27)))

        (setq mlEnt (entlast))
        (if (and mlEnt (= (cdr (assoc 0 (entget mlEnt))) "MULTILEADER"))
          (progn
            (setq mlObj (vlax-ename->vla-object mlEnt))
            ;; El MULTILEADER nuevo lleva el MISMO texto que el original,
            ;; para quedar como una directriz propia de CAD -una unica
            ;; entidad nativa con linea, flecha y texto asociados entre
            ;; si-. El texto suelto original ya no hace falta: se marca
            ;; para borrarlo mas abajo, junto con las lineas consumidas.
            (vl-catch-all-apply 'vla-put-TextString (list mlObj txtStr))

            (setq usedLines (append usedLines (entities-for-chain bestChain lineList *recdir-chain-tolerance*)))
            (setq usedTexts (cons txtEnt usedTexts))
            (setq doneCount (1+ doneCount))

            ;; Buscar y borrar una punta de flecha suelta (SOLID/INSERT)
            ;; que haya quedado junto al extremo de la flecha.
            (setq solidClosest nil solidClosestDist 1e99)
            (foreach solidEnt solidList
              (if (not (member solidEnt usedSolids))
                (progn
                  (setq solPt (trans (cdr (assoc 10 (entget solidEnt))) solidEnt 0))
                  (setq dd (distance arrowPt solPt))
                  (if (< dd solidClosestDist)
                    (progn (setq solidClosestDist dd) (setq solidClosest solidEnt))
                  )
                )
              )
            )
            (if (and solidClosest (< solidClosestDist (* *recdir-arrow-cleanup-factor* txtHeight)))
              (progn
                (entdel solidClosest)
                (setq usedSolids (cons solidClosest usedSolids))
              )
            )
          )
          (princ (strcat "\n[RECDIR] Aviso: no se pudo crear el MULTILEADER para el texto \"" txtStr "\"."))
        )
      )
      (princ (strcat "\n[RECDIR] Aviso: no se ha encontrado ninguna cadena de lineas para el texto \"" txtStr "\"."))
    )
  )

  ;; Borrar SOLO las lineas/polilineas que de verdad se han usado en una
  ;; directriz reconstruida -si se selecciono alguna de mas que no llego
  ;; a emparejarse con ningun texto, se deja intacta en el dibujo- y los
  ;; textos originales cuyo contenido ya se ha copiado al MULTILEADER.
  (foreach ent usedLines (entdel ent))
  (foreach ent usedTexts (entdel ent))

  ;; Restaurar el estilo de directriz activo, si se cambio.
  (if (/= chosenStyle currentStyle)
    (vl-catch-all-apply 'setvar (list "CMLEADERSTYLE" currentStyle))
  )

  (princ (strcat "\n[RECDIR] " (itoa doneCount) " directriz(ces) recompuesta(s) con el estilo \""
                 chosenStyle "\", cada una con su mismo texto integrado."))
  (princ)
)

(princ "\nRECDIR cargado. Escribe 'RECDIR' para recomponer, en un lote, lineas, flechas y texto en una directriz propia de CAD.")
(princ)
