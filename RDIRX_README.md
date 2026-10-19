# RDIRX — Reconstruir directrices explotadas

`RDIRX.lsp` convierte directrices que se han quedado **explotadas** en piezas
sueltas en **directrices múltiples (MLEADER)** reales de AutoCAD. Las piezas
sueltas son un texto, una o varias líneas o polilíneas y la flecha (un SOLID o
un bloque).

Cada directriz nueva conserva:

- el **mismo texto** (contenido y formato),
- la **misma altura de texto**,
- la **misma capa** que el texto original,
- la **forma original**: todos los tramos y codos, con la punta de flecha en
  el mismo sitio.

Las piezas sueltas originales se borran al terminar.

---

## Cuándo usarlo

- Planos recibidos de otra empresa o exportados desde otro programa en los que
  las directrices llegan "rotas" en líneas, textos y sólidos.
- Directrices antiguas (`LEADER`) o múltiples que alguien hizo `EXPLODE` por
  error.
- Cuando necesitas que las directrices vuelvan a ser un único objeto: que se
  muevan y se editen juntas y obedezcan al estilo de directriz múltiple.

---

## Instalación

### Cargarlo una vez
1. Escribe `APPLOAD`.
2. Busca `RDIRX.lsp`, selecciónalo y pulsa **Cargar**.
3. Cierra la ventana. En la línea de comandos aparecerá:
   `[RDIRX] Cargado. Escribe RDIRX para reconstruir directrices explotadas.`

### Cargarlo siempre al abrir AutoCAD
1. `APPLOAD` → botón **Contenido…** del **Maletín de inicio** (*Startup
   Suite*).
2. **Añadir…** → selecciona `RDIRX.lsp` → **Cerrar**.

---

## Uso paso a paso

1. **Prepara el estilo** *(opcional)*: activa el estilo de directriz múltiple
   que quieras usar (`MLEADERSTYLE` → seleccionar → **Definir actual**). Las
   directrices nuevas usarán ese estilo: tipo de flecha, tamaño de flecha,
   fuente, etc.
2. Escribe `RDIRX`.
3. **Elige la orientación del texto** (ver más abajo): Intro para `Scp`
   (texto horizontal en el SCP actual) o `O` para `Original`. Se recuerda la
   última elección.
4. **Selecciona** todas las piezas de las directrices que quieras reconstruir:
   los textos, las líneas o polilíneas y las flechas. Puedes coger muchas
   directrices de una vez con una **ventana de selección**: el programa sabe
   qué texto va con qué línea.
5. Pulsa **Intro**.
6. En la línea de comandos verás el resultado, por ejemplo:
   `[RDIRX] 12 directriz(es) reconstruida(s); 1 texto(s) sin linea cercana, sin tocar.`

Si el resultado no te convence, escribe **`U`** una sola vez: se deshace todo
el lote.

---

## Qué objetos admite

| Pieza | Tipos de objeto |
|---|---|
| Texto | `TEXT`, `MTEXT` |
| Línea de la directriz | `LINE`, `LWPOLYLINE`, `POLYLINE`, `LEADER` |
| Flecha | `SOLID` (flecha rellena), `INSERT` (bloque de flecha) |

Los objetos en **capas bloqueadas** se ignoran: ni se usan ni se borran.

---

## Cómo decide qué va con qué

1. **Texto ↔ primer tramo.** Para cada texto busca el tramo con un
   **extremo** a menos de **4 alturas de texto** del rectángulo **real** del
   texto, girado con él. No usa la caja alineada con el SCU, que en un texto
   girado es enorme y tocaría líneas ajenas. Empareja primero las parejas más
   cercanas de todo el lote, sin repetir texto ni tramo.
2. **Seguir la directriz.** Desde ese tramo sigue los tramos que empiezan
   donde termina el anterior, **solo por líneas de la misma capa y el mismo
   color** que el primer tramo. Se detiene:
   - al llegar a la **flecha**,
   - donde el camino se **bifurca** (dos o más tramos posibles),
   - o donde ya no hay continuación.

   Así no se "come" contornos ni otras líneas del dibujo que toquen la
   directriz.
3. **Apoyo y punta.** El extremo pegado al texto es el apoyo; el otro, la
   punta. Si el primer tramo tiene los dos extremos junto al texto (un
   subrayado), prueba los dos sentidos y se queda con el que llega a una
   flecha.
