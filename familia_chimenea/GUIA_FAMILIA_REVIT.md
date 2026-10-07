# Guía: construir en Revit la familia «Chimenea_Esquina_Minimalista»

## 0. Qué vas a obtener

- Una familia `.rfa` de **chimenea de esquina minimalista**: volumen liso en pentágono (muro de fondo 1380, muro izquierdo 1420, chaflán de 720 × 920), zócalo retranqueado (junta de sombra), hueco de hogar rectangular centrado en el chaflán, marco de acero negro y vidrio.
- Es **paramétrica**: ancho, fondo, chaflán, hueco, marco, zócalo y altura se cambian desde las propiedades; la altura es de instancia.
- Se modela **ortogonal**; el desvío de 2,39° del muro izquierdo lo absorbe un solape oculto (anclaje) dentro de los muros.
- Tiempo estimado: **2–3 horas** la primera vez (estimación mía, no medida).
- **Aviso honesto:** esta guía está escrita **sin poder ejecutar Revit**; nadie la ha probado en Revit. Los nombres de comandos son los habituales en español; donde dudo, lo digo. Lo que puede cambiar entre Revit 2022 y 2025 lleva **(según versión)**. Si un paso falla, ve al apartado 12.

Convenciones: unidades en mm; el inglés entre paréntesis solo la primera vez; X a la derecha, **Y hacia el muro de fondo (arriba en planta)**; el cuerpo ocupa X ≥ 0, Y ≤ 0; origen O = esquina interior (cara interior del muro de fondo ∩ cara interior del muro izquierdo). Puntos clave: B(1380; 0), C(1380; −500), Dv(660; −1420), E(0; −1420). Decimales con la coma de tu configuración regional.

## 1. Nueva familia

1. Archivo (File) → Nuevo (New) → Familia (Family) → plantilla **`Modelo genérico métrico.rft`** (Metric Generic Model.rft) → Abrir.
2. Guarda ya: Archivo → Guardar como → Familia → `Chimenea_Esquina_Minimalista.rfa`. Guarda tras cada apartado.
3. Crear (Create) → panel Propiedades → **Categoría y parámetros de familia** (Family Category and Parameters): categoría **Equipamiento especializado** (Specialty Equipment); marca **Siempre vertical** (Always vertical); **desmarca Delimitación de habitaciones** (Room Bounding); deja desmarcado «Basado en plano de trabajo» (Work plane-based). Aceptar.
4. Gestionar (Manage) → Unidades de proyecto (Project Units) → Longitud: **Milímetros**, redondeo a **2 decimales** (para ver 1168,25; luego puedes poner 0), sin símbolo.
5. Abre la planta del Navegador de proyectos (Project Browser): Planos de planta → **`Ref. Level`** (el nombre varía con el idioma). Barra de control de vista → estilo visual **Sombreado** (Shaded). Todo el trabajo en planta se hace aquí.

## 2. Parámetros

### 2.1 Tabla completa

Grupo «Cotas» = Dimensions; «Gráficos» = Graphics; «Materiales y acabados» = Materials and Finishes. Los nombres son **sin acentos ni espacios y distinguen mayúsculas** (las fórmulas los usan tal cual).

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
| Mat_Cuerpo | Materiales y acabados | Material | Tipo | (apartado 7) | — |
| Mat_Marco | Materiales y acabados | Material | Tipo | (apartado 7) | — |
| Mat_Vidrio | Materiales y acabados | Material | Tipo | (apartado 7) | — |
| Mat_Hogar | Materiales y acabados | Material | Tipo | (apartado 7; ver nota) | — |
| Long_Chaflan | Cotas | Longitud | Tipo | 1168,25 (calculado) | `sqrt(Chaflan_X ^ 2 + Chaflan_Y ^ 2)` |
| Margen_Hogar | Cotas | Longitud | Tipo | 159,12 (calculado) | `(Long_Chaflan - Hogar_Ancho) / 2` |

**Parámetros auxiliares** (los añado yo; **no están en la especificación**). Hacen falta porque Revit extruye desde una cara en el sentido de su normal (hacia fuera) y la profundidad hacia dentro es un valor **negativo**; para no teclear −450 a mano (y perder el parámetro) se asocia a la extrusión un parámetro calculado negativo. Tipo, grupo «Cotas», Longitud:

| Nombre | Valor (calculado) | Fórmula |
|---|---|---|
| Aux_Prof_Hogar | −450 | `-Hogar_Fondo` |
| Aux_Prof_Marco | −40 | `-Marco_Prof` |
| Aux_Vidrio_Ini | −15 | `-(Marco_Prof - Vidrio_Esp) / 2` |
| Aux_Vidrio_Fin | −25 | `-(Marco_Prof + Vidrio_Esp) / 2` |

Condición de diseño: `Hogar_Ancho + 2 · Marco_Ancho ≤ Long_Chaflan − 100` (con los valores por defecto el máximo de Hogar_Ancho es ≈ 1028 mm).

