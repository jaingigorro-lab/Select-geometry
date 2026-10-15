# Familia Revit: mueble para televisión

`CrearMuebleTV.py` construye, dentro del Editor de familias de Revit, una familia
**paramétrica** de mueble bajo para TV (categoría *Mobiliario*). El `.rfa` es un
formato binario que solo Revit puede escribir, por eso la familia se genera con
un script en vez de distribuirse ya hecha.

```
+-------------------------------------------------------+   <- Tapa
|  Puerta    |  |   Nicho abierto  |  |   Puerta        |
|  izquierda |  |------------------|  |   derecha       |   <- Estantes
+--+------------------------------------------------+---+   <- Fondo
   |              Zócalo retranqueado               |
```

Piezas: 2 laterales hasta el suelo, tapa, fondo, trasera, zócalo retranqueado,
2 divisores, estante del nicho central, 2 estantes laterales y 2 puertas
enrasadas (sin tirador, tipo *push-to-open*).

## Cómo generarla

1. Revit → *Archivo › Nuevo › Familia* → plantilla **Mobiliario métrico.rft**
   (*Metric Furniture.rft*). También vale *Modelo genérico métrico.rft*; el script
   cambia la categoría a Mobiliario.
2. Ejecuta `CrearMuebleTV.py` con **pyRevit** (*Run script*, o colócalo en un
   botón de tu extensión) o con **RevitPythonShell**.
3. Guarda como `MuebleTV.rfa` y cárgala en el proyecto.

Origen de inserción: **centro de la cara trasera, a nivel de suelo**, así que se
coloca directamente contra un muro. El frente mira hacia −Y (alzado frontal).

## Parámetros (de tipo)

| Parámetro | Por defecto | Notas |
|---|---|---|
| Ancho | 1800 mm | simétrico respecto al centro |
| Alto | 500 mm | total, incluido zócalo |
| Profundidad | 450 mm | |
| Espesor | 18 mm | tableros y puertas |
| Espesor_Trasera | 6 mm | |
| Altura_Zocalo | 80 mm | |
| Retranqueo_Zocalo | 40 mm | |
| Ancho_Nicho | 700 mm | hueco central libre, centrado |
| Altura_Estante | 180 mm | medida desde la cara superior del fondo |
| Mostrar_Puertas | Sí | |
| Mostrar_Estantes_Laterales | Sí | |
| Material_Cuerpo | MuebleTV - Roble | |
| Material_Puertas | MuebleTV - Lacado blanco | |

Tipos creados: **MuebleTV 1800** (principal), **1400**, **2200** y
**2400 alto** (600 mm de alto). Para añadir otros, edita `TIPOS_EXTRA` al
principio del script o usa *Tipos de familia* en Revit.

Coherencia: `Ancho_Nicho + 4·Espesor` debe ser menor que `Ancho`, y
`Altura_Estante + Espesor` menor que el hueco interior
(`Alto − Altura_Zocalo − 2·Espesor`); si no, Revit avisará de geometría
inválida al flexionar.

## Cómo está construida

Cada plano de referencia (prefijo `MTV`) cuelga de un único padre mediante una
cota etiquetada con un parámetro; los tres planos raíz (centro, trasera, suelo)
están fijados. Cada pieza es una extrusión con sus seis caras alineadas y
bloqueadas a planos de referencia, así que todo flexiona al cambiar los
parámetros. Funciona con la API antigua (`ParameterType`) y la nueva
(`SpecTypeId`/`GroupTypeId`, Revit 2022+).