4. **Flecha.** Es un `SOLID` o un `INSERT` **pegado** a la punta (a menos de
   0,25 alturas de texto de su contorno). Un `INSERT` solo cuenta como flecha
   si es **pequeño** (menos de 4 alturas de texto), para no borrar un bloque
   normal que se haya colado en la selección. Si la línea acababa en la base
   de un `SOLID`, la punta nueva se coloca en el vértice real de la flecha.

## Orientación del texto

Al empezar, `RDIRX` pregunta `Orientacion del texto [Scp/Original] <Scp>:`.

- **Scp** *(por defecto)*: el texto queda **horizontal en el SCP actual**,
  como si dibujaras la directriz a mano con `MLEADER`. Si trabajas en un SCP
  girado, el texto sale recto en pantalla.
- **Original**: conserva el **ángulo y el plano del texto original**, aunque
  estuviera girado.

## Texto apoyado sobre una línea (subrayado)

Si el tramo junto al texto es una línea **horizontal** (el típico texto
escrito encima de una raya, con la diagonal saliendo de un extremo), ese tramo
se convierte en el **rellano** de la directriz múltiple y el texto queda
**subrayado**, como en el original. Así la directriz se comporta como una
nativa: si mueves el texto, el subrayado lo acompaña.

## Altura del texto y estilos anotativos

La directriz nueva lleva la **altura real** del texto original. Si el estilo de
directriz múltiple actual es **anotativo**, la directriz se deja **no
anotativa**: si no, AutoCAD multiplicaría la altura por la escala de anotación
y el texto saldría gigante.

---

## Limitaciones y consejos

- **Posición del texto.** La directriz múltiple coloca el texto junto a su
  apoyo según su estilo (separación, enganche), así que puede quedar
  ligeramente desplazado respecto al original.
- **Sin subrayado no hay rellano.** Si el último tramo no es horizontal
  respecto al texto, la directriz se crea sin rellano, apoyando el texto en el
  último punto. Si lo quieres, en Propiedades pon **Rellano horizontal: Sí**.
- **Texto lejos de la línea.** Si un texto queda a más de 4 alturas de texto
  de su línea, no se empareja y se queda sin tocar. Acerca el texto o pide que
  se amplíe esa distancia.
- **Formato manual del texto.** Si el texto original tenía alturas o fuentes
  puestas a mano dentro del MTEXT, la directriz nueva las hereda. Para
  quitarlas, usa `StripMtext` (`SMT`) sobre las directrices nuevas,
  marcando *Height* y *Font*.
- **Directrices de varias capas.** Si los tramos de una misma directriz
  original están en capas o colores distintos, solo se sigue el primero.
  Unifícalos antes (`MATCHPROP`) y repite.
- **Arcos en polilíneas.** Los tramos curvos de una polilínea se convierten en
  tramos rectos entre sus vértices.
- **Prueba primero.** Haz la primera prueba en una copia del dibujo o sobre
  unas pocas directrices, y comprueba el resultado antes de procesar el plano
  entero.

---

## Solución de problemas

| Mensaje / síntoma | Causa probable | Qué hacer |
|---|---|---|
| `Faltan datos: la seleccion debe incluir textos y lineas.` | En la selección no había textos o no había líneas. | Vuelve a seleccionar incluyendo ambos. |
| `N texto(s) sin linea cercana, sin tocar.` | La línea de esos textos está a más de 4 alturas de texto, o en una capa bloqueada. | Acerca el texto, desbloquea la capa o selecciona también esa línea. |
| La flecha vieja no se ha borrado. | No tocaba la punta de la línea, o es un bloque grande. | Bórrala a mano. |
| La directriz nueva se queda corta (le falta un tramo). | El tramo siguiente está en otra capa o color, o en ese punto el camino se bifurca. | Unifica capa y color de los tramos con `MATCHPROP` y repite. |
| El texto sale girado. | Elegiste `Original` y el texto original estaba girado. | Repite con `Scp`. |
| `No se pudo crear una directriz: …` | El estilo de directriz múltiple actual da problemas. | Pon como actual el estilo `Standard` y repite. |
| Las flechas nuevas salen muy grandes o muy pequeñas. | Es el tamaño de flecha del estilo de directriz múltiple actual. | Ajusta el estilo en `MLEADERSTYLE`. |