Nota sobre **Mat_Hogar**: el interior del hogar se **pinta** (apartado 6.7) y, que yo sepa, la herramienta Pintar aplica un material fijo, no un parámetro. Crea Mat_Hogar igualmente por coherencia con la especificación; solo tendrá efecto si luego forras el hogar con un sólido (última nota del apartado 7.3). No lo he podido comprobar.

### 2.2 Cómo crearlos

1. Crear → panel Propiedades → **Tipos de familia** (Family Types).
2. Botón **Nuevo tipo** (New Type) → nombre `1380x1420` → Aceptar. Todos los valores de abajo se escriben dentro de este tipo.
3. Botón **Nuevo parámetro** (New Parameter) (icono inferior): *Parámetro de familia* (no compartido); Nombre; Disciplina «Común» y Tipo «Longitud» (en versiones antiguas, un solo desplegable «Tipo de parámetro»; según versión); **Agrupar parámetros en** = Cotas; radio **Tipo** o **Instancia** según la tabla → Aceptar. Repite con los 22 + 4.
4. Para el **Sí/No**: Tipo de parámetro «Sí/No», grupo Gráficos, Instancia; después marca la casilla de su fila.
5. Para los **de material**: Tipo de parámetro «Material», grupo «Materiales y acabados», Tipo. Déjalos en «Por categoría» hasta el apartado 7.
6. Para los **calculados**: crea el parámetro y escribe la expresión en la columna **Fórmula** (Formula) (la celda de Valor se pone gris). Si Revit da «fórmula incorrecta», revisa mayúsculas y que los nombres existan.
7. Escribe los valores en la columna Valor y pulsa **Aplicar**. Puedes subir/bajar parámetros con las flechas del diálogo.
8. Si prefieres crearlos sobre la marcha: al etiquetar una cota (apartado 3), Etiqueta → «‹Añadir parámetro…›».

**Aviso:** una cota con valor **0 no se admite** (Revit da error de restricciones). Ningún parámetro que etiquete una cota (W, D, CX, CY, S, ZR, MF, OW, OH, OZ…) puede valer 0 ni salirse de su rango (CX < W, CY < D). En las pruebas usa siempre ≥ 1 mm.

## 3. Planos de referencia y cotas

### 3.1 Receta para cada plano (repítela 8 veces)

1. En `Ref. Level`: Crear → panel Referencia → **Plano de referencia** (Reference Plane); dibuja la línea ya del lado correcto del origen, a ojo (verticales de abajo arriba, horizontales de izquierda a derecha).
2. Selecciónalo → Propiedades → **Nombre** (Name) = el de la tabla.
3. Anotar (Annotate) → **Cota alineada** (Aligned): clic en el plano de partida, clic en el nuevo, clic en vacío para colocar.
4. Clic en el valor de la cota y teclea el valor (el plano se mueve). Con la cota seleccionada, barra de opciones → **Etiqueta** (Label) → el parámetro. Comprueba en Tipos de familia que el parámetro conserva su valor (si Revit lo cambió, reescríbelo y Aplicar).

### 3.2 Tabla de planos

| # | Nombre | Orientación | Posición | Cota que lo define → parámetro | Es referencia |
|---|---|---|---|---|---|
| 1 | Origen_X | Vertical | X = 0 | plano de plantilla «Centro (izquierda/derecha)» renombrado | **Fuerte** (Strong Reference) |
| 2 | Origen_Y | Horizontal | Y = 0 | plano de plantilla «Centro (delante/detrás)» renombrado | **Fuerte** |
| 3 | RP_Ancho | Vertical | X = 1380 | Origen_X → RP_Ancho = Ancho_Muro_Fondo | No es una referencia |
| 4 | RP_Fondo | Horizontal | Y = −1420 | Origen_Y → RP_Fondo (hacia abajo) = Fondo_Muro_Izq | No es una referencia |
| 5 | RP_Chaflan_X | Vertical | X = 660 | RP_Chaflan_X → RP_Ancho = Chaflan_X | No es una referencia |
| 6 | RP_Chaflan_Y | Horizontal | Y = −500 | RP_Fondo → RP_Chaflan_Y (hacia arriba) = Chaflan_Y (920) | No es una referencia |
| 7 | RP_Anclaje_X | Vertical | X = −100 | Origen_X → RP_Anclaje_X (a la izquierda) = Solape_Muros | No es una referencia |
| 8 | RP_Anclaje_Y | Horizontal | Y = +100 | Origen_Y → RP_Anclaje_Y (arriba) = Solape_Muros | No es una referencia |
| 9 | RP_ZR_Der | Vertical | X = 1355 | RP_ZR_Der → RP_Ancho = Zocalo_Retranqueo | No es una referencia |
| 10 | RP_ZR_Frente | Horizontal | Y = −1395 | RP_ZR_Frente → RP_Fondo = Zocalo_Retranqueo | No es una referencia |

