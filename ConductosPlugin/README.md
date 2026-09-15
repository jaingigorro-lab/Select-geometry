# Conductos HVAC (plugin .NET para AutoCAD)

Plugin en C# para AutoCAD 2024 (y compatibles con .NET Framework 4.8), usando la API
real de AutoCAD (`Autodesk.AutoCAD.DatabaseServices`, etc.) en vez de AutoLISP/ActiveX.
Todo el código vive en un único archivo, `ConductosPlugin.cs`. Compilado y verificado
contra el paquete NuGet oficial de Autodesk (`AutoCAD.NET` 24.3.0) — no contra un
AutoCAD real, pero sí contra sus tipos y firmas exactas, así que no hay ambigüedades
de VARIANT/coerción como en LSP.

## Comandos

- **CONDUCTO** — traza un recorrido de conducto (circular o rectangular) a doble
  línea y a escala real, de forma **interactiva**: la pared, el eje y los codos se
  van dibujando tramo a tramo según haces clic en cada punto, no al terminar todo el
  recorrido. A partir del segundo tramo, cada punto se ajusta en vivo al ángulo de
  codo normalizado SMACNA más cercano (90/45/30/22.5/15 en circular, solo 90 en
  rectangular, o 0 para seguir recto) y en pantalla se ve un abanico con todas las
  rutas/ángulos disponibles desde ese punto, con el segmento activo resaltado — así
  el ángulo resultante siempre es válido y nunca hace falta rechazar el recorrido
  después de trazarlo. Cada codo se marca solo con dos líneas delimitadoras
  perpendiculares al tramo (dónde empieza y dónde termina la zona del codo), sin
  bloque ni texto. El eje trazado se conserva como referencia (gris, línea
  `CENTER`).

- **CONDUCTORAMAL** — inserta una unión en T (un ramal) o en cruz (dos ramales
  opuestos) sobre un conducto principal ya existente (dos paredes paralelas que
  seleccionas). El conducto principal no se modifica; cada ramal se recorta
  automáticamente donde alcanza la pared más cercana. Solo válido sobre un tramo
  recto del conducto principal, no sobre un codo.

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
4. Ya están disponibles `CONDUCTO` y `CONDUCTORAMAL`.

Para que se cargue automáticamente cada vez que abras AutoCAD, puedes añadir la
ruta de la DLL a `APPAUTOLOAD` o a la carpeta de soporte, o registrar el plugin en
el `acad.rx`/paquete de contenido según tu configuración habitual.

## Como funciona el trazado interactivo de CONDUCTO

`CONDUCTO` usa un `DrawJig` (`DuctTurnJig`) para el punto siguiente en cuanto ya
hay un tramo previo (heading). En cada frame del arrastre del ratón:

1. Calcula el ángulo entre el cursor y el pivote (el último punto fijado) respecto
   a la dirección de entrada.
2. Lo ajusta (snap) al ángulo de codo normalizado más cercano para ese tipo de
   conducto (`GeometryUtil.NearestStandardTurn`), conservando la distancia libre.
3. Dibuja el abanico de todas las rutas posibles desde el pivote y resalta en verde
   el segmento que se crearía si se hace clic en ese instante.

Al aceptar el punto (clic, o coordenadas + Intro), si ese vértice implica un giro
real (ángulo ≠ 0) se cierra inmediatamente en la base de datos: el tramo de pared
hasta el arranque del codo, el tramo de eje correspondiente, y las dos líneas
delimitadoras del codo (inicio/fin). Si el ángulo ajustado es 0 (seguir recto), no
se inserta ningún codo y el trazado simplemente continúa. Pulsar Intro sin mover el
ratón termina el comando conservando todo lo ya dibujado; Escape aborta el trazado
pero también conserva lo ya dibujado (no hay "todo o nada").

## Diferencias respecto al LSP

- Los codos ya no son bloques con atributos: son solo dos líneas delimitadoras
  perpendiculares al tramo, sin texto ni `BlockReference`.
- El desfase de paredes usa `Polyline.GetOffsetCurves`, sin la ambigüedad de
  `vla-Offset` vista en el LSP.
- El trazado es interactivo (jig con snapping de ángulo en vivo) en vez de pedir
  todos los puntos primero y validar/rechazar el recorrido entero al final.
