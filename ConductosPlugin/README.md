# Conductos HVAC (plugin .NET para AutoCAD)

Plugin en C# para AutoCAD 2024 (y compatibles con .NET Framework 4.8) que sustituye
al LSP `Conductos.lsp` del repositorio, con los mismos comandos y comportamiento,
pero usando la API real de AutoCAD (`Autodesk.AutoCAD.DatabaseServices`, etc.) en
vez de AutoLISP/ActiveX. Compilado y verificado contra el paquete NuGet oficial de
Autodesk (`AutoCAD.NET` 24.3.0) — no contra un AutoCAD real, pero sí contra sus
tipos y firmas exactas, así que no hay ambigüedades de VARIANT/coerción como en LSP.

## Comandos

- **CONDUCTO** — traza un recorrido de conducto (circular o rectangular) a doble
  línea y a escala real. En cada cambio de dirección inserta un **bloque** de codo
  normalizado (con atributos `DIAM`/`ANCHO`, `ANG`, `TIPO`), reutilizado entre codos
  del mismo tipo/dimensión/ángulo. Si algún codo no tiene un ángulo normalizado
  (90/45/30/22.5/15 en circular, solo 90 en rectangular), el recorrido entero se
  rechaza sin crear nada. El eje trazado se conserva como referencia (gris,
  línea `CENTER`), siguiendo la forma real del conducto (con el arco de cada codo
  circular, o pasando por el vértice en rectangular).

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

## Diferencias respecto al LSP

- Los codos y bloques se crean con la API tipada de AutoCAD (`Arc`, `Line`,
  `AttributeDefinition`, `BlockTableRecord`, `BlockReference`...), no con
  `entmake`/ActiveX — el compilador ya valida que cada llamada existe y tiene el
  tipo correcto, cosa que no era posible verificar en AutoLISP desde este entorno.
- El desfase de paredes usa `Polyline.GetOffsetCurves`, sin la ambigüedad de
  `vla-Offset` vista en el LSP.
- La línea de eje usa el mismo enfoque (bulge por vértice para el arco del codo
  circular, o pasando por el vértice real en rectangular).