Planos 1 y 2: la plantilla ya trae dos planos centrales cruzados en el origen. **No dibujes otros**: selecciónalos, cambia Nombre y **Es referencia → Fuerte**. Si Revit no deja editarlos, quita el pin (Desanclar / Unpin) y vuelve a intentarlo (según versión). Tampoco los muevas. Estos dos planos son los que alinearás con los muros en el proyecto (apartado 10).

Orden: 1–2, 3–4, 5–6, 7–8, 9–10. El plano 10 queda entre Origen_Y y RP_Fondo (25 mm sobre RP_Fondo); haz zoom para colocar las cotas.

**Chaflán:** no hacen falta líneas de referencia (Reference Line). Los dos extremos salen de intersecciones de planos: **Dv = RP_Chaflan_X ∩ RP_Fondo = (660; −1420)** y **C = RP_Ancho ∩ RP_Chaflan_Y = (1380; −500)**. Por eso los planos 5 y 6 existen: llevan CX y CY. El chaflán será una línea de boceto entre esos dos puntos (apartado 4).

Con CX=720 y CY=920 deben cumplirse: Long_Chaflan = 1168,25 y Margen_Hogar = 159,12 (compruébalo en Tipos de familia).

## 4. Cuerpo (pentágono)

1. En `Ref. Level`: Crear → panel Formas (Forms) → **Extrusión** (Extrusion). Se abre la pestaña «Modificar | Crear perfil de extrusión».
2. Panel Dibujar → **Elegir líneas** (Pick Lines). Barra de opciones: Desfase (Offset) `0`; **marca Bloquear** (Lock); desmarca «Seleccionar cadena».
3. Clic sobre Origen_Y, Origen_X, RP_Ancho y RP_Fondo. Salen 4 líneas con candado (lock) sobre los planos.
4. Pestaña Modificar → panel Editar → **Recortar/Extender a esquina** (Trim/Extend to Corner): en cada una de las 4 esquinas, clic en las dos líneas por el lado que quieres conservar. Resultado: rectángulo 1380 × 1420 con vértices O, B, K(1380; −1420), E.
5. Dibujar → **Línea** (Line); desmarca «Cadena» (Chain). Clic 1 en la intersección RP_Fondo ∩ RP_Chaflan_X (el cursor indica «Intersección»); clic 2 en RP_Ancho ∩ RP_Chaflan_Y. Es el chaflán.
6. Recortar/Extender a esquina: diagonal + línea derecha (conserva el tramo B–C, el de arriba); diagonal + línea inferior (conserva el tramo Dv–E, el de la izquierda). Desaparece la esquina K. Quedan **5 líneas formando un lazo cerrado**: O–B–C–Dv–E.
7. **Fijar los extremos del chaflán** (para que siga a CX y CY): Modificar → **Alinear** (Align): clic en el plano RP_Chaflan_X (referencia), luego pasa el cursor por el extremo Dv de la diagonal hasta que se resalte el punto final y haz clic; pulsa el candado que aparece. Repite con RP_Chaflan_Y y el extremo C. *No estoy seguro de que todas las versiones dejen alinear un extremo de línea de boceto; si no deja, usa el plan B del apartado 12 (fila 2).*
8. Paleta Propiedades (Properties):
   - **Extrusión final** (Extrusion End): pulsa el botoncito de la derecha («Asociar parámetro de familia», Associate Family Parameter) → **Altura**. Así la altura queda enlazada al parámetro de **instancia**.
   - **Extrusión inicial** (Extrusion Start): botoncito → **Zocalo_Alto** (el cuerpo arranca sobre el zócalo).
9. **Finalizar modo de edición** (Finish Edit Mode, marca de verificación verde).
10. Comprobación: abre la vista 3D y mira el pentágono. En Tipos de familia pon Chaflan_X = 600 y Aplicar: el chaflán debe moverse; devuélvelo a 720. Si no se mueve, apartado 12.

## 5. Zócalo retranqueado y anclaje

### 5.1 Zócalo (Z 0 → 60, retranqueado 25)

1. Planos 9 y 10 ya creados (apartado 3).
2. Crear → Extrusión → Elegir líneas (**Bloquear** marcado, Desfase `0`): clic en Origen_Y, Origen_X, **RP_ZR_Der** y **RP_ZR_Frente**; Recortar/Extender a esquina en las 4 esquinas → rectángulo.
3. Chaflán del zócalo: Elegir líneas con **Desfase = 25**, **Bloquear** marcado; acerca el cursor al **borde del chaflán del cuerpo** (la línea oblicua que ves en planta) y mueve el cursor hacia la esquina interior (hacia O) hasta que la línea previa quede *dentro*; clic. Recorta la diagonal con la línea derecha y con la frontal. Lazo cerrado de 5 líneas.
   - Este desfase de 25 queda **fijo** (no sé etiquetar con un parámetro el desfase de Elegir líneas). Si algún día cambias Zocalo_Retranqueo, cambia también esa línea. *Si Revit no te deja elegir el borde del cuerpo, dibuja la diagonal con Línea y acótala (cota alineada, valor 25) respecto a la cara del cuerpo.*
