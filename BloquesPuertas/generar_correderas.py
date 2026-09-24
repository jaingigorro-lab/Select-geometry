#!/usr/bin/env python3
"""Bloques de puerta corredera en planta (vista de superficie y empotrada).
Geometria en metros; se exporta en m, cm y mm.

Punto base (0,0): jamba izquierda del hueco, en la cara del tabique por la
que corre la hoja (lado pasillo). El hueco va de x=0 a x=A y la hoja se
recoge hacia la IZQUIERDA (x<0). Para la otra mano usar SIMETRIA.
El tabique queda hacia y<0 (espesor T)."""
import os
import ezdxf
from ezdxf.enums import TextEntityAlignment

HERE = os.path.dirname(os.path.abspath(__file__))
UNITS = {'m': (1.0, 6), 'cm': (100.0, 5), 'mm': (1000.0, 4)}
T = 0.10  # espesor de tabique de referencia


def build(units):
    f, iu = UNITS[units]
    doc = ezdxf.new('R2010')
    doc.header['$INSUNITS'] = iu
    doc.linetypes.add('OCULTA', pattern=[0.15 * f, 0.10 * f, -0.05 * f])
    doc.layers.add('A-CARPINTERIA', color=4).dxf.lineweight = 18
    doc.layers.add('A-CARPINTERIA-OCULTA', color=4, linetype='OCULTA').dxf.lineweight = 13
    doc.layers.add('A-TEXTO', color=7)
    P = lambda x, y: (x * f, y * f)

    def pl(b, pts, layer='A-CARPINTERIA', closed=False):
        b.add_lwpolyline([P(*p) for p in pts], close=closed, dxfattribs={'layer': layer})

    def rect(b, x0, y0, x1, y1, layer='A-CARPINTERIA'):
        pl(b, [(x0, y0), (x1, y0), (x1, y1), (x0, y1)], layer, True)

    def arrow(b, x0, x1, y):
        pl(b, [(x0, y), (x1, y)])
        d = 0.05 if x1 > x0 else -0.05
        pl(b, [(x1 - d, y + 0.025), (x1, y), (x1 - d, y - 0.025)])

    names = []
    for hoja in (0.625, 0.725, 0.825):
        A = round(hoja - 0.025, 3)            # hueco de paso
        tag = f'{int(round(hoja * 1000)):03d}'
        # ---- corredera vista (de superficie, colgada de guia por el lado del pasillo)
        n = f'PUERTA_CORREDERA_VISTA_{tag}'
        b = doc.blocks.new(n, dxfattribs={'description':
            f'Puerta corredera de superficie, hoja {hoja:.3f} m, hueco {A:.3f} m. '
            f'Necesita {hoja + 0.05:.2f} m de pared libre a la izquierda del hueco.'})
        b.block_record.dxf.units = iu
        for x in (0, A):                                   # jambas del hueco
            pl(b, [(x, 0), (x, -T)])
        rect(b, -0.0125, 0.015, A + 0.0125, 0.055)         # hoja cerrada
        rect(b, -hoja - 0.0125, 0.015, -0.0125, 0.055, 'A-CARPINTERIA-OCULTA')  # hoja abierta
        pl(b, [(-hoja - 0.06, 0.085), (A + 0.06, 0.085)], 'A-CARPINTERIA-OCULTA')  # guia
        arrow(b, A * 0.7, A * 0.2, 0.13)
        names.append((n, hoja, A, 'vista'))
        # ---- corredera empotrada (casoneto dentro del tabique)
        n = f'PUERTA_CORREDERA_EMPOTRADA_{tag}'
        L = hoja + 0.05                                    # longitud del cajon
        b = doc.blocks.new(n, dxfattribs={'description':
            f'Puerta corredera empotrada (casoneto), hoja {hoja:.3f} m, hueco {A:.3f} m. '
            f'Tabique minimo {T:.2f} m y {L:.2f} m libres de muros transversales a la izquierda.'})
        b.block_record.dxf.units = iu
        pl(b, [(A, 0), (A, -T)])                           # jamba de cierre
        pl(b, [(-L, 0), (-L, -T)])                         # fondo del cajon
        for y in (-0.03, -0.07):                           # caras del cajon
            pl(b, [(-L, y), (0, y)])
        pl(b, [(0, 0), (0, -0.03)]); pl(b, [(0, -0.07), (0, -T)])
        rect(b, -hoja + 0.03, -0.065, 0.03, -0.035, 'A-CARPINTERIA-OCULTA')  # hoja recogida
        pl(b, [(0.03, -0.05), (A, -0.05)], 'A-CARPINTERIA-OCULTA')           # recorrido
        arrow(b, A * 0.7, A * 0.2, 0.06)
        names.append((n, hoja, A, 'empotrada'))

    # lamina con todos los bloques
    msp = doc.modelspace()
    for i, (n, hoja, A, tipo) in enumerate(names):
        x = (i // 2) * 2.4 + 1.0
        y = -(i % 2) * 0.9
        msp.add_blockref(n, P(x, y))
        for k, t in enumerate((n, f'hoja {hoja:.3f} m / hueco {A:.3f} m')):
            msp.add_text(t, height=0.06 * f, dxfattribs={'layer': 'A-TEXTO'}).set_placement(
                P(x - 0.9, y - 0.25 - 0.09 * k), align=TextEntityAlignment.LEFT)
    path = os.path.join(HERE, f'Puertas_correderas_{units}.dxf')
    doc.saveas(path)
    return path, doc


if __name__ == '__main__':
    import matplotlib; matplotlib.use('Agg')
    from ezdxf.addons.drawing import matplotlib as mpl
    for u in ('m', 'cm', 'mm'):
        p, d = build(u)
        print('escrito', p, 'errores', len(d.audit().errors))
        if u == 'm':
            mpl.qsave(d.modelspace(), os.path.join(HERE, 'Puertas_correderas_vista_previa.png'),
                      bg='#212830', dpi=200)
