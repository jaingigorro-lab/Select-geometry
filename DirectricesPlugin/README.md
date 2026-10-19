# DirectricesPlugin — comando `RDIR` (plugin .NET para AutoCAD)

Reconstruye directrices **explotadas** (un texto, sus líneas o polilíneas y la
flecha, sueltos) como **directrices múltiples (MLEADER)** reales.

Es la versión en C# de `RDIRX.lsp`, pensada para que el resultado sea
**exacto**:

- **No adivina nada.** Reconstruyes **una directriz cada vez**, seleccionando
  sus piezas, y usa **exactamente las líneas que seleccionas**: ni una más ni
  una menos.
- **El texto conserva el original:** mismo contenido, altura, estilo de texto,
  capa, color y ángulo. Y queda **siempre legible**: nunca boca abajo.
- **La flecha queda igual que la original:** misma punta y mismo tamaño y, si
  era un bloque (punto, trazo de arquitectura...), el mismo símbolo.
- **La orientación no depende del SCU ni del estilo.** La directriz se
  construye directamente en su sitio, en el plano del SCP actual y con su eje
  X a lo largo del texto. Así el rellano y el subrayado siguen al texto y no a
  la horizontal del SCU.

---

## 1. Compilar en Visual Studio

Requisitos: **Visual Studio 2022** (con el componente *Desarrollo de
escritorio de .NET*) y conexión a Internet la primera vez, para descargar el
paquete NuGet oficial de Autodesk `AutoCAD.NET` 24.3.0 (AutoCAD 2024).

1. Abre `DirectricesPlugin.csproj` con Visual Studio (*Archivo › Abrir ›
   Proyecto o solución*).
2. Arriba, elige la configuración **Release** y la plataforma **x64**.
3. *Compilar › Compilar solución* (`Ctrl+Mayús+B`).
4. La DLL queda en `bin\x64\Release\DirectricesPlugin.dll`.

El código está comprobado compilando con el compilador de Visual Studio
(Roslyn) contra los ensamblados de referencia oficiales de **AutoCAD 2024** y
**.NET Framework 4.8**, sin errores ni avisos. Para AutoCAD 2025 o posterior
(que usan .NET 8) habría que cambiar el proyecto a `net8.0-windows` y
`AutoCAD.NET` 25.x.

## 2. Cargarlo en AutoCAD

1. En AutoCAD escribe `NETLOAD`.
2. Elige `DirectricesPlugin.dll`.
3. Ya tienes el comando **`RDIR`**.

**Para que se cargue siempre al abrir AutoCAD:** crea un archivo
`CargarDirectrices.lsp` con esta línea (ajusta la ruta) y añádelo al **Maletín
de inicio** de `APPLOAD`:

```lisp
(command "_.NETLOAD" "C:/Ruta/A/DirectricesPlugin.dll")
```

**Importante:** AutoCAD no puede descargar una DLL ya cargada. Si recompilas,
**cierra y vuelve a abrir AutoCAD** antes de hacer `NETLOAD` otra vez, o
seguirás usando la versión anterior.

---

## 3. Uso

1. Escribe `RDIR`.
2. **Orientación del texto** `[Original/Scp] <Original>`:
   - **Original** *(por defecto)*: el texto conserva el ángulo con el que **se
     ve** el texto original en el SCP actual.
   - **Scp**: el texto queda horizontal en el SCP actual.

   En los dos casos el texto queda **legible**: si con ese ángulo se leería
   boca abajo (de arriba abajo o de derecha a izquierda), se gira 180°. Es la
   regla de siempre en los planos: el texto se lee desde abajo o desde la
   derecha. Así da igual cómo estuviera guardado el texto original: girado
   180°, reflejado por una simetría o con la normal invertida.

   Se recuerda la última elección durante la sesión.
3. **Selecciona las piezas de UNA directriz:** su texto, sus líneas o
   polilíneas y su flecha. Puedes usar una ventana y quitar con `Mayús` lo que
   sobre. Pulsa **Intro**.
4. La directriz se reconstruye y el comando **vuelve a pedir la siguiente**.
5. Cuando termines, pulsa **Intro** sin seleccionar nada.

`U` (deshacer) después del comando deshace todas las directrices de esa
ejecución.

### Qué tienes que seleccionar

| Pieza | Obligatoria | Tipos |
|---|---|---|
| Texto | Sí, **solo uno** | `TEXT`, `MTEXT` |
| Líneas | Sí, al menos una | `LINE`, `LWPOLYLINE`, `POLYLINE`, `LEADER` |
| Flechas | No | `SOLID` (flecha rellena) o bloques de flecha, una por rama |