4. Propiedades: Extrusión inicial `0`; Extrusión final → botoncito → **Zocalo_Alto**. Finalizar modo de edición.

### 5.2 Anclaje en L (Z 0 → H, oculto en planta)

1. Planos 7 y 8 ya creados.
2. Crear → Extrusión → Elegir líneas (**Bloquear**, Desfase `0`): clic en **RP_Anclaje_Y, RP_Ancho, Origen_Y, Origen_X, RP_Fondo, RP_Anclaje_X** (las 6 líneas).
3. Recortar/Extender a esquina entre cada par contiguo hasta cerrar el polígono en L: (−S, S) → (W, S) → (W, 0) → (0, 0) → (0, −D) → (−S, −D) → vuelta. Es decir: una tira de 100 sobre el muro de fondo y otra de 100 a la izquierda del muro izquierdo; ambas quedan **dentro de los muros**.
4. Propiedades: Extrusión inicial `0`; Extrusión final → **Altura**. Finalizar modo de edición.
5. Su visibilidad en planta se desactiva en el apartado 8.2.

## 6. Hogar (hueco, marco, vidrio, interior)

### 6.1 Preparar una vista para dibujar en la cara del chaflán

Recomendado (para poder acotar con cotas permanentes): una **sección paralela a la cara**.
1. En `Ref. Level`: Vista (View) → Crear (Create) → **Sección** (Section). Clic 1 en Dv y clic 2 en C (ajústalos a «Punto final» del borde del chaflán, para que sea exactamente paralela). El sentido Dv→C hace que la sección mire hacia la esquina; si la flecha apunta al lado contrario, selecciona la sección y pulsa el símbolo de voltear (Flip).
2. Selecciona la línea de sección y **Mover** (Move) unos 300 mm hacia la sala (abajo-derecha en planta), sin girar: una traslación mantiene el paralelismo (no hace falta precisión).
3. Doble clic en la cabeza de la sección para abrirla; renómbrala `Cara_chaflan`. Si no ves la cara, en Propiedades sube «Desfase de recorte lejano» (Far Clip Offset) a 2000. Verás la cara de frente, `Ref. Level` como línea horizontal y las aristas verticales de la cara en Dv (izquierda) y C (derecha).

Alternativa mínima: trabajar en la vista **3D** (apartado 6.2). *En 3D la herramienta Cota puede estar desactivada salvo que bloquees la vista (clic derecho en el ViewCube → «Guardar orientación y bloquear vista»; según versión); por eso prefiero la sección.*

### 6.2 Plano de trabajo sobre la cara

1. Crear → panel Plano de trabajo (Work Plane) → **Establecer** (Set) → «**Elegir un plano**» (Pick a plane) → Aceptar → clic en la cara del chaflán (la cara grande, entre las dos aristas verticales). Si haces esto desde la sección, normalmente no se abre ningún diálogo.
2. Si se abre el diálogo **«Ir a vista»** (Go To View), elige `Sección: Cara_chaflan`; si esa no aparece, elige **`Vista 3D: {3D}`** (el contenido de la lista varía; según versión) y continúa en 3D.
3. Comprueba con Plano de trabajo → **Mostrar** (Show) que el plano coincide con la cara.

### 6.3 Vaciado (hueco) con cotas

1. Crear → Formas → desplegable **Vaciado** (Void Forms) → **Extrusión de vaciado** (Void Extrusion).
2. Dibujar → **Rectángulo** (Rectangle): dos clics dentro de la cara, a ojo ≈ 850 × 600.
3. Plano auxiliar: Crear → Plano de referencia → dibuja una línea vertical hacia el centro del rectángulo; Nombre `RP_Hogar_Centro`.
4. Cotas alineadas (todas con el rectángulo aún en edición):
   - `Ref. Level` (la línea horizontal del nivel) → lado inferior del rectángulo: Etiqueta **Hogar_Cota**. Si no deja seleccionar el nivel, crea en la sección un plano horizontal alineado con candado a `Ref. Level` y acota a ese plano.
   - Lado inferior → lado superior: Etiqueta **Hogar_Alto**.
   - Lado izquierdo → lado derecho: Etiqueta **Hogar_Ancho**.
   - **Centrado del plano en la cara:** una sola cota de 3 referencias: arista izquierda de la cara (en Dv) → RP_Hogar_Centro → arista derecha de la cara (en C); colócala y pulsa el símbolo **EQ** (igualdad) que aparece. (Con la tecla Tab alterna entre «arista» y «cara» hasta que se resalte la arista vertical.)
   - **Centrado del rectángulo en el plano:** otra cota de 3 referencias: lado izquierdo del rectángulo → RP_Hogar_Centro → lado derecho; pulsa **EQ**.
