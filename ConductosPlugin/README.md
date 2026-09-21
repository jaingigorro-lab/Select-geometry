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
    cercano (hasta 90°), con codos **curvos** (bloque de 3 arcos concéntricos).
    En el dibujo solo se ve el diámetro del tramo recto; la sección del propio
    codo queda solo en Propiedades, nunca dibujada.
  - **Rectangular**: pide ancho y alto; los giros se ajustan al mismo
    múltiplo de 15° (hasta 90°) que en circular, resueltos como **miter
    recto** — sin radio, sin bisel, sin ninguna geometría de codo aparte: es
    como es un codo rectangular real (una pared cortada en ángulo no se puede
    fabricar con radio salvo que se pida expresamente una pieza curva, cosa
    que este plugin no modela); las dos paredes de los tramos que se
    encuentran simplemente se cortan en su intersección exacta, a cualquier
    ángulo. La sección del codo (igual que en circular) queda solo en
    Propiedades, nunca dibujada. Cada tramo recto lleva un rótulo
    "ANCHOxLARGO" en una misma fila (el "x" es un separador fijo, no un
    atributo, para que ANCHO y LARGO se sigan pudiendo extraer como valores
    numéricos independientes); ALTO también queda disponible, pero solo en
    Propiedades.

  Al principio también se preguntan la **altura de texto** de los rótulos, la
  **separación** entre el rótulo y la pared del conducto, y cada cuánto
  **repetir** el rótulo a lo largo de un mismo tramo recto (0 = uno solo, en
  el centro — el valor de siempre) — los tres, a tu elección, según la escala
  de dibujo que vayas a usar y lo largos que sean los tramos. Cada tramo
  (circular o rectangular) lleva un rótulo con sus atributos ANCHO (`⌀200` en
  circular), ALTO (solo rectangular, oculto por defecto) y LARGO, como bloque
  **vinculado** (`CVENT_ROTULO_CIRC`/`CVENT_ROTULO_RECT`) — así queda
  disponible para mediciones/extracción de cantidades (`DATAEXTRACTION`,
  `BATTMAN`), no es solo texto suelto (ver más abajo por qué es un bloque
  aparte).

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

## Bloques: se generan solos, no hace falta una librería externa

El LSP original necesitaba una librería de bloques (`.dwg`) construida a mano en
`BEDIT` — AutoLISP no puede crear bloques dinámicos. En C# **no hace falta**: el
plugin genera los bloques la primera vez que hacen falta (`BlockFactory`, dentro
de `ConductosPlugin.cs`) y los reutiliza después:

- `CVENT_TRAMO_RECTO_D<diámetro>` y `CVENT_REDUCCION_D<d1>_D<d2>` — un cuerpo de
  longitud **unidad** (1) que se estira en X (`ScaleFactors`) a la longitud real
  de cada tramo al insertarse. Sin atributos (ver más abajo por qué).
- `CVENT_CODO_A<ángulo>` — un único bloque por ángulo normalizado (15/30/45/
  60/75/90), construido a un diámetro de referencia (100) con tres arcos
  concéntricos (pared interior, eje, pared exterior); se inserta escalado
  uniformemente al diámetro real, y reflejado (`ScaleFactors.Y` negativo, ver
  más abajo por qué Y y no X) para un giro a la derecha.
- `CVENT_ROTULO_CIRC` / `CVENT_ROTULO_RECT` — el rótulo de cada tramo recto
  (ver siguiente sección), con sus atributos ANCHO/ALTO/LARGO.
- `CVENT_ROTULO_RECT_CODO` — variante de `CVENT_ROTULO_RECT` usada
  **exclusivamente** para la sección de un codo rectangular (siempre
  invisible en el dibujo, solo Propiedades): tres atributos apilados
  (ANCHO/ALTO/LARGO), sin ninguna otra geometría. Hace falta como bloque
  aparte porque `CVENT_ROTULO_RECT` lleva el separador "x" fijo (texto
  normal, no atributo) entre ANCHO y LARGO para el formato visible
  "ANCHOxLARGO" — y una entidad no-atributo dentro de un bloque **siempre**
  se dibuja, pase lo que pase con la visibilidad de sus atributos, así que
  insertar un codo con ese mismo bloque dejaría el "x" (fantasma, sin
  números) visible en el dibujo pese al `forceInvisible`. El circular no
  necesita nada de esto: su bloque de tramo recto no lleva ninguna geometría
  fija, así que lo reutiliza tal cual para los codos.

Solo el tipo **circular** usa bloque de **codo**: un codo real en un conducto
rectangular es un simple corte a inglete (sin radio, sin bisel — una pieza
curva rectangular es un encargo especial que este plugin no modela), así que
sus paredes simplemente se cortan en su intersección exacta con el mismo
cierre a inglete (`DuctTracer.ProcessNextPiece`) que ya usan las reducciones y
transiciones, sin ninguna geometría de codo aparte. El rótulo, en cambio,
**siempre** es un bloque (`CVENT_ROTULO_*`), tanto en circular como en
rectangular.

### Importante al volver a probar tras un cambio: un bloque ya existente en tu dwg se queda con su geometría VIEJA

