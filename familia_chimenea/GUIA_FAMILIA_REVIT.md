# Guía: construir en Revit la familia «Chimenea_Esquina_Minimalista»

**Índice:** [0. Qué vas a obtener](#0-qué-vas-a-obtener) · [1. Nueva familia](#1-nueva-familia) · [2. Parámetros y materiales](#2-parámetros-y-materiales) · [3. Planos de referencia y cotas](#3-planos-de-referencia-y-cotas) · [4. Cuerpo (pentágono)](#4-cuerpo-pentágono) · [5. Zócalo retranqueado y anclaje](#5-zócalo-retranqueado-y-anclaje) · [6. Hogar (hueco, marco, vidrio, interior)](#6-hogar-hueco-marco-vidrio-interior) · [7. Subcategorías y asociación a las formas](#7-subcategorías-y-asociación-a-las-formas) · [8. Representación en planta y niveles de detalle](#8-representación-en-planta-y-niveles-de-detalle) · [9. Prueba de flexión](#9-prueba-de-flexión) · [10. Guardar, cargar y colocar en el proyecto](#10-guardar-cargar-y-colocar-en-el-proyecto) · [11. Atajo de comprobación con el DXF de planta](#11-atajo-de-comprobación-con-el-dxf-de-planta) · [12. Problemas típicos y soluciones](#12-problemas-típicos-y-soluciones)

## 0. Qué vas a obtener
- Una familia `.rfa` de **chimenea de esquina minimalista**: volumen liso en pentágono (muro de fondo 1380, muro izquierdo 1420, chaflán de 720 × 920), zócalo retranqueado (junta de sombra), hueco de hogar rectangular centrado en el chaflán, marco de acero negro y vidrio.
- Es **paramétrica**: ancho, fondo, chaflán, hueco, marco, zócalo y altura se cambian desde las propiedades; la altura es de instancia.
- Se modela **ortogonal**; el desvío de 2,39° del muro izquierdo lo absorbe un solape oculto (anclaje) dentro de los muros.
- Tiempo estimado: **2–3 horas** la primera vez (estimación mía, no medida).
- **Aviso honesto:** esta guía está escrita **sin poder ejecutar Revit**; nadie la ha probado en Revit ni en AutoCAD (los DXF y la lámina solo se han comprobado geométricamente con scripts). Los nombres de comandos son los habituales en español; donde dudo, la duda va en una línea «Si no funciona: ver apartado 12, fila N» al final del paso.

Convenciones: unidades en mm; el inglés entre paréntesis solo la primera vez; X a la derecha, **Y hacia el muro de fondo (arriba en planta)**; el cuerpo ocupa X ≥ 0, Y ≤ 0; origen O = esquina interior (cara interior del muro de fondo ∩ cara interior del muro izquierdo). Puntos clave: B(1380; 0), C(1380; −500), Dv(660; −1420), E(0; −1420). Decimales con la coma de tu configuración regional. Cada apartado termina en una línea **Comprobación**.

**Archivos de apoyo** (en la misma carpeta que esta guía):

- `GUIA_FAMILIA_REVIT.md`: esta guía.
- `Chimenea_esquina_diseno.png`: lámina de diseño (planta, alzado de la cara diagonal, sección A–A, perspectiva, parámetros y materiales) para mirar y comparar; no se importa.
- `Chimenea_esquina_diseno.pdf`: la misma lámina en PDF, para imprimir.
- `Chimenea_esquina_planta_familia.dxf`: solo la planta, con la esquina interior O en (0, 0); es el único DXF que se importa en el Editor de familias (atajo opcional del final de la guía).
- `Chimenea_esquina_plantilla.dxf`: alzado, sección y cotas a 1:1 en mm, solo para mirar y medir; su planta está desplazada (454; 1770) mm, no la importes.
- `Chimenea_esquina_3D.dxf`: modelo 3D de referencia visual y de volúmenes, con O en (0, 0, 0); no se importa para construir.
- `generar_chimenea.py`: script de Python (necesita ezdxf, matplotlib y numpy) que regenera los DXF y la lámina; no genera el `.rfa`.

**Comprobación:** tienes Revit abierto y los archivos de apoyo en una carpeta.

## 1. Nueva familia
1. Archivo (File) → Nuevo (New) → Familia (Family).
2. Elige la plantilla **`Modelo genérico métrico.rft`** (Metric Generic Model.rft) → Abrir.
3. Archivo → Guardar como → Familia → `Chimenea_Esquina_Minimalista.rfa`. Guarda tras cada apartado.
4. Crear (Create) → panel Propiedades → **Categoría y parámetros de familia** (Family Category and Parameters).
5. Categoría: **Equipamiento especializado** (Specialty Equipment).
6. Marca **Habilitar corte en vistas** (Enable Cutting in Views; el nombre en español puede variar). Existe desde Revit 2023 para esta categoría: sin ella, Equipamiento especializado **no se corta** en planta y verás la chimenea en proyección, sin el relleno de corte. En Revit 2022 o anterior la categoría no se puede cortar; si necesitas verla cortada, usa la categoría **Modelos genéricos** (Generic Models), que siempre se corta.
7. Marca **Siempre vertical** (Always vertical).
8. Desmarca **Delimitación de habitaciones** (Room Bounding), si aparece.
9. Comprueba que «Basado en plano de trabajo» (Work plane-based) está desmarcado y pulsa Aceptar.
10. Gestionar (Manage) → Unidades de proyecto (Project Units) → Longitud → botón de formato.
11. Unidades: **Milímetros**.
12. Redondeo: **2 decimales** (para ver 1168,25; luego puedes poner 0).
13. Símbolo de unidad: ninguno. Aceptar dos veces.
14. Navegador de proyectos (Project Browser) → Planos de planta → doble clic en **`Ref. Level`** (el nombre varía con el idioma). Todo el trabajo en planta se hace aquí.
15. Barra de control de vista → estilo visual **Sombreado** (Shaded).

**Comprobación:** estás en `Ref. Level`, con la categoría Equipamiento especializado, el corte en vistas activado y las unidades en mm con 2 decimales.

## 2. Parámetros y materiales
### 2.1 Tabla completa
Grupo «Cotas» = Dimensions; «Gráficos» = Graphics; «Materiales y acabados» = Materials and Finishes. Los nombres son **sin acentos ni espacios y distinguen mayúsculas** (las fórmulas los usan tal cual). En total son **26 parámetros (22 + 4 auxiliares)**.

| Nombre (abrev.) | Grupo | Tipo de parámetro | Tipo/Instancia | Valor | Fórmula |
|---|---|---|---|---|---|
| Ancho_Muro_Fondo (W) | Cotas | Longitud | Tipo | 1380 | — |
| Fondo_Muro_Izq (D) | Cotas | Longitud | Tipo | 1420 | — |
| Chaflan_X (CX) | Cotas | Longitud | Tipo | 720 | — |
| Chaflan_Y (CY) | Cotas | Longitud | Tipo | 920 | — |
| Solape_Muros (S) | Cotas | Longitud | Tipo | 100 | — |
| Zocalo_Alto (ZH) | Cotas | Longitud | Tipo | 60 | — |
| Zocalo_Retranqueo (ZR) | Cotas | Longitud | Tipo | 25 | — |
| Hogar_Ancho (OW) | Cotas | Longitud | Tipo | 850 | — |
| Hogar_Alto (OH) | Cotas | Longitud | Tipo | 600 | — |
| Hogar_Cota (OZ) | Cotas | Longitud | Tipo | 400 | — |
| Hogar_Fondo (OD) | Cotas | Longitud | Tipo | 450 | — |
| Marco_Ancho (MF) | Cotas | Longitud | Tipo | 20 | — |
| Marco_Prof (MD) | Cotas | Longitud | Tipo | 40 | — |
| Vidrio_Esp (VG) | Cotas | Longitud | Tipo | 10 | — |
| **Altura (H)** | Cotas | Longitud | **Instancia** | 2600 | — |
| **Ver_Vidrio** | Gráficos | Sí/No (Yes/No) | **Instancia** | marcado | — |
| Mat_Cuerpo | Materiales y acabados | Material | Tipo | material (al final de este apartado) | — |
| Mat_Marco | Materiales y acabados | Material | Tipo | material (al final de este apartado) | — |
| Mat_Vidrio | Materiales y acabados | Material | Tipo | material (al final de este apartado) | — |
| Mat_Hogar | Materiales y acabados | Material | Tipo | material (al final de este apartado; ver nota) | — |
| Long_Chaflan | Cotas | Longitud | Tipo | 1168,25 (calculado) | `sqrt(Chaflan_X ^ 2 + Chaflan_Y ^ 2)` |
| Margen_Hogar | Cotas | Longitud | Tipo | 159,12 (calculado) | `(Long_Chaflan - Hogar_Ancho) / 2` |

**Plan B de Long_Chaflan** si Revit avisa de «unidades inconsistentes»: `sqrt((Chaflan_X / 1 mm) ^ 2 + (Chaflan_Y / 1 mm) ^ 2) * 1 mm` (dividir por «1 mm» quita las unidades; multiplicar las devuelve). Ninguna de las dos variantes está probada en Revit.

**Parámetros auxiliares** (los añado yo; **no están en la especificación**). Revit extruye desde una cara en el sentido de su normal (hacia fuera) y la profundidad hacia dentro es un valor **negativo**; para no teclear −450 a mano (y perder el parámetro) se asocia a la extrusión un parámetro calculado negativo. Tipo, grupo **«Otros»** (Other), Longitud. Son **internos, no editar**:

| Nombre | Grupo | Valor (calculado) | Fórmula |
|---|---|---|---|
| Aux_Prof_Hogar | Otros | −450 | `-Hogar_Fondo` |
| Aux_Prof_Marco | Otros | −40 | `-Marco_Prof` |
| Aux_Vidrio_Ini | Otros | −15 | `-(Marco_Prof - Vidrio_Esp) / 2` |
| Aux_Vidrio_Fin | Otros | −25 | `-(Marco_Prof + Vidrio_Esp) / 2` |

**Plan B de Aux_Vidrio_*** si Revit rechaza el signo menos delante del paréntesis: `Aux_Vidrio_Ini = (Vidrio_Esp - Marco_Prof) / 2` y `Aux_Vidrio_Fin = (-Marco_Prof - Vidrio_Esp) / 2` (mismos valores, −15 y −25).

**Condición de diseño del hueco** (prudente): `Hogar_Ancho + 2 · Marco_Ancho ≤ Long_Chaflan − 100`. Con los valores por defecto: **Hogar_Ancho ≤ 1028,25** como máximo prudente, que equivale a **Margen_Hogar ≥ 70 mm** (= 50 + Marco_Ancho; el marco queda dentro del hueco, así que sumar 2·MF es solo prudencia).

**Aviso de valores:** una cota con valor **0 no se admite** (Revit da error de restricciones). Ningún parámetro que etiquete una cota (W, D, CX, CY, S, ZR, MF, OW, OH, OZ…) puede valer 0 ni salirse de su rango (CX < W, CY < D). **Tampoco pueden valer 0 ZH, OD, MD, VG ni H** (zócalo, marco, vidrio u hogar sin espesor; con inicio igual a final la extrusión da error; el mensaje exacto no lo sé). **Coherencia:** 2·MF < OW y 2·MF < OH; VG ≤ MD; MD < OD; OZ + OH < H; ZH < OZ; con los valores por defecto OD < 960 (hacia 962 la esquina P4 del fondo del hueco toca el plano del muro izquierdo). En las pruebas usa siempre ≥ 1 mm.

Nota sobre **Mat_Hogar**: el interior del hogar se **pinta** más adelante y, que yo sepa, la herramienta Pintar aplica un material fijo, no un parámetro. Mat_Hogar se crea por coherencia con la especificación; solo tendrá efecto si luego forras el hogar con láminas finas (camino que no he detallado ni probado).

### 2.2 Cómo crearlos
1. Crear → panel Propiedades → **Tipos de familia** (Family Types).
2. Pulsa **Nuevo tipo** (New Type).
3. Escribe el nombre `1380x1420` y pulsa Aceptar. Todos los valores se escriben dentro de este tipo.

Para **cada** parámetro de las tablas de 2.1 (los 26: 22 + 4 auxiliares) repite los pasos 4–12:

4. Pulsa **Nuevo parámetro** (New Parameter) (icono inferior del diálogo).
5. Elige *Parámetro de familia* (no compartido).
6. Escribe el **Nombre** tal cual está en la tabla (sin la abreviatura entre paréntesis).
7. Elige **Disciplina** «Común» y **Tipo de parámetro** «Longitud» (o «Sí/No» o «Material», según la tabla).
   - Si no funciona: ver apartado 12, fila 18.
8. En **Agrupar parámetros en** elige el grupo de la tabla (Cotas, Gráficos, Materiales y acabados u Otros).
9. Marca **Tipo** o **Instancia** según la tabla y pulsa Aceptar.
10. Parámetros calculados: escribe la expresión en la columna **Fórmula** (Formula); la celda de Valor se pone gris.
    - Si no funciona: ver apartado 12, fila 13.
11. Parámetros de longitud: escribe el valor en la columna Valor (los Mat_* se quedan en «Por categoría» hasta crear los materiales, al final de este apartado).
12. Ver_Vidrio: marca la casilla de su fila.
13. Al terminar, pulsa **Aplicar**.

Nota: puedes subir o bajar parámetros con las flechas del diálogo. Si prefieres crearlos sobre la marcha, al etiquetar una cota usa Etiqueta → «‹Añadir parámetro…›».

**Comprobación:** en Tipos de familia aparecen 26 parámetros; con los valores por defecto Long_Chaflan = 1168,25, Margen_Hogar = 159,12, Aux_Prof_Hogar = −450, Aux_Prof_Marco = −40, Aux_Vidrio_Ini = −15 y Aux_Vidrio_Fin = −25.

### 2.3 Materiales y su asociación a los parámetros
1. Gestionar → **Materiales** (Materials).
2. Abajo a la izquierda: «Crear y duplicar material» → **Nuevo material genérico**.
3. Renómbralo con el nombre de la tabla.
4. Pestaña Gráficos (Graphics): color RGB y transparencia de la tabla; pon el mismo color en Sombreado (o marca «Usar apariencia de render para sombreado»).
5. Pestaña Apariencia (Appearance): el recurso orientativo de la tabla.
   - Si no funciona: los nombres de los recursos de apariencia varían entre versiones; elige el más parecido.
6. Repite los pasos 2–5 con los otros tres materiales.

| Material (nombre) | Color RGB | Transparencia (Gráficos) | Apariencia orientativa |
|---|---|---|---|
| Chimenea - Microcemento blanco roto | 214, 210, 202 | 0 | Genérico, mate; patrón de corte: relleno sólido gris (o el de tu plantilla) |
| Chimenea - Acero negro | 28, 28, 28 | 0 | Genérico/metal pintado, satinado |
| Chimenea - Vidrio claro | 230, 238, 240 (orientativo) | ≈ 85 | Recurso de apariencia «Vidrio» (Glass), claro |
| Chimenea - Hogar negro mate | 40, 40, 40 | 0 | Genérico, mate |

7. Tipos de familia → fila Mat_Cuerpo → celda Valor → botón «…» → «Chimenea - Microcemento blanco roto».
8. Repite con Mat_Marco = Acero negro, Mat_Vidrio = Vidrio claro y Mat_Hogar = Hogar negro mate.
9. Pulsa Aplicar.

**Comprobación:** los cuatro Mat_* muestran su material en Tipos de familia (ninguno en «Por categoría»).

## 3. Planos de referencia y cotas
### 3.1 Receta para cada plano (repítela 8 veces, planos 3 a 10)
1. En `Ref. Level`: Crear → panel Referencia → **Plano de referencia** (Reference Plane).
2. Dibuja la línea ya del lado correcto del origen, a ojo (verticales de abajo arriba, horizontales de izquierda a derecha) y **larga (≈ 3000 mm, sobrepasando el cuerpo por ambos lados)**, para que sus intersecciones existan y los bocetos bloqueados sigan teniéndolas al cambiar W o D.
3. Selecciónalo → Propiedades → **Nombre** (Name) = el de la tabla.
4. Anotar (Annotate) → **Cota alineada** (Aligned).
5. Clic en el plano de partida, clic en el nuevo y clic en vacío para colocar la cota.
6. Clic en el valor de la cota y teclea el valor (el plano se mueve).
7. Con la cota seleccionada: barra de opciones → **Etiqueta** (Label) → el parámetro.
8. Comprueba en Tipos de familia que el parámetro conserva su valor; si Revit lo cambió, reescríbelo y Aplicar.

Los pasos 4–8 forman la receta **«cota + etiqueta»** que reutilizan los apartados siguientes (cuando el parámetro ya da el valor, salta el paso 6).

### 3.2 Tabla de planos
| # | Nombre | Orientación | Posición | Cota que lo define → parámetro | Es referencia |
|---|---|---|---|---|---|
| 1 | Origen_X | Vertical | X = 0 | plano de plantilla «Centro (izquierda/derecha)» renombrado | ver nota de los planos 1 y 2 |
| 2 | Origen_Y | Horizontal | Y = 0 | plano de plantilla «Centro (delante/detrás)» renombrado | ver nota de los planos 1 y 2 |
| 3 | RP_Ancho | Vertical | X = 1380 | Origen_X → RP_Ancho = Ancho_Muro_Fondo | No es una referencia |
| 4 | RP_Fondo | Horizontal | Y = −1420 | Origen_Y → RP_Fondo (hacia abajo) = Fondo_Muro_Izq | No es una referencia |
| 5 | RP_Chaflan_X | Vertical | X = 660 | RP_Chaflan_X → RP_Ancho = Chaflan_X | No es una referencia |
| 6 | RP_Chaflan_Y | Horizontal | Y = −500 | RP_Fondo → RP_Chaflan_Y (hacia arriba) = Chaflan_Y (920) | No es una referencia |
| 7 | RP_Anclaje_X | Vertical | X = −100 | Origen_X → RP_Anclaje_X (a la izquierda) = Solape_Muros | No es una referencia |
| 8 | RP_Anclaje_Y | Horizontal | Y = +100 | Origen_Y → RP_Anclaje_Y (arriba) = Solape_Muros | No es una referencia |
| 9 | RP_ZR_Der | Vertical | X = 1355 | RP_ZR_Der → RP_Ancho = Zocalo_Retranqueo | No es una referencia |
| 10 | RP_ZR_Frente | Horizontal | Y = −1395 | RP_ZR_Frente → RP_Fondo = Zocalo_Retranqueo | No es una referencia |

**Planos 1 y 2:** la plantilla ya trae dos planos centrales cruzados en el origen. **No dibujes otros**; no los muevas.

1. Selecciona el plano central vertical → Propiedades → Nombre = `Origen_X`.
2. Selecciona el plano central horizontal → Nombre = `Origen_Y`.
   - Si no funciona: Desanclar (Unpin; el nombre en tu idioma puede variar) y repite; ver apartado 12, fila 15.
3. Mira «Es referencia» en cada uno: si ya indica «Centro (izquierda/derecha)» o «Centro (delante/detrás)», déjalo (también sirve para Alinear en el proyecto).
4. Cámbialo a «Referencia fuerte» (Strong Reference) **solo** si indica «No es una referencia».

Orden de los demás: 3–4, 5–6, 7–8, 9–10. El plano 10 queda entre Origen_Y y RP_Fondo (25 mm sobre RP_Fondo); haz zoom para colocar las cotas.

**Chaflán:** no hacen falta líneas de referencia (Reference Line). Los dos extremos salen de intersecciones de planos: **Dv = RP_Chaflan_X ∩ RP_Fondo = (660; −1420)** y **C = RP_Ancho ∩ RP_Chaflan_Y = (1380; −500)**. Por eso los planos 5 y 6 existen: llevan CX y CY.

**No confundas** Y = −1395 (plano RP_ZR_Frente: 1420 − 25) con 1394,9, que es la distancia perpendicular de la esquina O al plano del chaflán. En el eje del hogar, la profundidad hasta el muro izquierdo es 1295,2 (OD = 450 cabe de sobra).

**Comprobación:** 10 planos con su nombre; en Tipos de familia, con CX = 720 y CY = 920, Long_Chaflan = 1168,25 y Margen_Hogar = 159,12; los valores por defecto de los parámetros siguen intactos.

## 4. Cuerpo (pentágono)
1. En `Ref. Level`: Crear → panel Formas (Forms) → **Extrusión** (Extrusion). Se abre la pestaña «Modificar | Crear perfil de extrusión».
2. Panel Dibujar → **Elegir líneas** (Pick Lines).
3. Barra de opciones: Desfase (Offset) `0`.
4. Marca **Bloquear** (Lock).
5. Desmarca **Cadena** (Chain).
6. Clic sobre Origen_Y, Origen_X, RP_Ancho y RP_Fondo. Salen 4 líneas con candado sobre los planos.
7. Pestaña Modificar → panel **Modificar** → **Recortar/Extender a esquina** (Trim/Extend to Corner).
8. En cada una de las 4 esquinas, clic en las dos líneas por el lado que quieres conservar. Resultado: rectángulo 1380 × 1420 con vértices O, B, K(1380; −1420), E.
9. Panel Dibujar → **Línea** (Line).
10. Desmarca «Cadena» en la barra de opciones.
11. Dibuja el chaflán: clic 1 en la intersección RP_Fondo ∩ RP_Chaflan_X (el cursor indica «Intersección») y clic 2 en RP_Ancho ∩ RP_Chaflan_Y.
12. Recortar/Extender a esquina: clic en la diagonal y en la línea derecha (conserva el tramo B–C, el de arriba).
13. Recortar/Extender a esquina: clic en la diagonal y en la línea inferior (conserva el tramo Dv–E, el de la izquierda). Desaparece la esquina K; quedan **5 líneas en lazo cerrado**: O–B–C–Dv–E.
14. **Fijar los extremos del chaflán** (para que siga a CX y CY): Modificar → **Alinear** (Align).
15. Clic en el plano RP_Chaflan_X y luego en el extremo Dv de la diagonal (pasa el cursor hasta que se resalte el punto final).
16. Pulsa el candado que aparece.
17. Repite los pasos 15–16 con RP_Chaflan_Y y el extremo C.
    - Si no funciona: ver apartado 12, fila 2.
18. Paleta Propiedades (Properties) → **Extrusión final** (Extrusion End) → botoncito de la derecha («Asociar parámetro de familia», Associate Family Parameter) → **Altura**. Así la altura queda enlazada al parámetro de instancia.
19. **Extrusión inicial** (Extrusion Start) → botoncito → **Zocalo_Alto** (el cuerpo arranca sobre el zócalo).
20. **Finalizar modo de edición** (Finish Edit Mode, marca de verificación verde).
21. Abre la vista 3D y mira el pentágono.
22. En Tipos de familia pon Chaflan_X = 600 y Aplicar: el chaflán debe moverse. Devuélvelo a 720.
    - Si no funciona: ver apartado 12, fila 2.

**Comprobación:** en 3D, un pentágono liso de 60 a 2600 de altura; Chaflan_X = 600 mueve el chaflán y de vuelta a 720 queda como antes.

## 5. Zócalo retranqueado y anclaje
### 5.1 Zócalo (Z 0 → 60, retranqueado 25)
Usa los planos 9 y 10 (creados en el apartado 3).

1. Crear → Extrusión.
2. Panel Dibujar → Elegir líneas con la misma barra de opciones que en el apartado 4 (Desfase `0`, **Bloquear** marcado, Cadena desmarcada).
3. Clic en Origen_Y, Origen_X, **RP_ZR_Der** y **RP_ZR_Frente**.
4. Recortar/Extender a esquina en las 4 esquinas → rectángulo.
5. Elegir líneas con **Desfase = 25** (Bloquear sigue marcado).
6. Acerca el cursor al **borde del chaflán del cuerpo** (la línea oblicua que ves en planta) y mueve el cursor hacia la esquina interior (hacia O) hasta que la línea previa quede *dentro*; clic.
   - Si no funciona: ver apartado 12, fila 16.
7. Recortar/Extender a esquina: diagonal + línea derecha.
8. Recortar/Extender a esquina: diagonal + línea frontal. Lazo cerrado de 5 líneas.
9. Propiedades: Extrusión inicial `0`.
10. Extrusión final → botoncito → **Zocalo_Alto**.
11. Finalizar modo de edición.

Límite conocido: el desfase de 25 del paso 5 queda **fijo** (no queda ligado a Zocalo_Retranqueo); si cambias ZR, ese lado no lo sigue (ver apartado 12, fila 12).

### 5.2 Anclaje en L (Z 0 → H, se oculta en planta más adelante)
**S debe ser menor que el grosor de los muros del proyecto**; si tus muros son finos, baja Solape_Muros (p. ej. 50) en ese tipo, o la tira asomará por la otra cara del muro. Usa los planos 7 y 8.

1. Crear → Extrusión.
2. Elegir líneas (misma barra de opciones que en el apartado 4).
3. Clic en **RP_Anclaje_Y, RP_Ancho, Origen_Y, Origen_X, RP_Fondo, RP_Anclaje_X** (las 6 líneas).
4. Recortar/Extender a esquina entre cada par contiguo hasta cerrar el polígono en L: (−S, S) → (W, S) → (W, 0) → (0, 0) → (0, −D) → (−S, −D) → vuelta. Es una tira de 100 sobre el muro de fondo y otra de 100 a la izquierda del muro izquierdo; con S menor que el grosor, ambas quedan **dentro de los muros**.
5. Propiedades: Extrusión inicial `0`.
6. Extrusión final → botoncito → **Altura**.
7. Finalizar modo de edición.

**Comprobación:** en 3D, un zócalo de 60 de alto retranqueado 25 respecto a las tres caras vistas, bajo el cuerpo, y una L pegada a los dos lados que dan a los muros; de momento el anclaje también se ve en planta.

## 6. Hogar (hueco, marco, vidrio, interior)
### 6.1 Preparar una vista para dibujar en la cara del chaflán
Recomendado, para poder acotar con cotas permanentes: una **sección paralela a la cara**.

1. En `Ref. Level`: Vista (View) → Crear (Create) → **Sección** (Section).
2. Dibuja la sección: clic 1 en Dv y clic 2 en C (ajústalos a «Punto final» del borde del chaflán, para que sea exactamente paralela).
3. Comprueba que la flecha de la sección mira hacia la esquina (el sentido Dv→C lo hace).
   - Si no funciona: selecciona la sección y pulsa el símbolo de voltear (Flip).
4. Selecciona la línea de sección y **Mover** (Move) unos 300 mm hacia la sala (abajo-derecha en planta), sin girar: una traslación mantiene el paralelismo.
5. Doble clic en la cabeza de la sección para abrirla.
6. Renómbrala `Cara_chaflan`.
7. Comprueba que ves la cara de frente, `Ref. Level` como línea horizontal y las aristas verticales de la cara en Dv (izquierda) y C (derecha).
   - Si no funciona: ver apartado 12, fila 17.

Alternativa mínima: trabajar en la vista **3D** en vez de la sección; allí la herramienta Cota puede estar desactivada (ver apartado 12, fila 6).

### 6.2 Plano de trabajo sobre la cara
1. Con la sección `Cara_chaflan` abierta: Crear → panel Plano de trabajo (Work Plane) → **Establecer** (Set).
2. Elige «**Elegir un plano**» (Pick a plane) → Aceptar.
3. Clic en la cara del chaflán (la cara grande, entre las dos aristas verticales).
4. Si se abre el diálogo **«Ir a vista»** (Go To View), elige `Sección: Cara_chaflan`.
   - Si no funciona: ver apartado 12, fila 5.
5. Plano de trabajo → **Mostrar** (Show): el plano debe coincidir con la cara.

### 6.3 Centro del hogar y vaciado con cotas
Primero el plano de centro y su cota, **antes** de pulsar Extrusión de vaciado (así esas restricciones no se crean con un boceto abierto):

1. En la sección `Cara_chaflan`: Crear → panel Referencia → Plano de referencia; dibuja una línea vertical hacia el centro de la cara.
2. Propiedades → Nombre = `RP_Hogar_Centro`.
3. Anotar → Cota alineada: clic en la arista izquierda de la cara (en Dv), clic en `RP_Hogar_Centro`, clic en la arista derecha (en C) y clic en vacío para colocarla (con Tab alterna entre «arista» y «cara» hasta que se resalte la arista vertical).
4. Pulsa el símbolo **EQ** (igualdad) de la cota.
   - Si no funciona: ver apartado 12, fila 6.

Después el vaciado:

5. Crear → Formas → desplegable **Vaciado** (Void Forms) → **Extrusión de vaciado** (Void Extrusion).
6. Dibujar → **Rectángulo** (Rectangle): dos clics dentro de la cara, a ojo ≈ 850 × 600.
7. Cota + etiqueta (3.1, pasos 4–8): de la línea `Ref. Level` al lado inferior del rectángulo, Etiqueta **Hogar_Cota**.
   - Si no funciona: crea en la sección un plano horizontal alineado con candado a `Ref. Level` y acota a ese plano.
8. Cota + etiqueta: del lado inferior al superior, Etiqueta **Hogar_Alto**.
9. Cota + etiqueta: del lado izquierdo al derecho, Etiqueta **Hogar_Ancho**.
10. Centrado del rectángulo: cota alineada de 3 referencias (lado izquierdo → `RP_Hogar_Centro` → lado derecho).
11. Pulsa **EQ**.
12. Resultado esperado (cotas temporales): márgenes de 159,12 a cada lado y base a Z = 400.
13. Propiedades: Extrusión inicial `0`.
14. **Extrusión final** → botoncito → **Aux_Prof_Hogar** (−450).
15. Finalizar modo de edición.
16. Abre `Ref. Level` y comprueba que el hueco se ve **dentro** del pentágono (P1–P2 en la cara, P3–P4 450 mm hacia la esquina).
    - Si no funciona: el plano de trabajo de una cara apunta hacia **fuera** del sólido y un valor negativo entra en el cuerpo (por eso OD lleva signo menos); si el hueco sale **hacia fuera**, cambia la fórmula de Aux_Prof_Hogar a `Hogar_Fondo` (sin signo); ver apartado 12, fila 3.

**Comprobación:** hueco de 850 × 600 centrado en la cara, con la base a Z = 400 y 450 de profundidad hacia la esquina.

### 6.4 Marco (anillo a ras de la cara)
1. Plano de trabajo → Mostrar: comprueba que el plano activo sigue siendo la cara.
   - Si no funciona: repite 6.2.
2. Crear → **Extrusión** (sólida, no vaciado).
3. Bucle exterior: Elegir líneas con **Bloquear** (Desfase `0`) sobre las 4 aristas del hueco.
   - Si no funciona: ver apartado 12, fila 16.
4. Bucle interior: Dibujar → Rectángulo cualquiera dentro del anterior.
5. Cota + etiqueta entre un lado exterior y su lado interior paralelo, Etiqueta **Marco_Ancho** (20).
6. Repite el paso 5 en los otros 3 lados (4 cotas, todas con Marco_Ancho).
7. Propiedades: Extrusión inicial `0`.
8. Extrusión final → botoncito → **Aux_Prof_Marco** (−40).
9. Finalizar modo de edición.

**Comprobación:** en 3D, un anillo de 20 de ancho visto y 40 de profundidad, a ras de la cara.

### 6.5 Vidrio
1. Crear → Extrusión.
2. Elegir líneas con Bloquear sobre los 4 lados del **bucle interior del marco** (rectángulo de 810 × 560).
   - Si no funciona: ver apartado 12, fila 16.
3. Propiedades: Extrusión inicial → botoncito → **Aux_Vidrio_Ini** (−15).
4. Extrusión final → botoncito → **Aux_Vidrio_Fin** (−25) (lámina de 10 centrada en los 40 del marco).
5. Propiedades → **Visible** → botoncito → **Ver_Vidrio**.
6. Finalizar modo de edición.

### 6.6 El vaciado también corta el marco y el vidrio: solución
El marco y el vidrio están enteros dentro del volumen del vaciado, así que Revit puede recortarlos hasta hacerlos desaparecer (depende de la versión y del orden de creación).

1. Modificar → panel Geometría (Geometry) → desplegable **Cortar** (Cut) → **Anular corte de geometría** (Uncut Geometry).
2. Clic en el **vaciado** y luego en el **marco**.
   - Si no funciona: invierte el orden (primero el marco).
3. Clic en el **vaciado** y luego en el **vidrio**.
4. Pulsa Esc para salir.

**Comprobación:** en 3D (con Ver_Vidrio marcado) se ven el marco y el vidrio llenando el hueco, que sigue abierto detrás; en Tipos de familia, desmarcar Ver_Vidrio (Aplicar) oculta el vidrio (vuelve a marcarlo). Si no: ver apartado 12, fila 4.

### 6.7 Pintar el interior del hogar
1. En 3D, selecciona marco y vidrio.
2. Barra de control de vista → gafas **Ocultar/aislar temporalmente** → Ocultar elemento.
3. Modificar → panel Geometría → **Pintar** (Paint).
4. En el Explorador de materiales elige «Chimenea - Hogar negro mate» (creado en 2.3).
5. Clic en las **5 caras interiores**: fondo, izquierda, derecha, techo y suelo del hueco.
6. Pulsa Terminado (Done).
7. Gafas → **Restablecer ocultar/aislar temporal**.

Si usaste «Ocultar en vista → Elementos» (permanente): bombilla (Mostrar elementos ocultos) → selecciona marco y vidrio → Mostrar elemento.

Pintar no es paramétrico y **no sé si la pintura sobrevive** cuando cambian los parámetros (Revit regenera las caras del hueco). Si se pierde: ver apartado 12, fila 20.

**Comprobación:** en 3D el interior del hogar se ve negro mate y el marco y el vidrio vuelven a verse.

## 7. Subcategorías y asociación a las formas
### 7.1 Crear las subcategorías
1. Gestionar → Configuración (Settings) → **Estilos de objeto** (Object Styles).
2. Pestaña Objetos de modelo.
3. Categoría Equipamiento especializado → **Modificar subcategorías** → **Nuevo** (New).
4. Escribe `Cuerpo` y Aceptar.
5. Repite el paso 4 con `Zocalo`, `Marco`, `Vidrio`, `Hogar` y `Anclaje` (6 en total).
6. Grosores sugeridos: Cuerpo proyección 2 / corte 3; las demás 1. Aceptar.

### 7.2 Asociar material y subcategoría a cada forma
1. Selecciona una forma (clic en 3D o Tab).
2. Propiedades → **Material** → botoncito (asociar parámetro) → el parámetro de la tabla.
3. Propiedades → **Subcategoría** (Subcategory) → elige la de la tabla en su desplegable (la subcategoría no tiene botón de asociar; solo Material lo tiene).
4. Repite con cada forma de la tabla.

| Forma | Subcategoría | Material (parámetro) |
|---|---|---|
| Cuerpo | Cuerpo | Mat_Cuerpo |
| Zócalo | Zocalo | Mat_Cuerpo |
| Anclaje | Anclaje | Mat_Cuerpo |
| Marco | Marco | Mat_Marco |
| Vidrio | Vidrio | Mat_Vidrio |
| Interior del hogar | — | pintado con el material del hogar (fijo; la pintura no admite parámetro) |

Opcional si necesitas el material del hogar como parámetro: forra el hueco con 5 láminas finas (p. ej. 2 mm) con Mat_Hogar y aplícales Anular corte; no he detallado este camino.

**Comprobación:** al seleccionar cada forma, Material muestra el botoncito asociado y la subcategoría de la tabla; en 3D cada pieza tiene su color.

## 8. Representación en planta y niveles de detalle
### 8.1 Líneas simbólicas del hueco (discontinuas)
1. En `Ref. Level`: Propiedades → Rango de vista (View Range) y comprueba el plano de corte (por defecto 1200 mm). El hogar (Z 400–1000) queda por debajo del corte, por eso se dibuja con líneas simbólicas.
2. Crear → panel Detalle (Detail) → **Línea simbólica** (Symbolic Line).
3. Barra de opciones: Subcategoría = **Hogar** (desplegable).
4. Dibuja el rectángulo P1–P2–P3–P4 (valores del tipo por defecto, en mm): **P1(758,1; −1294,7), P2(1281,9; −625,3), P3(927,6; −348,0), P4(403,7; −1017,4)**. P1–P2 coincide con la cara; P3–P4 es el fondo. Encájalo con Elegir líneas sobre las aristas del vaciado.
   - Si no funciona: ver apartado 12, fila 16.
5. Gestionar → Estilos de objeto → Objetos de modelo → Equipamiento especializado → Hogar → Patrón de línea: uno **discontinuo** (el nombre, p. ej. «Línea oculta», depende de tu plantilla).

**Limitación:** las líneas simbólicas son **de la familia, no del tipo**, y no siguen a los parámetros: valen solo para el tipo por defecto (1380x1420 con los valores por defecto). En otro tipo con distintos W, D, CX, CY, OW u OD el rectángulo discontinuo de planta queda desfasado respecto al hueco real; el rectángulo está inclinado, así que no se puede acotar a planos ortogonales.

**Método alternativo (no probado):** para otro tipo, dibuja un rectángulo propio con la subcategoría Hogar y, en sus Propiedades, asocia **Visible** a un parámetro Sí/No de tipo (p. ej. `Simb_1500x1500`), marcado solo en ese tipo; asocia el rectángulo original a su propio Sí/No (`Simb_1380x1420`) y márcalo solo en su tipo. Vértices de cualquier tipo: C = (W; −(D − CY)), Dv = (W − CX; −D), M = punto medio de Dv–C, d = (CX; CY) / Long_Chaflan, n = (−CY; CX) / Long_Chaflan; P1 = M − (OW/2)·d, P2 = M + (OW/2)·d, P3 = P2 + OD·n, P4 = P1 + OD·n.

### 8.2 Anclaje invisible en planta
1. Selecciona el Anclaje (Tab en 3D).
2. Propiedades → **Visibilidad/Gráficos** (Visibility/Graphics Overrides) → «Editar…» (Family Element Visibility Settings).
3. Desmarca las **cuatro** casillas: «Plano/RCP» (Plan/RCP), «Frontal/Posterior», «Izquierda/Derecha» y «Cuando se corta en Plano/RCP».
4. Deja marcados **Basto, Medio y Fino**.
5. Aceptar.
   - Si no funciona: ver apartado 12, fila 10.

Con el plano de corte a 1200 el anclaje (Z 0 → H) queda cortado, así que la casilla decisiva en planta es **probablemente** «Cuando se corta en Plano/RCP» (probable, no probado). Este diálogo no controla las vistas 3D: allí el anclaje seguirá existiendo (queda dentro de los muros); si estorba, desmarca la subcategoría Anclaje en Visibilidad/Gráficos del proyecto.

**Comprobación:** en `Ref. Level` el anclaje no se ve; en 3D sí.

### 8.3 Niveles de detalle (mismo diálogo de visibilidad, por forma)
1. Selecciona el Zócalo → Propiedades → Visibilidad/Gráficos → Editar… → desmarca **Basto**.
2. Repite con el Marco y con el Vidrio.
3. Selecciona las líneas simbólicas del hogar → Visibilidad/Gráficos → Editar… → desmarca **Basto**.
4. Deja las demás casillas como indica la tabla.

| Forma | Basto | Medio | Fino | Plano/RCP | Cuando se corta en Plano/RCP | Frontal/Posterior e Izquierda/Derecha |
|---|---|---|---|---|---|---|
| Cuerpo | Sí | Sí | Sí | Sí | Sí (se ve cortado a 1200) | Sí |
| Zócalo | No | Sí | Sí | Sí | Sí | Sí |
| Marco | No | Sí | Sí | Sí | Sí | Sí |
| Vidrio | No | Sí | Sí | Sí | Sí | Sí |
| Anclaje | Sí | Sí | Sí | **No** | **No** | **No** |
| Líneas simbólicas del hogar | No | Sí | Sí | (solo existen en planta) | — | — |

- **Basto:** el cuerpo queda con su base 60 mm por encima del suelo (es lo especificado; si no te gusta, deja el zócalo también en Basto). La especificación dice «Basto = solo cuerpo»; aquí el anclaje también está en Basto (Basto = cuerpo + anclaje), pero no se ve en planta ni en alzados y en 3D queda dentro de los muros.
- **Líneas simbólicas en Basto:** las dejo ocultas en Basto (decisión de esta guía, no de la especificación). En un proyecto, las plantas a 1:100 suelen estar en Basto: no verás el hueco discontinuo hasta pasar la vista a Medio o Fino. Si prefieres verlo siempre, marca también Basto en las líneas simbólicas.

**Comprobación:** en `Ref. Level` se ve el rectángulo discontinuo sobre el hueco y, con el control «Nivel de detalle» de la barra inferior (Basto / Medio / Fino), en planta y en 3D, la tabla se cumple. Si no ves las líneas del hogar en el proyecto: ver apartado 12, fila 21.

## 9. Prueba de flexión
Haz cada prueba en Tipos de familia: cambia el valor, **Aplicar**, mira planta y 3D, y vuelve al valor original. Si Revit protesta, deshaz (Ctrl+Z).

| # | Cambio | Qué debe pasar | Fallos típicos |
|---|---|---|---|
| 1 | W: 1380 → 1500 | Cara derecha, chaflán y zócalo se desplazan 120 a la derecha; el anclaje se alarga 120 por la derecha (su borde izquierdo, X = −100, no se mueve); Dv pasa a (780; −1420); la longitud del chaflán no cambia (1168,25) | La cara derecha no se mueve: línea sin candado; el zócalo no acompaña: RP_ZR_Der sin cota a RP_Ancho (apartado 3) |
| 2 | D: 1420 → 1600 | Frente y chaflán bajan 180; C = (1380; −680), Dv = (660; −1600); el hueco sigue centrado en el chaflán; el anclaje se alarga hacia abajo | El hueco se queda atrás: no está centrado por EQ; el anclaje no se alarga |
| 3 | CX: 720 → 600 | Dv se mueve a (780; −1420); Long_Chaflan = 1098,36 y Margen_Hogar = 124,18; el hueco sigue centrado | **El chaflán no se mueve**: extremos sin alinear (apartado 4, pasos 14–17); hueco descentrado |
| 4 | CY: 920 → 800 | C = (1380; −620); Long_Chaflan = 1076,29; Margen_Hogar = 113,14 | Igual que la prueba 3 |
| 5 | OW: 850 → 700 (también 1000) | Hueco, marco y vidrio se estrechan simétricamente; con 700 el margen es 234,12; con 1000 el margen es 84,12 | Marco o vidrio no siguen (no están bloqueados a las aristas); con OW > 1028,25 el Margen_Hogar baja de 70 mm y se incumple la condición de diseño; hacia 1168 el hueco ocupa toda la cara |
| 6 | H: 2600 → 2400 (instancia) | Solo cuerpo y anclaje cambian; zócalo y hueco no; en un proyecto, dos instancias con distinta Altura | Altura aparece como parámetro de tipo (cambia todas): vuelve a crearlo como Instancia |
| 7 | OZ: 400 → 600 y OH: 600 → 800 | El hueco, el marco y el vidrio suben y crecen; con OZ + OH = 1400 el hueco sobrepasa el plano de corte (1200): en planta se verá cortado y las líneas simbólicas ya no tienen sentido | Marco o vidrio no siguen: no están bloqueados a las aristas del hueco |
| 8 | OD: 450 → 300 | El fondo del hueco se acorta (P3–P4 a 300 de la cara); marco y vidrio no cambian; OD debe seguir siendo > MD (40) y < 960 | El hueco sale hacia fuera: cambia el signo de Aux_Prof_Hogar (apartado 12, fila 3) |
| 9 | MF: 20 → 30 y MD: 40 → 60 | El marco engorda y se hace más profundo; el vidrio sigue centrado en la profundidad del marco (Aux_Vidrio_*) | El vidrio no se centra: Aux_Vidrio_* mal asociados; el marco no engorda: sus 4 cotas no llevan Marco_Ancho |
| 10 | ZR: 25 → 40 | Retroceden el lado derecho y el frontal del zócalo; el chaflán del zócalo **NO** (su desfase de 25 es fijo, apartado 5.1) y el zócalo queda irregular. Devuelve ZR a 25 | El lado derecho o el frontal no se mueven: RP_ZR_* sin cota a RP_Ancho / RP_Fondo |
| 11 | S: 100 → 150 y ZH: 60 → 100 | El anclaje se ensancha 50 (bordes en X = −150 e Y = +150); el zócalo mide 100 y el cuerpo arranca a Z = 100 (con S ≥ grosor del muro el anclaje asoma por la otra cara) | El cuerpo no sube: Extrusión inicial sin asociar a Zocalo_Alto; RP_Anclaje_* sin cota a Solape_Muros |
| 12 | Con el hogar ya pintado: OW: 850 → 700 y OZ: 400 → 500 | El interior del hogar sigue negro mate | Pierde el pintado (no lo he podido comprobar): repíntalo (6.7); Mat_Hogar no es paramétrico (apartado 12, fila 20) |

Pruebas rápidas extra: desmarcar Ver_Vidrio oculta el vidrio; Basto/Medio/Fino se comportan como en 8.3; el anclaje no se ve en planta.

**Comprobación:** tras cada prueba, el valor vuelve al original y el modelo se regenera sin errores.

## 10. Guardar, cargar y colocar en el proyecto
### 10.1 Guardar y crear otros tipos
1. Con todos los valores por defecto: Archivo → Guardar como `Chimenea_Esquina_Minimalista.rfa`. Tipo ya creado: `1380x1420` (convención W×D).
2. (Opcional) Tipos de familia → Nuevo tipo → p. ej. `1500x1500`.
3. Escribe W = 1500 y D = 1500; respeta CX < W, CY < D, la condición del hogar (2.1) y S menor que el grosor del muro.
4. Aplicar.

**Aviso:** al crear tipos que muevan el hueco (W, D, CX, CY, OW, OD), el símbolo de planta no lo sigue (ver 8.1, limitación y método alternativo no probado).

### 10.2 Cargar en el proyecto
1. Abre el proyecto.
2. En la familia: Crear → panel Editor de familias → **Cargar en proyecto** (Load into Project).

### 10.3 Colocar
1. Proyecto: Arquitectura → Componente (Component) → **Colocar un componente** (Place a Component).
2. Elige el tipo `1380x1420`.
3. En planta, lleva el cursor a la esquina interior; ajusta al punto de la esquina (origen = esquina).
4. Clic. Revit coloca la familia libre, a nivel (no alojada).

### 10.4 Alinear a los muros
1. Modificar → **Alinear** (Align).
2. Clic en la **cara interior del muro de fondo**.
3. Pasa el cursor sobre la chimenea y con Tab elige el plano **Origen_Y**; clic.
4. Pulsa el **candado**.
5. Alinear → clic en la cara interior del muro izquierdo.
6. Con Tab elige el plano **Origen_X**; clic.
7. Pulsa el candado.
   - Si no funciona: tu muro izquierdo está inclinado 2,39° y la familia es ortogonal; Alinear exige caras paralelas y probablemente lo rechace (apartado 12, fila 9). Entonces no hay candado en X: deja la familia con el origen exacto en la esquina (con el ajuste de punto) y bloquea solo en Y.

Como el muro izquierdo se mete hasta 59 mm hacia la sala en el frente, el cuerpo y el muro se solapan y no queda hueco; el anclaje de 100 cubre además el caso contrario (muro inclinado hacia fuera).

### 10.5 Altura e instancia
1. Selecciona la instancia → Propiedades → **Altura** = altura libre hasta el techo (cara inferior del techo o falso techo) menos el acabado, por ejemplo 2600.
2. Cambia aquí Ver_Vidrio si lo necesitas. El parámetro de instancia permite valores distintos por chimenea.

### 10.6 Habitación «CHIMENEA» existente
La familia no delimita habitaciones. Dos opciones:
- **Conservarla** si quieres su área en tablas: la chimenea queda dentro de la habitación, su área incluirá la huella de 1,63 m² y los límites no coinciden exactamente con la familia (**diferencias de hasta 20 mm en las líneas de separación y de hasta 59 mm en el muro izquierdo**, por la cuña de desvío).
- **Borrar la habitación y sus líneas de separación** si solo era para dibujar el nicho; la zona pasa a la habitación contigua.

### 10.7 Otra esquina
El modelo está dibujado para la esquina arriba-izquierda.

| Esquina | Operación |
|---|---|
| Superior derecha | **Reflejar - Seleccionar eje** (Mirror - Pick Axis) con un eje vertical |
| Inferior izquierda | Reflejar con un eje horizontal |
| Inferior derecha | **Girar** (Rotate) 180° |

Después repite el Alinear con los muros (10.4). Si el chaflán 720 × 920 te resulta asimétrico, es lo esperado: se refleja tal cual.

**Comprobación:** la chimenea está en la esquina con el origen sobre ella, la Altura es la del techo y en planta se ve el cuerpo cortado.

## 11. Atajo de comprobación con el DXF de planta
Opcional; puedes hacerlo en cuanto existan los planos de origen y el cuerpo (apartado 4). Usa **solo** `Chimenea_esquina_planta_familia.dxf`: contiene únicamente la planta, con la esquina interior O en (0, 0) exacto y las capas CHM-PERFIL, CHM-ZOCALO, CHM-HOGAR, CHM-EJES (y, si la trae, CHM-ANCLAJE); todo cae dentro de X −110…1400 e Y −1430…110 mm.

`Chimenea_esquina_plantilla.dxf` (alzado, sección, cotas) es **solo para mirar y medir**: su planta está desplazada (454; 1770) mm, no la importes. `Chimenea_esquina_3D.dxf` es referencia visual y de volúmenes (O en (0, 0, 0)); no se importa para construir.

1. En `Ref. Level` del Editor de familias: Insertar (Insert) → **Importar CAD** (Import CAD).
2. Elige `Chimenea_esquina_planta_familia.dxf`.
3. Marca **Solo vista actual** (Current view only).
4. Colores: Conservar.
5. Unidades de importación: **Milímetros**.
6. Posicionamiento: **Origen a origen** (Origin to Origin).
7. Desmarca «Corregir líneas ligeramente desviadas».
8. Pulsa Abrir.
   - Si no funciona: ver apartado 12, fila 19.
9. Comprueba que la cruz de CHM-EJES cae en el cruce de los planos Origen_X y Origen_Y.
10. Comprueba que B(1380; 0), C(1380; −500), Dv(660; −1420) y E(0; −1420) coinciden con los vértices de tus bocetos (errores ≤ 1 mm).
11. Compara el hueco P1–P4 de CHM-HOGAR con tu vaciado y con las líneas simbólicas (8.1).
12. **Antes de guardar:** selecciona el DXF importado y bórralo (Supr).
    - Si no funciona: Desanclar (Unpin; el nombre en tu idioma puede variar) y vuelve a borrarlo.
13. Gestionar → **Eliminar sin usar** (Purge Unused; el nombre en tu idioma puede variar) para limpiar capas y estilos de línea importados.
14. Insertar → Administrar vínculos (Manage Links) → pestaña Formatos CAD: debe quedar vacía.

**Comprobación:** los vértices coinciden con los bocetos, no queda ningún CAD importado en la familia y Formatos CAD está vacía. Si se ve a escala ×10 o ×1000, las unidades de importación no eran mm.

## 12. Problemas típicos y soluciones
| # | Síntoma | Causa probable | Solución |
|---|---|---|---|
| 1 | «Las restricciones no se cumplen» / error al cambiar un valor | Valor 0, o fuera de rango (CX ≥ W, CY ≥ D, OW demasiado grande, ZH/OD/MD/VG/H a 0, o incumples la coherencia de 2.1) | Deshaz; usa ≥ 1 mm; respeta CX < W, CY < D, OW + 2·MF ≤ Long_Chaflan − 100, 2·MF < OW y OH, VG ≤ MD, MD < OD, OZ + OH < H, ZH < OZ |
| 2 | Al cambiar CX o CY el chaflán no se mueve | Extremos de la diagonal sin alinear | Repite los pasos 14–17 del apartado 4. **Plan B** (si no deja alinear extremos): edita el boceto → Cota alineada entre RP_Ancho y el extremo Dv, etiqueta Chaflan_X; y entre RP_Fondo y el extremo C, etiqueta Chaflan_Y. No sé si tu versión acota a extremos de boceto |
| 3 | El vaciado del hogar no se ve (o se ve fuera del cuerpo) | Signo de la profundidad | Cambia la fórmula de Aux_Prof_Hogar a `Hogar_Fondo` (o viceversa) |
| 4 | Marco y/o vidrio desaparecen | El vaciado los corta | 6.6: Anular corte de geometría con cada uno; si siguen sin verse, comprueba que Ver_Vidrio está marcado y el nivel de detalle |
| 5 | Al elegir la cara, «Ir a vista» no ofrece la vista que esperas | Depende de la versión y de las vistas existentes | Elige `Vista 3D: {3D}`; o cancela, abre la sección `Cara_chaflan` y repite 6.2 desde ahí |
| 6 | No deja acotar a las aristas de la cara; no se puede hacer EQ; en 3D la herramienta Cota está desactivada | Revit no admite esa referencia en tu versión o la vista 3D no está bloqueada | Tab para alternar arista/cara; si no, centra el hueco con dos cotas fijas de margen (159,12) desde las aristas o a ojo y asume que no seguirá a CX/CY; o bloquea la vista 3D (clic derecho en el ViewCube → «Guardar orientación y bloquear vista») para acotar |
| 7 | «Las líneas del boceto se solapan» / «bucle abierto» | Una línea elegida dos veces o sin recortar | Muestra el error, borra la línea sobrante o repite Recortar/Extender a esquina en la esquina marcada |
| 8 | En el proyecto todo sale gris | Material «Por categoría» o parámetro sin asociar | Selecciona cada forma → Material debe mostrar el botoncito asociado (7.2); asigna los valores de Mat_* (2.3) |
| 9 | Alinear rechaza el muro izquierdo | La familia es ortogonal y el muro está a 2,39° | Ver 10.4: coloca con el ajuste de punto en la esquina y solo bloquea Origen_Y |
| 10 | Se ve el anclaje en planta | Visibilidad sin desmarcar en alguna de las cuatro casillas | 8.2: desmarca también «Cuando se corta en Plano/RCP» (probablemente la decisiva con el corte a 1200; no probado). Si la casilla está en gris, desmarca la subcategoría Anclaje en Visibilidad/Gráficos de la vista |
| 11 | Las líneas simbólicas no acompañan al cambiar un tipo | Son de la familia, no del tipo | Es lo esperado (8.1, limitación); método alternativo, no probado: un rectángulo por tipo con parámetro Sí/No (8.1) |
| 12 | El chaflán del zócalo no se retranquea 25 al cambiar ZR | Su desfase es un valor fijo | Edita esa línea (5.1, paso 5) o, mejor (no probado), dibújala con Línea, acótala 25 a la cara del cuerpo y etiqueta la cota con Zocalo_Retranqueo |
| 13 | Revit dice «fórmula incorrecta» o «unidades inconsistentes» | Ortografía/mayúsculas del parámetro, separador decimal o, en Long_Chaflan, unidades de `^ 2` y `sqrt` | Copia el nombre exacto de la tabla 2.1; en las fórmulas usa operadores con espacios; en Long_Chaflan usa la versión sin unidades (plan B de 2.1); en Aux_Vidrio_* usa la variante sin signo menos delante de paréntesis |
| 14 | Cambiar Altura en una instancia cambia todas | Se creó como parámetro de tipo | Tipos de familia → seleccionar Altura → Modificar parámetro → **Instancia** |
| 15 | No deja renombrar o editar los planos centrales de la plantilla | Están anclados (pin) | Selecciónalos → Desanclar (Unpin; el nombre en tu idioma puede variar) y renombra; no los muevas |
| 16 | Elegir líneas no resalta el borde del cuerpo, del hueco o del marco | Revit no ofrece esa arista como referencia de boceto | Dibuja con Línea o Rectángulo y alinea cada lado con candado a la arista; o acota (cota alineada) y etiqueta. Para las líneas simbólicas, importa la planta con el atajo del apartado 11 y encaja sobre sus vértices |
| 17 | En la sección `Cara_chaflan` no se ve la cara | Recorte lejano insuficiente o sección mirando al lado contrario | Propiedades de la sección: «Desfase de recorte lejano» (Far Clip Offset) = 2000; si sigue vacía, voltea la sección (Flip) |
| 18 | El diálogo «Nuevo parámetro» no tiene Disciplina y Tipo por separado | Versión antigua de Revit | Hay un solo desplegable «Tipo de parámetro»: elige Longitud, Sí/No o Material |
| 19 | El DXF se ve a otra escala, queda anclado o no se puede borrar | Unidades de importación distintas de mm; el CAD importado se ancla | Reimporta con Milímetros (11, paso 5); Desanclar (Unpin) antes de borrarlo |
| 20 | El interior del hogar pierde el pintado al cambiar parámetros | Pintar no es paramétrico y Revit regenera las caras del hueco | Repinta (6.7) y avisa de que Mat_Hogar no es paramétrico (no lo he podido comprobar) |
| 21 | En el proyecto no veo el rectángulo discontinuo del hogar | La vista está en nivel Basto (8.3), el tipo no es el por defecto o el plano de corte no es el de 8.1 | Pasa la vista a Medio o Fino, o marca Basto en las líneas simbólicas |
| 22 | En planta la chimenea no se ve cortada (solo líneas de proyección, sin relleno de corte) | Equipamiento especializado solo se corta con «Habilitar corte en vistas» marcado (Revit 2023 o posterior); en 2022 o anterior no se corta nunca | Crear → Categoría y parámetros de familia → marca la casilla (apartado 1, paso 6); en 2022 o anterior cambia la categoría a Modelos genéricos |

**Comprobación:** tras aplicar la solución, repite el paso que falló y la línea Comprobación de su apartado.

---

*Documento escrito sin ejecutar Revit ni AutoCAD. Cualquier nombre de menú puede variar con tu versión e idioma; ante la duda, busca la intención descrita.*