5. Resultado esperado (cotas temporales): márgenes de 159,12 a cada lado y base a Z = 400. *No sé si tu versión deja acotar a las aristas de la cara; si no, ver apartado 12 (fila 6).*
6. Propiedades: Extrusión inicial `0`; **Extrusión final** → botoncito → **Aux_Prof_Hogar** (−450).
   - **Signo:** el plano de trabajo de una cara apunta hacia **fuera** del sólido; un valor negativo entra en el cuerpo. Por eso OD se asocia con signo menos.
   - Comprobación: Finalizar modo de edición y abre `Ref. Level`: el hueco debe verse **dentro** del pentágono (P1–P2 en la cara, P3–P4 450 mm hacia la esquina). Si sale **hacia fuera**, cambia la fórmula de Aux_Prof_Hogar a `Hogar_Fondo` (sin signo).

### 6.4 Marco (anillo a ras de la cara)

1. Comprueba (Plano de trabajo → Mostrar) que el plano activo sigue siendo la cara; si no, repite 6.2.
2. Crear → **Extrusión** (sólida, no vaciado).
3. Bucle exterior: Elegir líneas con **Bloquear** (Desfase `0`) sobre las 4 aristas del hueco. Si Revit no las resalta, dibuja un Rectángulo y alinea con candado cada lado con el del hueco.
4. Bucle interior: Rectángulo cualquiera dentro del anterior. Después **4 cotas alineadas**, cada una entre un lado exterior y su lado interior paralelo, **todas con Etiqueta Marco_Ancho** (20).
5. Propiedades: Extrusión inicial `0`; Extrusión final → **Aux_Prof_Marco** (−40). Finalizar modo de edición.

### 6.5 Vidrio

1. Crear → Extrusión. Elegir líneas con Bloquear sobre los 4 lados del **bucle interior del marco** (rectángulo de 810 × 560). Si no los resalta, alinea con candado.
2. Propiedades: Extrusión inicial → **Aux_Vidrio_Ini** (−15); Extrusión final → **Aux_Vidrio_Fin** (−25) (lámina de 10 centrada en los 40 del marco).
3. Propiedades → **Visible** → botoncito → **Ver_Vidrio**. Finalizar modo de edición.

### 6.6 El vaciado también corta el marco y el vidrio: solución

El marco y el vidrio están enteros dentro del volumen del vaciado, así que Revit puede recortarlos hasta hacerlos desaparecer (depende de la versión y del orden de creación).
1. Modificar → panel Geometría (Geometry) → desplegable **Cortar** (Cut) → **Anular corte de geometría** (Uncut Geometry).
2. Clic en el **vaciado** y luego en el **marco** (si no responde, invierte el orden). Repite con el vaciado y el **vidrio**. Esc para salir.
3. Comprueba en 3D (con Ver_Vidrio marcado) que se ven el marco y el vidrio y que el hueco sigue abierto detrás.

### 6.7 Pintar el interior del hogar

1. En 3D, oculta temporalmente marco y vidrio para ver dentro (selecciónalos → clic derecho → Ocultar en vista → Elementos; luego Restablecer ocultos) o usa un cuadro de sección.
2. Modificar → panel Geometría → **Pintar** (Paint) → en el Explorador de materiales elige el material del hogar (créalo antes, en el apartado 7.1) → clic en las **5 caras interiores**: fondo, izquierda, derecha, techo y suelo del hueco. Terminado (Done).
3. Restablece lo oculto (Restablecer elementos ocultos temporalmente) y comprueba en 3D que el interior se ve negro mate.

## 7. Materiales, parámetros de material y subcategorías

### 7.1 Crear los 4 materiales

Gestionar → **Materiales** (Materials) → botón inferior izquierdo «Crear y duplicar material» → Nuevo material; renómbralo; pestañas Gráficos (Graphics) y Apariencia (Appearance).

| Material (nombre) | Color RGB | Transparencia (Gráficos) | Apariencia orientativa |
|---|---|---|---|
| Chimenea - Microcemento blanco roto | 214, 210, 202 | 0 | Genérico, mate; patrón de corte: relleno sólido gris (o el de tu plantilla) |
| Chimenea - Acero negro | 28, 28, 28 | 0 | Genérico/metal pintado, satinado |
| Chimenea - Vidrio claro | 230, 238, 240 (orientativo) | ≈ 85 | Recurso de apariencia «Vidrio» (Glass), claro |
| Chimenea - Hogar negro mate | 40, 40, 40 | 0 | Genérico, mate |

Pon el mismo color en Sombreado (Gráficos) o marca «Usar apariencia de render para sombreado» (según versión). Los nombres de recursos de apariencia varían; elige el más parecido.

### 7.2 Asignar los materiales a los parámetros

