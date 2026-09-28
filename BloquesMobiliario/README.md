# Bloques de mobiliario en planta

`BloquesMobiliarioPlanta.dxf` es una biblioteca de 64 bloques de mobiliario en vista en planta, dibujados a tamaño real en milímetros (DXF de AutoCAD 2010). El espacio modelo trae un catálogo con todos los bloques rotulados.

![Vista previa del catálogo](vista_previa.png)

## Cómo usarla

1. Abre el DXF en AutoCAD y guárdalo como DWG (`GUARDARCOMO` o `_SAVEAS`).
2. Inserta los bloques en tu plano de una de estas formas:
   - **DesignCenter** (Ctrl+2 o `_ADCENTER`): busca el DWG, entra en *Bloques* y arrástralos al dibujo.
   - **Paleta Bloques** (`_INSERT`, AutoCAD 2020 o posterior), pestaña *Bibliotecas*: elige el DWG.
   - Copiar y pegar desde el catálogo. En ese caso, cámbiales después la capa `CAT-BLOQUES` por la tuya.

## Convenciones

- **Capa 0 y PorCapa.** El bloque toma la capa, el color y el grosor de la capa donde lo insertas.
- **Unidades.** Cada bloque guarda sus unidades de inserción (mm). Si tu dibujo tiene sus unidades definidas (`UNIDADES`, *Unidades de inserción* en metros o centímetros), AutoCAD escala el bloque solo. Si tu dibujo está *sin unidades*, escálalo a mano: ×0,001 para metros y ×0,1 para centímetros.
- **Punto de inserción** (cruz roja del catálogo, capa que no se imprime):
  - muebles contra pared: centro de la trasera;
  - piezas exentas (mesas bajas, alfombras, plantas, mesa de dirección y de reuniones): centro;
  - armarios empotrados: esquina izquierda del hueco, en el plano de la pared.
- **Orientación.** Frente de los muebles hacia abajo (-Y). Las sillas de despacho miran hacia arriba (+Y), así que van delante de las mesas sin girarlas.
- **Aspa (X)** dentro de un mueble: mueble alto.

## Bloques

| Grupo | Bloques |
|---|---|
| Mesas | `MESA_DESPACHO_120x60`, `_140x70`, `_160x80`, `MESA_DIRECCION_180x90`, `MESA_DESPACHO_L_160x160`, `MESA_REUNION_200x100`, `MESA_REUNION_D120` |
| Sillas de despacho | `SILLA_OPERATIVA`, `SILLA_DIRECCION`, `SILLA_CONFIDENTE` |
| Archivo | `CAJONERA_42x58`, `ARCHIVADOR_4C_47x62`, `ARCHIVADOR_LATERAL_80x45`, `ARMARIO_ARCHIVO_100x45` |
| Accesorios | `MONITOR_TECLADO`, `PORTATIL`, `PAPELERA_D30`, `PERCHERO_D50` |
| Conjuntos | `PUESTO_TRABAJO_160x80`, `CONJUNTO_REUNION_6P` |
| Televisión | `TV_43_PARED`, `TV_55_PARED`, `TV_65_PARED`, `TV_75_PARED`, `TV_55_PIE`, `MUEBLE_TV_180x40`, `MUEBLE_TV_240x45` |
| Sillones y sofás | `SILLON_85x85`, `BUTACA_70x75`, `SOFA_2P_160x90`, `SOFA_3P_210x90`, `SOFA_CHAISELONGUE_280x160` |
| Mesas bajas | `MESA_CENTRO_120x60`, `MESA_CENTRO_D80`, `MESA_AUXILIAR_50x50`, `MESA_AUXILIAR_D45`, `MESILLA_NOCHE_50x40` |
| Alfombras | `ALFOMBRA_120x170`, `_160x230`, `_200x300`, `_240x340`, `ALFOMBRA_D160`, `ALFOMBRA_D200` |
| Armarios empotrados | `ARMARIO_EMP_BATIENTE_2H_100x60`, `_3H_150x60`, `_4H_200x60`, `ARMARIO_EMP_CORREDERA_2H_180x60`, `_3H_240x60`, `DETALLE_ARMARIO_JAMBA` |
| Decoración | `APARADOR_160x45`, `APARADOR_200x50`, `CONSOLA_100x30`, `CONSOLA_120x35`, `ESTANTERIA_80x35`, `ESTANTERIA_120x35`, `VITRINA_100x40`, `BALDA_80x25`, `PEANA_40x40`, `PEANA_D40`, `PLANTA_GRANDE_D80`, `PLANTA_PEQUENA_D40`, `LAMPARA_PIE_D45`, `LAMPARA_MESA_D30`, `JARRON_D20` |

Los armarios empotrados incluyen tapajuntas, premarco, cerco, casco, divisiones, puertas con su barrido (o correderas con sus flechas), barra y perchas. `DETALLE_ARMARIO_JAMBA` es la sección horizontal de la jamba a tamaño real, con rótulos de 12,5 mm (2,5 mm impresos a E 1:5).

## Regenerar o modificar

Las medidas están en `generar_bloques.py`. Para volver a generar el DXF:

```
pip install ezdxf
python3 generar_bloques.py
```
