# DirectricesPlugin — comando `RDIR` (plugin .NET para AutoCAD)

Reconstruye directrices **explotadas** (un texto, sus líneas o polilíneas y la
flecha, sueltos) como **directrices múltiples (MLEADER)** reales.

Es la versión en C# de `RDIRX.lsp`, pensada para que el resultado sea
**exacto**:

- **No adivina nada.** Reconstruyes **una directriz cada vez**, seleccionando
  sus piezas, y usa **exactamente las líneas que seleccionas**: ni una más ni
  una menos.
- **El texto queda igual que el original:** mismo contenido, altura, estilo de
  texto, capa, color, plano y ángulo. Además se coloca en el mismo sitio.
- **La flecha queda igual que la original:** misma punta y mismo tamaño y, si
  era un bloque (punto, trazo de arquitectura...), el mismo símbolo.
- **La orientación no depende del SCU ni del estilo.** La directriz se
  construye en el sistema del propio texto y se lleva a su sitio con una sola
  transformación.

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
   - **Original** *(por defecto)*: el texto conserva el plano y el ángulo del
     texto original, y queda en el mismo sitio.
   - **Scp**: el texto queda horizontal en el SCP actual.

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
| Flecha | No | `SOLID` (flecha rellena) o un bloque de flecha |

Si no seleccionas la flecha, la directriz nueva usa la flecha del estilo de
directriz múltiple actual, y la flecha vieja se queda en el dibujo.

Los objetos en capas bloqueadas no se pueden seleccionar.

---

## 4. Qué hace exactamente

1. **Une todas las líneas seleccionadas en una sola cadena,** enganchando
   cada vez el extremo más cercano. Si entre dos tramos hay un pequeño hueco,
   lo salva con un tramo recto: no descarta ninguna línea. Los vértices
   alineados en la misma dirección se quedan en uno.
2. **Apoyo y punta:** el extremo de la cadena más cercano al texto es el
   apoyo; el otro, la punta.
3. **Flecha:**
   - Si es un `SOLID`, la punta va a su vértice y el tamaño es su longitud.
   - Si es un bloque, la punta va a su punto de inserción, el tamaño es su
     escala y el símbolo es ese mismo bloque.
4. **Rellano:** si el tramo junto al texto es horizontal respecto al texto, se
   convierte en el rellano de la directriz múltiple:
   - Si el texto estaba **encima de la raya**, el texto queda **subrayado**.
   - Si estaba **al lado**, queda un rellano normal.
5. **Texto:** misma altura real. La directriz se deja **no anotativa** y con
   escala general 1, para que AutoCAD no multiplique la altura por ninguna
   escala.
6. **Borra** el texto, las líneas y la flecha originales.

Si algo falla al reconstruir una directriz, no se cambia nada de ella. El
comando lo avisa y sigue con la siguiente.

---

## 5. Limitaciones

- **Una sola rama por directriz.** Una directriz con varias flechas que salen
  del mismo texto no se reconstruye bien. Hazla en varias pasadas, una por
  rama, o selecciona una rama sola.
- **Arcos en polilíneas:** los tramos curvos pasan a ser rectos entre sus
  vértices.
- **Posición fina del texto:** el texto se coloca con su esquina superior
  izquierda donde estaba la del original. Según el estilo (separación del
  rellano), AutoCAD puede ajustar ligeramente el último tramo para enganchar
  la línea al texto.
- **Formato manual del texto:** se conserva tal cual estaba en el original.
  Si quieres limpiarlo, usa `StripMtext` (`SMT`) sobre las directrices nuevas.