Tipos de familia → en cada parámetro Mat_*, celda de Valor → botón «…» → elige el material: Mat_Cuerpo = Microcemento; Mat_Marco = Acero negro; Mat_Vidrio = Vidrio claro; Mat_Hogar = Hogar negro mate. Aplicar.

### 7.3 Asociar el parámetro a cada forma y asignar subcategoría

Gestionar → Configuración → **Estilos de objeto** (Object Styles) → pestaña Objetos de modelo → categoría Equipamiento especializado → **Modificar subcategorías** → **Nuevo** (New) ×6: `Cuerpo`, `Zocalo`, `Marco`, `Vidrio`, `Hogar`, `Anclaje`. Sugerencia de grosores: Cuerpo proyección 2/corte 3; las demás 1. Aceptar.

Luego selecciona cada forma (clic en 3D o Tab) y en Propiedades usa el botoncito de **Material** (asociar parámetro) y **Subcategoría** (Subcategory):

| Forma | Subcategoría | Material (parámetro) |
|---|---|---|
| Cuerpo | Cuerpo | Mat_Cuerpo |
| Zócalo | Zocalo | Mat_Cuerpo |
| Anclaje | Anclaje | Mat_Cuerpo |
| Marco | Marco | Mat_Marco |
| Vidrio | Vidrio | Mat_Vidrio |
| Interior del hogar | — | pintado con el material del hogar (fijo; la pintura no admite parámetro) |
| Líneas simbólicas (apdo. 8) | Hogar | — |

Opcional si necesitas el material del hogar como parámetro: forra el hueco con 5 láminas finas (p. ej. 2 mm) con Mat_Hogar y aplícales Anular corte; no he detallado este camino.

## 8. Representación en planta y niveles de detalle

### 8.1 Líneas simbólicas del hueco (discontinuas)

1. En `Ref. Level` (plano de corte por defecto a 1200 mm; compruébalo en Rango de vista, View Range): el hogar (Z 400–1000) queda por debajo del corte, por eso se dibuja con líneas simbólicas.
2. Crear → panel Detalle (Detail) → **Línea simbólica** (Symbolic Line). Subcategoría (barra de opciones) = **Hogar**.
3. Dibuja el rectángulo P1–P2–P3–P4 (valores del tipo por defecto, en mm): **P1(758,1; −1294,7), P2(1281,9; −625,3), P3(927,6; −348,0), P4(403,7; −1017,4)**. P1–P2 coincide con la cara; P3–P4 es el fondo. Encájalo con Elegir líneas sobre las aristas del vaciado si Revit las resalta, o con los puntos finales del DXF (apartado 11).
4. En Estilos de objeto → subcategoría Hogar → Patrón de línea: uno **discontinuo** (el nombre, p. ej. «Línea oculta», depende de tu plantilla).
5. **Limitación:** las líneas simbólicas no siguen a los parámetros (salvo que consigas alinearlas con candado a las aristas del vaciado). Si cambias CX, CY, D o OW, revisa o redibuja el rectángulo en cada tipo.

### 8.2 Anclaje invisible en planta

Selecciona el Anclaje → Propiedades → **Visibilidad/Gráficos** (Visibility/Graphics Overrides) → «Editar…» (Family Element Visibility Settings) → **desmarca «Plano/RCP»** (Plan/RCP) (y «Cuando se corta en Plano/RCP»). Déjalo marcado en las demás vistas.

### 8.3 Niveles de detalle (mismo diálogo de visibilidad, por forma)

| Forma | Basto | Medio | Fino | Plano/RCP |
|---|---|---|---|---|
| Cuerpo | Sí | Sí | Sí | Sí (cortado) |
| Zócalo | No | Sí | Sí | Sí |
| Marco | No | Sí | Sí | Sí |
| Vidrio | No | Sí | Sí | Sí |
| Anclaje | Sí | Sí | Sí | **No** |
| Líneas simbólicas del hogar | No | Sí | Sí | (solo existen en planta) |

En Basto el cuerpo queda con su base 60 mm por encima del suelo (es lo especificado; si no te gusta, deja el zócalo también en Basto). Verifica con el control «Nivel de detalle» de la barra inferior de la vista (Basto / Medio / Fino), en planta y en 3D.

## 9. Prueba de flexión

Haz cada prueba en Tipos de familia: cambia el valor, **Aplicar**, mira planta y 3D, y vuelve al valor original. Si Revit protesta, deshaz (Ctrl+Z).

