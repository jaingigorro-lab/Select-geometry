# CVENT / CVENTT (plugin .NET para AutoCAD)

Plugin en C# para AutoCAD 2024 (y compatibles con .NET Framework 4.8), traducido
1:1 de `ConductoVentilacionCircular_CVENT.lsp` (el LSP original vive en la raiz del
repo), usando la API real de AutoCAD (`Autodesk.AutoCAD.DatabaseServices`, etc.) en
vez de AutoLISP/ActiveX. Todo el código vive en un único archivo,
`ConductosPlugin.cs`.

Traza conductos de ventilación en planta (representación a dos líneas),
**circulares o rectangulares**, con reducciones y derivaciones en T o en cruz
que se acoplan a un conducto ya existente.

## Comandos

- **CVENT** — traza un conducto nuevo desde cero, punto a punto. Primero
  pregunta el tipo (`Circular`/`Rectangular`):
  - **Circular**: pide el diámetro; cada giro se ajusta al múltiplo de 15° más
    cercano (hasta 90°), con codos **curvos** (tres arcos concéntricos). En el
    dibujo solo se ve el diámetro del tramo recto; la sección del propio codo
    queda solo en Propiedades, nunca dibujada.
  - **Rectangular**: pide ancho y alto; los giros se ajustan al mismo
    múltiplo de 15° que en circular. Un codo rectangular real es un **miter
    recto** — sin radio, sin bisel (una pieza curva rectangular es un encargo
    especial que este plugin no modela) — así que las dos paredes que se
    encuentran simplemente se cortan en su intersección exacta, a cualquier
    ángulo. La sección del codo (igual que en circular) queda solo en
    Propiedades, nunca dibujada. Cada tramo recto lleva un rótulo
    "ANCHOxLARGO" en una misma fila (el "x" es un separador fijo, no un
    atributo, para que ANCHO y LARGO se sigan pudiendo extraer como valores
    numéricos independientes); ALTO también queda disponible, pero solo en
    Propiedades.

  Al principio también se preguntan la **altura de texto** de los rótulos y la
  **separación** entre el rótulo y la pared del conducto — a tu elección,
  según la escala de dibujo que vayas a usar. Cada tramo (circular o
  rectangular) lleva un rótulo con sus atributos ANCHO (`⌀200` en circular),
  ALTO (solo rectangular, oculto por defecto) y LARGO — como **atributo real
  del mismo bloque** que la pared de ese tramo (ver más abajo), así queda
  disponible para mediciones/extracción de cantidades (`DATAEXTRACTION`,
  `BATTMAN`) seleccionando un único objeto, no uno aparte.

  Se puede desactivar la restricción de ángulo sobre la marcha con la palabra
  clave `Libre`. Con `Diametro` (circular) o `Ancho` (rectangular, que
  también pide un `Alto` nuevo) se fija una dimensión nueva: al marcar el
  punto siguiente se inserta la reducción automáticamente y el conducto
  continúa ya con la dimensión nueva. `Salir` (o Intro) termina el trazado.

- **CVENTT** — arranca una derivación (T o cruz) desde un punto de un conducto ya
  dibujado con CVENT: seleccionas el **eje** (capa `MEP-CONDUCTOS-EJE`, no la
  pared), indicas el diámetro del conducto principal y de la derivación, eliges
  Te o Cruz, y (si es Te) marcas con un clic hacia qué lado sale. A partir de ahí
  se traza igual que con CVENT. El conducto principal nunca se modifica ni se
  corta — solo se marca el arranque de cada ramal con una línea perpendicular
  sobre su propio eje. Por ahora **CVENTT solo admite derivaciones circulares**.

Cada codo, cada reducción y cada derivación quedan delimitados con una línea
perpendicular al conducto que marca dónde empieza y dónde termina esa pieza
especial. Las paredes de tramos vecinos se unen a inglete en cada vértice.

## Cada pieza es UN ÚNICO bloque: pared + eje + su propio rótulo

El LSP original necesitaba una librería de bloques (`.dwg`) construida a mano en
`BEDIT` — AutoLISP no puede crear bloques dinámicos. En C# no hace falta: el
plugin (`BlockFactory`, dentro de `ConductosPlugin.cs`) genera un bloque por
cada **pieza** del recorrido (tramo recto, reducción o codo), en el momento en
que se sabe exactamente dónde debe terminar (inglete con la pieza vecina, o
tangencia con el siguiente codo) — nunca antes.

Cada pieza es una definición de bloque **nueva y única** (nombre generado,
`CVENT_PIEZA_<n>`), construida ya a su tamaño real en coordenadas locales, e
insertada siempre a escala **uniforme** (`1,1,1`, nunca estirada después). Un
único bloque contiene:

- las dos líneas de pared (o, en un codo circular, los tres arcos concéntricos:
  pared interior, eje, pared exterior),
- el eje (capa aparte),
- su propio rótulo (ANCHO/ALTO/LARGO), como **atributos reales de ese mismo
  bloque** — no de uno aparte.

No se comparte definición entre piezas (cada tramo tiene su propio largo, y a
veces sus propias esquinas a inglete con la pieza vecina, así que no tendría
sentido reutilizar una), pero a cambio: el rótulo queda vinculado al bloque de
la pared, seleccionable como un único objeto — que es lo que se pedía — y, al
ser siempre escala uniforme, `AttributeReference.SetAttributeFromBlock` calcula
bien `Height`/`WidthFactor` sin ningún ajuste a mano (ver por qué importa, más
abajo). Un codo rectangular no tiene bloque de pared propio (es un simple
inglete, resuelto por la intersección de las dos piezas rectas vecinas); solo
lleva una marca mínima, siempre invisible, con su sección en Propiedades.

