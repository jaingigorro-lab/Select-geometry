# CVENT / CVENTT (plugin .NET para AutoCAD)

Plugin en C# para AutoCAD 2024 (y compatibles con .NET Framework 4.8), traducido
1:1 de `ConductoVentilacionCircular_CVENT.lsp` (el LSP original vive en la raiz del
repo), usando la API real de AutoCAD (`Autodesk.AutoCAD.DatabaseServices`, etc.) en
vez de AutoLISP/ActiveX. Todo el código vive en un único archivo,
`ConductosPlugin.cs`.

Traza conductos de ventilación circular en planta (representación a dos líneas),
con codos **curvos**, reducciones, y derivaciones en T o en cruz que se acoplan a
un conducto ya existente.

## Comandos

- **CVENT** — traza un conducto nuevo desde cero, punto a punto. Cada giro se
  ajusta al múltiplo de 15° más cercano (hasta 90°); se puede desactivar sobre la
  marcha con la palabra clave `Libre`. Con `Diametro` se fija un diámetro nuevo: al
  marcar el punto siguiente se inserta la reducción automáticamente y el conducto
  continúa ya con el diámetro nuevo. `Salir` (o Intro) termina el trazado.

- **CVENTT** — arranca una derivación (T o cruz) desde un punto de un conducto ya
  dibujado con CVENT: seleccionas el **eje** (capa `MEP-CONDUCTOS-EJE`, no la
  pared), indicas el diámetro del conducto principal y de la derivación, eliges
  Te o Cruz, y (si es Te) marcas con un clic hacia qué lado sale. A partir de ahí
  se traza igual que con CVENT. El conducto principal nunca se modifica ni se
  corta — solo se marca el arranque de cada ramal con una línea perpendicular
  sobre su propio eje.

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
  de cada tramo al insertarse.
- `CVENT_CODO_A<ángulo>` — un único bloque por ángulo normalizado (15/30/45/
  60/75/90), construido a un diámetro de referencia (100) con tres arcos
  concéntricos (pared interior, eje, pared exterior); se inserta escalado
  uniformemente al diámetro real, y reflejado (`ScaleFactors.X` negativo) para
  un giro a la derecha.

Si por lo que sea la creación de un bloque fallara, el propio `DuctTracer` puede
recurrir a líneas/arcos sueltos (`useBlocks = false`) — hoy `DuctRunner` siempre
pide bloques, ya que `BlockFactory` los genera bajo demanda y no depende de
ningún archivo externo.

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
