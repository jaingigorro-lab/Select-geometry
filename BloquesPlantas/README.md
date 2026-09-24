# Bloques de plantas de interior

11 plantas × 2 vistas = 22 bloques (`VEG_<planta>_PLANTA` y `VEG_<planta>_ALZADO`):
Monstera, Ficus lyrata, Kentia, Ave del paraíso, Olivo, Sansevieria, Helecho,
Pothos colgante, Cactus, Pilea y Trío de suculentas.

| Archivo | Unidades del dibujo |
|---|---|
| `Plantas_interior_mm.dxf` | milímetros |
| `Plantas_interior_cm.dxf` | centímetros |
| `Plantas_interior_m.dxf`  | metros |

Los tres contienen los mismos bloques a escala real. Usa el que coincida con las
unidades de tu plano, o arrastra los bloques desde DesignCenter (`ADCENTER`), que
reescala solo porque cada bloque lleva sus unidades de inserción.

- **Punto base:** en planta, el centro de la maceta. En alzado, la base de la maceta
  a cota 0. El pothos colgante en alzado se inserta por el gancho del techo.
- **Capas:** `VEG-HOJAS`, `VEG-NERVIOS`, `VEG-TRONCO`, `VEG-MACETA`, `VEG-FLOR` y
  `VEG-RELLENO` (colores sólidos). Las líneas ocultas ya están eliminadas, así que al
  congelar `VEG-RELLENO` queda un plano a línea limpio.
- **Impresión:** con `monochrome.ctb` los rellenos salen negros. En ese caso congela
  `VEG-RELLENO` o asígnale un tramado del 20–30 % en la tabla de estilos de trazado.

`generar_plantas.py` regenera todo (`pip install ezdxf shapely matplotlib`).
