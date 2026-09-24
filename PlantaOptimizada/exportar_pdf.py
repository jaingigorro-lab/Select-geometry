#!/usr/bin/env python3
"""Exporta la planta optimizada a PDF A3 a escala 1:50 (fondo blanco) para
dibujar encima en el iPad. Genera una version en color y otra en grises claros
(base de calco)."""
import os
import ezdxf
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from ezdxf import bbox
from ezdxf.addons.drawing import Frontend, RenderContext
from ezdxf.addons.drawing.config import BackgroundPolicy, ColorPolicy, Configuration
from ezdxf.addons.drawing.matplotlib import MatplotlibBackend

HERE = os.path.dirname(os.path.abspath(__file__))
A3 = (420.0, 297.0)          # mm
ESCALA = 50                  # 1:50
DOC = os.path.join(HERE, 'PB_propuesta_optimizada_cm.dxf')   # unidades: cm


def exportar(color_policy, nombre, sufijo):
    doc = ezdxf.readfile(DOC)
    msp = doc.modelspace()
    ext = bbox.extents(msp, fast=True)
    cx, cy = (ext.extmin.x + ext.extmax.x) / 2, (ext.extmin.y + ext.extmax.y) / 2
    w_cm, h_cm = A3[0] * ESCALA / 10, A3[1] * ESCALA / 10          # papel -> cm reales
    fig = plt.figure(figsize=(A3[0] / 25.4, A3[1] / 25.4))
    ax = fig.add_axes([0, 0, 1, 1])
    cfg = Configuration(background_policy=BackgroundPolicy.WHITE,
                        color_policy=color_policy, lineweight_scaling=1.0)
    Frontend(RenderContext(doc), MatplotlibBackend(ax), config=cfg).draw_layout(msp, finalize=True)
    ax.set_autoscale_on(False)
    ax.set_aspect('auto')   # el papel ya tiene la misma proporcion: escala exacta
    ax.set_xlim(cx - w_cm / 2, cx + w_cm / 2)
    ax.set_ylim(cy - h_cm / 2 - 20, cy + h_cm / 2 - 20)
    # escala grafica 0-5 m y rotulo
    x0, y0 = ext.extmin.x + 1150, ext.extmin.y + 60
    for i in range(5):
        ax.add_patch(plt.Rectangle((x0 + i * 100, y0), 100, 12,
                                   facecolor='black' if i % 2 == 0 else 'white',
                                   edgecolor='black', lw=0.4))
        ax.text(x0 + i * 100, y0 + 22, f'{i}', ha='center', fontsize=6)
    ax.text(x0 + 500, y0 + 22, '5 m', ha='center', fontsize=6)
    ax.text(x0, y0 - 30, f'ESCALA 1:{ESCALA} en A3  -  {sufijo}', fontsize=7)
    fig.set_size_inches(A3[0] / 25.4, A3[1] / 25.4)   # el render cambia el tamano: fijar A3
    ax.set_position([0, 0, 1, 1])
    fig.savefig(os.path.join(HERE, nombre), format='pdf', facecolor='white')
    plt.close(fig)
    print('escrito', nombre, 'extents cm', round(ext.size.x), 'x', round(ext.size.y))


if __name__ == '__main__':
    exportar(ColorPolicy.COLOR, 'PB_propuesta_optimizada_A3_1-50_color.pdf', 'color')
    exportar(ColorPolicy.MONOCHROME_LIGHT_BG, 'PB_propuesta_optimizada_A3_1-50_calco.pdf',
             'base de calco en grises')