| # | Cambio | Qué debe pasar | Fallos típicos |
|---|---|---|---|
| 1 | W: 1380 → 1500 | Cara derecha, chaflán, zócalo y solape se desplazan 120 a la derecha; Dv pasa a (780; −1420); la longitud del chaflán no cambia (1168,25) | La cara derecha no se mueve: línea sin candado; el zócalo no acompaña: RP_ZR_Der sin cota a RP_Ancho (apartado 3) |
| 2 | D: 1420 → 1600 | Frente y chaflán bajan 180; C = (1380; −680), Dv = (660; −1600); el hueco sigue centrado en el chaflán | El hueco se queda atrás: no está centrado por EQ; el anclaje no se alarga |
| 3 | CX: 720 → 600 | Dv se mueve a (780; −1420); Long_Chaflan = 1098,36 y Margen_Hogar = 124,18; el hueco sigue centrado | **El chaflán no se mueve**: extremos sin alinear (apartado 4, paso 7); hueco descentrado |
| 4 | CY: 920 → 800 | C = (1380; −620); Long_Chaflan = 1076,29; Margen_Hogar = 113,14 | Igual que la prueba 3 |
| 5 | OW: 850 → 700 (también 1000) | Hueco, marco y vidrio se estrechan simétricamente; con 700 el margen es 234,12; con 1000 el margen es 84,12 | Marco o vidrio no siguen (no están bloqueados a las aristas); con OW > 1028 se incumple la condición de diseño (margen < 50 mm) y hacia 1168 el hueco ocupa toda la cara |
| 6 | H: 2600 → 2400 (instancia) | Solo cuerpo y anclaje cambian; zócalo y hueco no; en un proyecto, dos instancias con distinta Altura | Altura aparece como parámetro de tipo (cambia todas): vuelve a crearlo como Instancia |

Pruebas rápidas extra: desmarcar Ver_Vidrio oculta el vidrio; Basto/Medio/Fino se comportan como en 8.3; el anclaje no se ve en planta.

## 10. Guardar, cargar y colocar en el proyecto

1. Con todos los valores por defecto, Guardar como `Chimenea_Esquina_Minimalista.rfa`. Tipo ya creado: `1380x1420` (convención W×D). Otros: Tipos de familia → Nuevo tipo → p. ej. `1500x1500` con W=1500, D=1500 (respeta CX < W, CY < D y la condición del hogar).
2. Abre el proyecto; en la familia: Crear → panel Editor de familias → **Cargar en proyecto** (Load into Project).
3. Proyecto: Arquitectura → Componente (Component) → **Colocar un componente** (Place a Component); elige el tipo `1380x1420`. En planta, lleva el cursor a la esquina interior y ajusta al punto de la esquina (origen = esquina). Clic. Revit coloca la familia libre, a nivel (no alojada).
4. **Alinear a los muros:** Modificar → **Alinear** (Align) → clic en la **cara interior del muro de fondo** → pasa el cursor sobre la chimenea y con Tab elige el plano **Origen_Y** → clic → pulsa el **candado**.
   - Lo mismo con la cara interior del muro izquierdo y el plano **Origen_X**. **Atención:** tu muro izquierdo está inclinado 2,39° y la familia es ortogonal; Alinear exige caras paralelas y probablemente lo rechace. En ese caso, no hay candado en X: deja la familia con el origen exacto en la esquina (con el ajuste de punto) y solo bloquea en Y. Como el muro izquierdo se mete hasta 59 mm hacia la sala en el frente, el cuerpo y el muro se solapan y no queda hueco; el anclaje de 100 cubre además el caso contrario (muro inclinado hacia fuera).
5. Selecciona la instancia → Propiedades → **Altura** = altura libre hasta el techo (cara inferior del techo o falso techo) menos el acabado, por ejemplo 2600; el parámetro de instancia permite valores distintos por chimenea. Ver_Vidrio también se cambia aquí.
6. **Habitación «CHIMENEA» existente:** la familia no delimita habitaciones. Puedes (a) **conservarla** si quieres su área en tablas (la chimenea queda dentro de la habitación y su área incluirá la huella de 1,63 m²; los límites no coinciden exactamente con la familia, con diferencias ≤ 20 mm) o (b) **borrar la habitación y sus líneas de separación** si solo era para dibujar el nicho, y entonces la zona pasa a la habitación contigua.
7. **Otra esquina:** el modelo está dibujado para la esquina arriba-izquierda. Superior derecha: **Reflejar - Seleccionar eje** (Mirror - Pick Axis) con un eje vertical. Inferior izquierda: Reflejar con un eje horizontal. Inferior derecha: **Girar** (Rotate) 180°. Después repite el Alinear con los muros. *Si el chaflán 720 × 920 te resulta asimétrico, esto es lo esperado: se refleja tal cual.*

## 11. Atajo de comprobación con el DXF

Archivo `Chimenea_esquina_plantilla.dxf`, en esta misma carpeta: según la cabecera del generador contiene **planta, alzado y sección** a escala 1:1 en mm; la **planta** debe estar en coordenadas de la familia (origen en la esquina interior, X a la derecha, Y hacia el muro de fondo; cuerpo en X ≥ 0, Y ≤ 0). Alzado y sección son solo de lectura: ignóralos en el Editor de familias. *No he verificado la disposición del DXF final; si la planta no cae sobre el origen, muévela con Mover hasta que su esquina O coincida con el cruce de Origen_X/Origen_Y.*