Si vienes reutilizando el **mismo** archivo `.dwg` de pruebas entre una versión
del plugin y la siguiente (lo normal al iterar), ten en cuenta que un bloque
como `CVENT_ROTULO_RECT` o `CVENT_CODO_A90` **ya existe** en ese dwg desde la
primera vez que lo usaste — y AutoCAD no sabe que el código que lo generó ha
cambiado. Por eso, desde esta versión, el plugin lleva un control por
**sesión de AutoCAD** (`BlockFactory._rebuiltThisSession`): la primera vez que
hace falta un bloque en la sesión actual, se reconstruye con la geometría del
código que tengas cargado ahora mismo, aunque ya existiera (con geometría
antigua) en el dwg; a partir de ahí, dentro de esa misma sesión, se reutiliza
sin volver a tocarlo (para no rehacer el mismo trabajo en cada clic).

En la práctica, esto significa que **basta con seguir la rutina de siempre**
—cerrar y volver a abrir AutoCAD antes de cada `NETLOAD` de una DLL nueva—
para que los bloques se pongan al día solos; no hace falta purgarlos ni
borrar el dwg. Si alguna vez pruebas una DLL nueva **sin** reiniciar AutoCAD
(recargando con `NETLOAD` en la misma sesión), los bloques que ya se
reconstruyeron en esa sesión NO se volverán a tocar aunque el código haya
cambiado — de ahí la importancia de reiniciar AutoCAD en cada prueba.

### Si la sección de un codo sigue apareciendo en el dibujo: revisa ATTDISP

CVENT y CVENTT fuerzan al arrancar la variable de sistema `ATTDISP` a `1`
("Normal") — si estaba en `2` ("Activado"), AutoCAD muestra **todos** los
atributos de bloque sin importar su propio flag `Invisible`, incluida la
sección de un codo (que este plugin deja siempre invisible). Con `ATTDISP` en
`0` ("Desactivado") pasaría lo contrario: ni siquiera ANCHO/LARGO de un tramo
recto se verían. Si aun así ves texto donde no debería (p. ej. porque algo en
el dwg ya había puesto `ATTDISP` en `2` antes de ejecutar el comando, o por
cualquier otro motivo), comprueba el valor a mano con el comando `ATTDISP`
(opción `Normal`).

### Por qué el rótulo es un bloque APARTE, no un atributo del tramo recto

Los bloques de tramo recto/reducción se insertan con `ScaleFactors` **no
uniforme** (X = longitud real, Y = 1 fijo). Un atributo definido dentro de ese
bloque se coloca bien en `Position`/`Rotation`
(`AttributeReference.SetAttributeFromBlock` calcula eso correctamente bajo esa
transformación), pero **no** `Height`/`WidthFactor` — salía un texto con una
altura disparatada (proporcional a la longitud del tramo, no al diámetro), que
de lejos parecía una mancha y, al hacer zoom, "desaparecía" porque la vista
quedaba dentro de una letra gigante.

Fijar `Height` a mano tras cada `SetAttributeFromBlock` arreglaba el tamaño,
pero era frágil (había que repetirlo cada vez que `AdjustBodyLength` recortaba
el bloque) y, más importante: el usuario necesitaba que el rótulo siguiera
siendo un **atributo real** (vinculado al bloque, extraíble con
`DATAEXTRACTION`/`BATTMAN` para mediciones de sección y longitud), así que
pasarlo a texto suelto tampoco servía.

La solución fue separar el rótulo en su **propio bloque** (`BlockFactory.
EnsureLabelBlock`/`InsertLabel`), sin ninguna otra geometría, insertado
siempre con `ScaleFactors` **uniforme** (`X = Y = alturaTexto`, la altura que
el usuario elige al principio de CVENT/CVENTT). Al ser uniforme,
`SetAttributeFromBlock` calcula bien `Height`/`WidthFactor` sin ningún ajuste
a mano — el mismo mecanismo que ya usaba, sin problemas, el bloque de codo.
Como es un bloque independiente de las paredes, funciona igual en circular
(paredes en bloque) y en rectangular (paredes en líneas sueltas): el rótulo
siempre queda vinculado, y su tamaño siempre sale bien calculado.

El rótulo se orienta con la dirección del tramo (`BlockFactory.InsertLabel`),
pero si esa dirección cae en la mitad "de vuelta" (más de 90° respecto a la
horizontal) se gira 180° adicionales, para que el texto nunca salga boca
abajo o al revés — se lee siempre de izquierda a derecha, sea cual sea el
sentido en que se trazó el tramo.

## Corrección respecto al LSP original

Traduciendo el LSP se encontró un fallo latente: cuando una pieza (tramo recto o
reducción) se dibujaba como bloque, el estado "pendiente" se descartaba por
completo (`nil`) en vez de conservar su dirección/diámetro — y como el
procesamiento del codo siguiente exige ese estado pendiente
(`(and pending (> (abs turnAngle) eps))`), el resultado era que **ningún giro se
procesaba como codo** justo después de una pieza dibujada como bloque (ni bloque
de codo ni arcos sueltos), dejando una esquina sin resolver. En la traducción,
`PendingPiece` se conserva siempre (con un flag `WallsAlreadyDrawn` que solo evita
volver a dibujar las paredes ya cubiertas por el bloque), así que los codos se
procesan correctamente venga o no precedidos de un bloque.

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
antes del siguiente `NETLOAD`, o los cambios no se verán.

Para que se cargue automáticamente cada vez que abras AutoCAD, puedes añadir la
ruta de la DLL a `APPAUTOLOAD` o a la carpeta de soporte, o registrar el plugin en
el `acad.rx`/paquete de contenido según tu configuración habitual.