Si no seleccionas la flecha de una rama, esa rama usa la flecha del estilo de
directriz múltiple actual, y la flecha vieja se queda en el dibujo.

Los objetos en capas bloqueadas no se pueden seleccionar.

---

## 4. Qué hace exactamente

1. **Usa todas las líneas seleccionadas, tal cual.** Las une por los
   extremos que coinciden. Los vértices alineados en la misma dirección se
   quedan en uno.
2. **Apoyo, codo y ramas:** el extremo libre más cercano al texto es el
   apoyo. Desde ahí sigue la línea hasta el **codo**, el punto donde se separa
   en varias ramas, o hasta la punta si no se separa.
   - Si hay **varias flechas saliendo del mismo codo**, cada rama es una línea
     de la **misma** directriz múltiple, todas unidas en el codo, como en una
     directriz nativa con varias flechas.
   - Si las líneas seleccionadas no se tocan entre sí, se avisa y se unen por
     sus extremos más cercanos, sin descartar ninguna.
3. **Flechas:** cada flecha seleccionada va a la rama cuya punta tiene más
   cerca.
   - Si es un `SOLID`: la punta va a su vértice, el tamaño es su longitud y el
     tipo es flecha cerrada rellena.
   - Si es un bloque: la punta va a su punto de inserción, el tamaño es su
     escala y el símbolo es ese mismo bloque.
4. **Rellano:** si el tramo junto al texto es paralelo al texto, se convierte
   en el rellano de la directriz múltiple:
   - Si la raya iba **a lo largo del texto** (texto escrito sobre la raya), el
     texto queda **subrayado y encima de la raya**, en su lado legible, a
     continuación del codo.
   - Si la raya **acababa junto al texto**, queda un rellano normal, con el
     texto a continuación y centrado en su altura.

   - Si la línea **sigue recta por debajo del texto** (raya y línea a la
     flecha en prolongación), el codo se pone en el borde del texto: lo que
     queda bajo el texto es el subrayado.
   - Si el texto estaba **subrayado por formato** (`%%u` en un TEXT o `\L` en
     un MTEXT), ese subrayado se quita del texto y lo dibuja la propia
     directriz, para que no salga **doble**.
   - Si el original **no** estaba subrayado, la directriz nueva tampoco, diga
     lo que diga el estilo de directriz múltiple actual.

   El texto se coloca como lo haría AutoCAD en una directriz nativa, y se
   desplaza hasta que el final de las líneas cae **exactamente en el codo
   original**. Si no hay rellano, el texto queda junto al apoyo, donde estaba.
5. **Texto:** misma altura real. La directriz se deja **no anotativa** y con
   escala general 1, para que AutoCAD no multiplique la altura por ninguna
   escala.
6. **Borra** el texto, las líneas y la flecha originales.

Si AutoCAD rechaza un ajuste secundario (el plano, la flecha, el rellano...),
la directriz se crea igualmente y el comando lo indica con un mensaje
`RDIR: aviso, no se pudo ...`. Si falla un paso imprescindible, no se cambia
nada de esa directriz: el mensaje dice en qué paso falló (por ejemplo
`al anadir las lineas de directriz: eInvalidContext`) y el comando sigue con la
siguiente. Si te pasa, mándame ese mensaje.

---

## 5. Diagnóstico: comando `RDIRINFO`

Si una directriz sale rara (por ejemplo, con el subrayado doble), escribe
`RDIRINFO` y toca cada línea sospechosa. Para cada objeto dice:

- si es **parte de una directriz múltiple** o un **objeto suelto** (una raya
  original que no entró en la selección, por ejemplo);
- si es una directriz múltiple: su estilo, escala, rellano, quiebro,
  enganche del texto, número de líneas y el contenido del texto (con sus
  códigos de formato).

Copia lo que aparece en la línea de comandos y mándalo junto con la captura.

---

## 6. Limitaciones

- **Ramas que se vuelven a dividir.** Las ramas se separan en un único codo,
  como en una directriz nativa. Si una rama se divide otra vez más adelante,
  cada camino hasta una punta se dibuja como una línea entera.
- **Arcos en polilíneas:** los tramos curvos pasan a ser rectos entre sus
  vértices.
- **Posición fina del texto:** según el estilo (separación del rellano),
  AutoCAD puede ajustar ligeramente el último tramo para enganchar la línea al
  texto.
- **Lo que no seleccionas se queda.** Si después de `RDIR` ves una línea
  suelta junto a la directriz nueva, es que no estaba en la selección: bórrala
  o repite incluyéndola.
- **Formato manual del texto:** se conserva tal cual estaba en el original.
  Si quieres limpiarlo, usa `StripMtext` (`SMT`) sobre las directrices nuevas.