### Por qué la escala tiene que ser uniforme

Un bloque insertado con `ScaleFactors` **no uniforme** (p. ej. X = longitud
real, Y = 1 fijo — lo que haría falta para reutilizar un único bloque
"plantilla" estirado a cada longitud) coloca bien un atributo en
`Position`/`Rotation` (`SetAttributeFromBlock` calcula eso bien bajo esa
transformación), pero **no** `Height`/`WidthFactor` — el texto salía con una
altura disparatada (proporcional a la longitud del tramo), que de lejos
parecía una mancha y, al hacer zoom, "desaparecía" porque la vista quedaba
dentro de una letra gigante. Fijar `Height` a mano después funcionaba, pero
era frágil.

La solución fue no reutilizar bloques: cada pieza se construye ya a su tamaño
real, en su propio sistema de coordenadas local (`GeometryUtil.ToLocal`), y se
inserta con escala **siempre uniforme** — así no hay ningún estiramiento que
corrompa el atributo, sea cual sea la longitud real del tramo.

El rótulo se orienta con la dirección del tramo, pero si esa dirección cae en
la mitad "de vuelta" (más de 90° respecto a la horizontal) el atributo se gira
180° **en su propia rotación local** (no la del bloque, que sigue apuntando a
la dirección real del tramo — así la pared no se ve afectada), para que el
texto nunca salga boca abajo o al revés. Cada atributo (y el separador "x" de
rectangular) usa justificación **Medio Centro** (`AttachmentPoint.MiddleCenter`),
centrado sobre su propio punto de inserción.

## Si la sección de un codo sigue apareciendo en el dibujo: revisa ATTDISP

CVENT y CVENTT intentan forzar al arrancar la variable de sistema `ATTDISP` a
`1` ("Normal", envuelto en un `try/catch` que nunca deja tirar abajo el
comando aunque falle) — si estaba en `2` ("Activado"), AutoCAD muestra
**todos** los atributos de bloque sin importar su propio flag `Invisible`,
incluida la sección de un codo (que este plugin deja siempre invisible). Con
`ATTDISP` en `0` ("Desactivado") pasaría lo contrario: ni siquiera
ANCHO/LARGO de un tramo recto se verían. Si ves texto donde no debería (o si
`DrawingUtil.EnsureAttDispNormal` no consigue ajustarlo en tu instalación),
comprueba el valor a mano con el comando `ATTDISP` (opción `Normal`).

## Corrección respecto al LSP original

Traduciendo el LSP se encontró un fallo latente: cuando una pieza (tramo recto o
reducción) se dibujaba como bloque, el estado "pendiente" se descartaba por
completo (`nil`) en vez de conservar su dirección/diámetro — y como el
procesamiento del codo siguiente exige ese estado pendiente
(`(and pending (> (abs turnAngle) eps))`), el resultado era que **ningún giro se
procesaba como codo** justo después de una pieza dibujada como bloque, dejando
una esquina sin resolver. En la traducción, `PendingPiece` se conserva siempre,
así que los codos se procesan correctamente en cualquier caso.

## Compilar

Necesitas el SDK de .NET (`dotnet build` funciona igual en Windows/Mac/Linux para
compilar, aunque el plugin solo se pueda *cargar y ejecutar* dentro de AutoCAD en
Windows):

```
cd ConductosPlugin
dotnet build -c Release
```

Esto genera `bin/Release/ConductosPlugin.dll`. El proyecto usa el paquete NuGet
`AutoCAD.NET` (mismas DLLs de referencia que Autodesk publica oficialmente); no
hace falta tener AutoCAD instalado para compilar, pero **si tienes una versión de
AutoCAD distinta a 2024**, cambia la versión del paquete en
`ConductosPlugin.csproj` (`<PackageReference Include="AutoCAD.NET" ... />`) por la
que corresponda:

| AutoCAD | Version del paquete | TargetFramework |
|---|---|---|
| 2024 o anterior | `24.3.0` (o la que corresponda a tu año) | `net48` |
| 2025 | `25.0.1` | `net8.0` |
| 2026 | `25.1.1` | `net10.0` |
| 2027 | `26.0.0` | `net10.0` |

## Cargar en AutoCAD

1. Abre AutoCAD.
2. Ejecuta el comando `NETLOAD`.
3. Selecciona `ConductosPlugin.dll` (la de `bin/Release`, o `bin/Debug` si has
   compilado en modo Debug).
4. Ya están disponibles `CVENT` y `CVENTT`.

**Importante:** AutoCAD no puede descargar una DLL ya cargada por `NETLOAD` en la
misma sesión. Si recompilas y vuelves a probar, **cierra y vuelve a abrir AutoCAD**
antes del siguiente `NETLOAD`, o los cambios no se verán. Además, cada pieza es
un bloque con nombre único generado en el momento (`CVENT_PIEZA_<n>`), así que
no hay ningún bloque "viejo" del dwg que pueda quedarse con geometría
desactualizada entre una prueba y la siguiente.

Para que se cargue automáticamente cada vez que abras AutoCAD, puedes añadir la
ruta de la DLL a `APPAUTOLOAD` o a la carpeta de soporte, o registrar el plugin en
el `acad.rx`/paquete de contenido según tu configuración habitual.