1. En `Ref. Level` del Editor de familias: Insertar (Insert) → **Importar CAD** (Import CAD).
2. Opciones: **Solo vista actual** (Current view only) marcado; Colores: Conservar; Unidades de importación: **Milímetros**; Posicionamiento: **Origen a origen** (Origin to Origin); desmarca «Corregir líneas ligeramente desviadas». Abrir.
3. Comprueba que la esquina O del DXF coincide con la cruz de Origen_X/Origen_Y y que B(1380; 0), C(1380; −500), Dv(660; −1420), E(0; −1420) y el hueco P1–P4 caen sobre los vértices de tus bocetos (errores ≤ 1 mm). Úsalo también para encajar las líneas simbólicas (8.1).
4. **Antes de guardar:** selecciona el DXF y bórralo (Supr); Gestionar → **Eliminar sin usar** (Purge Unused) para limpiar capas y estilos de línea importados; y Insertar → Administrar vínculos (Manage Links) → pestaña Formatos CAD debe quedar vacía. Si se ve a escala ×10 o ×1000, las unidades de importación no eran mm.

## 12. Problemas típicos y soluciones

| # | Síntoma | Causa probable | Solución |
|---|---|---|---|
| 1 | «Las restricciones no se cumplen» / error al cambiar un valor | Valor 0, o fuera de rango (CX ≥ W, CY ≥ D, OW demasiado grande) | Deshaz; usa ≥ 1 mm; respeta CX < W, CY < D, OW + 2·MF ≤ Long_Chaflan − 100 |
| 2 | Al cambiar CX o CY el chaflán no se mueve | Extremos de la diagonal sin alinear | Repite el paso 7 del apartado 4. **Plan B** (si no deja alinear extremos): edita el boceto → Cota alineada entre RP_Ancho y el extremo Dv, etiqueta Chaflan_X; y entre RP_Fondo y el extremo C, etiqueta Chaflan_Y. No sé si tu versión acota a extremos de boceto |
| 3 | El vaciado del hogar no se ve (o se ve fuera del cuerpo) | Signo de la profundidad | Cambia la fórmula de Aux_Prof_Hogar a `Hogar_Fondo` (o viceversa) |
| 4 | Marco y/o vidrio desaparecen | El vaciado los corta | 6.6: Anular corte de geometría con cada uno; si siguen sin verse, comprueba que Ver_Vidrio está marcado y el nivel de detalle |
| 5 | Al elegir la cara, «Ir a vista» no ofrece la vista que esperas | Depende de la versión y de las vistas existentes | Elige `Vista 3D: {3D}`; o cancela, abre la sección `Cara_chaflan` y repite 6.2 desde ahí |
| 6 | No deja acotar a las aristas de la cara; no se puede hacer EQ | Revit no admite esa referencia en tu versión | Tab para alternar arista/cara; si no, centra el hueco con dos cotas fijas de margen (159,12) desde las aristas o a ojo y asume que no seguirá a CX/CY; o bloquea la vista 3D para acotar |
| 7 | «Las líneas del boceto se solapan» / «bucle abierto» | Una línea elegida dos veces o sin recortar | Muestra el error, borra la línea sobrante o repite Recortar/Extender a esquina en la esquina marcada |
| 8 | En el proyecto todo sale gris | Material «Por categoría» o parámetro sin asociar | Selecciona cada forma → Material debe mostrar el botoncito asociado; asigna los valores de Mat_* (7.2) |
| 9 | Alinear rechaza el muro izquierdo | La familia es ortogonal y el muro está a 2,39° | Ver paso 4 del apartado 10: coloca con el ajuste de punto en la esquina y solo bloquea Origen_Y |
| 10 | Se ve el anclaje en planta | Visibilidad en Plano/RCP sin desmarcar | 8.2 (también «Cuando se corta en Plano/RCP») |
| 11 | Las líneas simbólicas no acompañan al cambiar un tipo | No son paramétricas | Es lo esperado (8.1, paso 5); redibújalas por tipo |
| 12 | El chaflán del zócalo no se retranquea 25 al cambiar ZR | Su desfase es un valor fijo | Edita esa línea (apartado 5.1, paso 3) o rehaz con otro desfase |
| 13 | Revit dice «fórmula incorrecta» o «unidades inconsistentes» | Mayúsculas/ortografía del parámetro o separador decimal | Copia el nombre exacto de la tabla 2.1; en las fórmulas usa operadores con espacios |
| 14 | Cambiar Altura en una instancia cambia todas | Se creó como parámetro de tipo | Tipos de familia → seleccionar Altura → Modificar parámetro → **Instancia** |

---

*Documento escrito sin ejecutar Revit. Cualquier nombre de menú puede variar con tu versión e idioma; ante la duda, busca la intención descrita.*
