#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
PLANTA BAJA - PROPUESTA OPTIMIZADA

Redibujo de la planta baja (a partir de una captura, escala estimada con el
mobiliario: ~2,2 cm/px) con una redistribucion optimizada. Genera el DXF en
mm, cm y m, y una vista previa PNG.

Toda la geometria se define en CENTIMETROS con origen en la esquina exterior
inferior izquierda (x hacia la derecha, y hacia arriba = fachada trasera).

Uso:  python3 generar_planta_optimizada.py   (requiere ezdxf, shapely, matplotlib)
"""
import math
import os
import sys

from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import unary_union

import ezdxf
from ezdxf.enums import TextEntityAlignment

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'BloquesPlantas'))
import generar_plantas as GP  # noqa: E402  (bloques de plantas en planta)

# unidad: (factor desde cm, $INSUNITS, decimales de cota)
UNITS = {'mm': (10.0, 4, 0), 'cm': (1.0, 5, 0), 'm': (0.01, 6, 2)}

LAYERS = {  # nombre: (color ACI, grosor 1/100 mm, tipo de linea)
    'A-MURO-BLOQUE': (2, 35, None),
    'A-MURO-TRASDOSADO': (8, 18, None),
    'A-TABIQUE': (2, 25, None),
    'A-POCHE': (252, 0, None),
    'A-CARPINTERIA': (4, 18, None),
    'A-ESCALERA': (7, 18, None),
    'A-ESCALERA-OCULTA': (8, 13, 'OCULTA'),
    'A-MOBILIARIO': (40, 13, None),
    'A-COCINA': (40, 13, None),
    'A-SANITARIOS': (22, 13, None),
    'A-SANEAMIENTO': (211, 25, 'OCULTA'),
    'A-COTAS': (3, 13, None),
    'A-TEXTO': (7, 18, None),
    'A-MEJORAS': (1, 25, None),
}

# ------------------------------------------------------------------ datos
H_OUT_X, G_OUT_X, OUT_Y = 1370, 1790, 580      # vivienda | garaje | fondo
BLQ, TRS = 20, 10                              # bloque, trasdosado (cm)
IN_X0, IN_X1, IN_Y0, IN_Y1 = 30, 1340, 30, 550   # interior vivienda

# huecos en muros exteriores: (muro, desde, hasta)
OPENINGS = [
    ('S', 480, 570),     # puerta principal (90)
    ('S', 850, 930),     # ventana cocina (80)
    ('N', 300, 480),     # ventana salon (180)
    ('N', 860, 940),     # puerta trasera / jardin (80)
    ('E', 80, 162),      # puerta vivienda-garaje (82,5) en muro medianero
    ('GS', 1390, 1750),  # porton garaje
]


class Drawing:
    def __init__(self, units):
        self.f, self.insunits, self.dec = UNITS[units]
        self.units = units
        doc = ezdxf.new('R2010')
        doc.header['$INSUNITS'] = self.insunits
        doc.header['$MEASUREMENT'] = 1
        doc.header['$LUNITS'] = 2
        f = self.f
        doc.linetypes.add('OCULTA', pattern=[15 * f, 10 * f, -5 * f],
                          description='Oculta __ __ __')
        for name, (aci, lw, lt) in LAYERS.items():
            lay = doc.layers.add(name, color=aci)
            if lw:
                lay.dxf.lineweight = lw
            if lt:
                lay.dxf.linetype = lt
        for name, (rgb, lw) in GP.LAYERS.items():
            if name == 'VEG-TEXTO':
                continue
            lay = doc.layers.add(name)
            lay.color = GP.nearest_aci(rgb)
            lay.rgb = rgb
            if lw:
                lay.dxf.lineweight = lw
        doc.styles.add('A-TEXTO', font='arial.ttf')
        ds = doc.dimstyles.new('COTAS')
        ds.dxf.dimtxt = 11 * f
        ds.dxf.dimasz = 6 * f
        ds.dxf.dimexe = 5 * f
        ds.dxf.dimexo = 4 * f
        ds.dxf.dimgap = 3 * f
        ds.dxf.dimdec = self.dec
        ds.dxf.dimtad = 1
        ds.dxf.dimtxsty = 'A-TEXTO'
        ds.dxf.dimdsep = ord(',')
        ds.dxf.dimclrd = 3
        ds.dxf.dimclre = 3
        ds.dxf.dimclrt = 7
        ds.set_arrows(blk=ezdxf.ARROWS.architectural_tick)
        self.doc = doc
        self.msp = doc.modelspace()

    # ---- primitivas (coordenadas en cm)
    def P(self, x, y):
        return (round(x * self.f, 4), round(y * self.f, 4))

    def pl(self, pts, layer, closed=False, **attrs):
        self.msp.add_lwpolyline([self.P(*p) for p in pts], close=closed,
                                dxfattribs=dict(layer=layer, **attrs))

    def rect(self, x0, y0, x1, y1, layer, **attrs):
        self.pl([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], layer, True, **attrs)

    def line(self, p0, p1, layer, **attrs):
        self.msp.add_line(self.P(*p0), self.P(*p1), dxfattribs=dict(layer=layer, **attrs))

    def circle(self, c, r, layer, **attrs):
        self.msp.add_circle(self.P(*c), r * self.f, dxfattribs=dict(layer=layer, **attrs))

    def arc(self, c, r, a0, a1, layer, **attrs):
        self.msp.add_arc(self.P(*c), r * self.f, a0, a1, dxfattribs=dict(layer=layer, **attrs))

    def ellipse(self, c, rx, ry, layer):
        major = (rx * self.f, 0) if rx >= ry else (0, ry * self.f)
        self.msp.add_ellipse(self.P(*c), major_axis=major,
                             ratio=min(rx, ry) / max(rx, ry), dxfattribs={'layer': layer})

    def text(self, s, p, h, layer='A-TEXTO', align=TextEntityAlignment.MIDDLE_CENTER,
             rot=0.0):
        t = self.msp.add_text(s, height=h * self.f,
                              dxfattribs={'layer': layer, 'style': 'A-TEXTO',
                                          'rotation': rot})
        t.set_placement(self.P(*p), align=align)

    def geom(self, g, layer, **attrs):
        """Dibuja el contorno de una geometria shapely."""
        polys = [g] if g.geom_type == 'Polygon' else list(getattr(g, 'geoms', []))
        for p in polys:
            if p.geom_type != 'Polygon':
                continue
            self.pl(list(p.exterior.coords)[:-1], layer, True, **attrs)
            for r in p.interiors:
                self.pl(list(r.coords)[:-1], layer, True, **attrs)

    def poche(self, g, layer='A-POCHE'):
        polys = [g] if g.geom_type == 'Polygon' else list(getattr(g, 'geoms', []))
        h = self.msp.add_hatch(color=256, dxfattribs={'layer': layer})
        for p in polys:
            if p.geom_type != 'Polygon':
                continue
            h.paths.add_polyline_path([self.P(*c) for c in list(p.exterior.coords)[:-1]],
                                      is_closed=True, flags=1)
            for r in p.interiors:
                h.paths.add_polyline_path([self.P(*c) for c in list(r.coords)[:-1]],
                                          is_closed=True, flags=0)

    def dim(self, p1, p2, base, angle=0):
        d = self.msp.add_linear_dim(base=self.P(*base), p1=self.P(*p1), p2=self.P(*p2),
                                    angle=angle, dimstyle='COTAS',
                                    dxfattribs={'layer': 'A-COTAS'})
        d.render()

    def chain(self, xs, y_meas, y_line, vertical=False):
        for a, b in zip(xs[:-1], xs[1:]):
            if vertical:
                self.dim((y_meas, a), (y_meas, b), (y_line, a), angle=90)
            else:
                self.dim((a, y_meas), (b, y_meas), (a, y_line))

    def mark(self, n, p):
        self.circle(p, 16, 'A-MEJORAS')
        self.text(str(n), p, 16, 'A-MEJORAS')

    def plant(self, key, p, rot=0.0):
        name = f'VEG_{key}_PLANTA'
        if name not in self.doc.blocks:
            fn = {'Kentia': GP.kentia, 'Monstera': GP.monstera,
                  'Sansevieria': GP.sansevieria, 'Pilea': GP.pilea,
                  'Ficus_lyrata': GP.ficus}[key]
            blk = self.doc.blocks.new(name=name)
            blk.block_record.dxf.units = self.insunits
            GP.emit(blk, fn()['plan'], 0.1 * self.f)   # plantas en mm -> cm * f
        self.msp.add_blockref(name, self.P(*p), dxfattribs={'rotation': rot})


# ------------------------------------------------------------ muros
def build_walls(d):
    house_out = box(0, 0, H_OUT_X, OUT_Y)
    house_blq_in = box(BLQ, BLQ, H_OUT_X - BLQ, OUT_Y - BLQ)
    garage = box(H_OUT_X, 0, G_OUT_X, OUT_Y)
    garage_in = box(H_OUT_X, -10, G_OUT_X - BLQ, OUT_Y - BLQ)
    bloque = unary_union([house_out.difference(house_blq_in), garage.difference(garage_in)])
    trasdosado = house_blq_in.difference(box(IN_X0, IN_Y0, IN_X1, IN_Y1))

    cuts = []
    for wall, a, b in OPENINGS:
        if wall == 'S':
            cuts.append(box(a, -5, b, IN_Y0 + 1))
        elif wall == 'N':
            cuts.append(box(a, IN_Y1 - 1, b, OUT_Y + 5))
        elif wall == 'E':
            cuts.append(box(IN_X1 - 1, a, H_OUT_X + 1, b))
        elif wall == 'GS':
            cuts.append(box(a, -5, b, BLQ + 1))
    cut = unary_union(cuts)
    bloque = bloque.difference(cut)
    trasdosado = trasdosado.difference(cut)

    # tabiques interiores (10 cm)
    tab = unary_union([
        box(950, 450, 960, 550),          # escalera: muro oeste (con puerta)
        box(950, 440, 1240, 450),         # escalera: muro sur
        box(1230, 190, 1240, 450),        # entre columnas de cocina y aseo
        box(1240, 380, 1340, 390),        # aseo: muro norte (hueco bajo escalera)
        box(1170, 180, 1340, 190),        # aseo: muro sur (con corredera empotrada)
        box(1370, 415, 1770, 425),        # lavadero: muro sur
    ]).difference(unary_union([
        box(949, 460, 961, 540),          # puerta escalera
        box(1260, 179, 1333, 191),        # corredera aseo
        box(1390, 414, 1470, 426),        # puerta lavadero
    ]))
    d.poche(bloque)
    d.poche(tab, 'A-POCHE')
    d.geom(bloque, 'A-MURO-BLOQUE')
    d.geom(trasdosado, 'A-MURO-TRASDOSADO')
    d.geom(tab, 'A-TABIQUE')


# ------------------------------------------------------- carpinteria
def door(d, hinge, width, closed_dir, open_dir, layer='A-CARPINTERIA'):
    """Puerta abatible: bisagra, ancho, direccion (grados) de la hoja cerrada
    y de la hoja abierta (90 grados de giro)."""
    hx, hy = hinge
    ox, oy = hx + width * math.cos(math.radians(open_dir)), hy + width * math.sin(math.radians(open_dir))
    nx, ny = -math.sin(math.radians(open_dir)) * 2, math.cos(math.radians(open_dir)) * 2
    d.pl([(hx + nx, hy + ny), (ox + nx, oy + ny), (ox - nx, oy - ny), (hx - nx, hy - ny)],
         layer, True)
    a0, a1 = sorted([closed_dir % 360, open_dir % 360])
    if a1 - a0 > 180:
        a0, a1 = a1, a0 + 360
    d.arc(hinge, width, a0, a1, layer)


def window(d, wall, a, b):
    if wall == 'S':
        y0, y1 = 0, IN_Y0
        for y in (12, 18):
            d.line((a, y), (b, y), 'A-CARPINTERIA')
        d.line((a - 5, -3), (b + 5, -3), 'A-CARPINTERIA')
    else:
        for y in (OUT_Y - 18, OUT_Y - 12):
            d.line((a, y), (b, y), 'A-CARPINTERIA')
        d.line((a - 5, OUT_Y + 3), (b + 5, OUT_Y + 3), 'A-CARPINTERIA')


def build_openings(d):
    door(d, (480, IN_Y0), 90, 0, 90)                 # principal: abre hacia dentro
    window(d, 'S', 850, 930)
    window(d, 'N', 300, 480)
    door(d, (940, IN_Y1), 80, 180, 270)              # trasera: abre hacia dentro
    door(d, (960, 540), 80, 270, 0)                  # escalera
    door(d, (H_OUT_X, 80), 82, 90, 0)                # garaje: abre hacia el garaje
    door(d, (1390, 425), 80, 0, 90)                  # lavadero
    # corredera empotrada del aseo (hoja abierta dentro del tabique)
    d.rect(1187, 183, 1262, 187, 'A-CARPINTERIA', linetype='OCULTA')
    d.line((1262, 185), (1333, 185), 'A-CARPINTERIA', linetype='OCULTA')
    # porton seccional del garaje
    d.rect(1390, 8, 1750, 12, 'A-CARPINTERIA')
    d.text('PUERTA SECCIONAL', (1570, -14), 9)


# ------------------------------------------------------------ escalera
def build_stair(d):
    L = 'A-ESCALERA'
    xs = [1110 + 26 * i for i in range(6)]           # tramo recto: 5 huellas de 26
    for x in xs:
        d.line((x, 450), (x, IN_Y1), L)
    c = (1240, 450)                                   # compensados desde el rincon interior
    for p in ((1281, IN_Y1), (IN_X1, IN_Y1), (IN_X1, 491)):
        d.line(c, p, L)
    d.line((1240, 450), (IN_X1, 450), L)
    for y in (424, 398):                              # tramo hacia abajo (hasta el corte)
        d.line((1240, y), (IN_X1, y), L)
    for y in (372, 346, 320, 294, 268):               # resto de tramo, por encima del aseo
        d.line((1240, y), (IN_X1, y), 'A-ESCALERA-OCULTA')
    d.line((1240, 390), (1240, 268), 'A-ESCALERA-OCULTA')
    # linea de corte
    d.pl([(1232, 402), (1282, 414), (1286, 424), (1294, 404), (1298, 414), (1348, 426)], L)
    # linea de huella y flecha
    d.circle((1123, 500), 5, L)
    d.pl([(1128, 500), (1290, 500), (1290, 410)], L)
    d.pl([(1282, 424), (1290, 410), (1298, 424)], L)
    d.text('SUBE', (1175, 485), 10, L)


# ---------------------------------------------------------- mobiliario
def chair(d, cx, cy, facing):
    """Silla 45x45 con respaldo; facing = direccion hacia la que mira (grados)."""
    import shapely.affinity as aff
    seat = box(-22, -22, 22, 22)
    back = box(-22, -26, 22, -19)
    for g in (seat, back):
        g = aff.translate(aff.rotate(g, facing - 90, origin=(0, 0)), cx, cy)
        d.geom(g, 'A-MOBILIARIO')


def build_living(d):
    M = 'A-MOBILIARIO'
    # chimenea (esquina NO)
    d.pl([(IN_X0, IN_Y1), (155, IN_Y1), (155, 515), (95, 425), (IN_X0, 425)], 'A-ESCALERA', True)
    d.text('CHIMENEA', (82, 480), 10)
    # mueble TV
    d.rect(IN_X0, 175, 75, 355, M)
    d.rect(70, 200, 76, 330, M)
    d.text('TV', (52, 265), 10, rot=90)
    # alfombra
    d.rect(120, 110, 400, 385, M, linetype='OCULTA')
    # sofa en L (rinconera): tramo principal mirando a la TV + chaise
    sofa = unary_union([box(340, 60, 430, 340), box(180, 60, 340, 150)])
    d.geom(sofa, M)
    d.pl([(410, 340), (410, 80), (180, 80)], M)                      # respaldos
    d.pl([(340, 320), (410, 320)], M)                                # brazo norte
    d.pl([(200, 80), (200, 150)], M)                                 # brazo oeste
    for y in (140, 230):
        d.line((340, y), (410, y), M)                                # cojines
    d.line((260, 80), (260, 150), M)
    # mesa de centro
    d.rect(225, 170, 285, 290, M)
    # butaca hacia chimenea / TV
    import shapely.affinity as aff
    b = box(-40, -40, 40, 40)
    back = box(-40, 24, 40, 40)
    arms = [box(-40, -40, -28, 24), box(28, -40, 40, 24)]
    for g in [b, back] + arms:
        d.geom(aff.translate(aff.rotate(g, 35, origin=(0, 0)), 245, 455), M)
    # consola que separa recibidor y salon
    d.rect(435, 90, 465, 270, M)
    d.text('CONSOLA', (450, 180), 8, rot=90)
    # armario recibidor 140x60
    d.rect(580, IN_Y0, 720, 90, M)
    d.line((650, IN_Y0), (650, 90), M)
    d.line((585, 60), (715, 60), M, linetype='OCULTA')
    d.text('ARMARIO', (650, 48), 8)
    # comedor 8 plazas: mesa 240x100 sin cabeceras
    d.rect(580, 330, 820, 430, M)
    for x in (610, 670, 730, 790):
        chair(d, x, 462, 270)   # mira al sur
        chair(d, x, 298, 90)    # mira al norte
    # plantas (bloques de la biblioteca)
    d.plant('Kentia', (100, 100))
    d.plant('Monstera', (445, 492))
    d.plant('Sansevieria', (450, 295))
    d.plant('Pilea', (700, 380))


def build_kitchen(d):
    K = 'A-COCINA'
    # encimera sur
    d.rect(720, IN_Y0, 1170, 90, K)
    for x in (780, 840, 940, 1000, 1040, 1130):
        d.line((x, IN_Y0), (x, 90), K, linetype='OCULTA')
    d.text('VINOTECA', (750, 60), 7, rot=90)
    # fregadero bajo ventana
    d.rect(846, 36, 934, 84, K)
    d.rect(852, 42, 896, 78, K)
    for y in (48, 56, 64, 72):
        d.line((902, y), (928, y), K)
    d.circle((874, 81), 2.5, K)
    d.text('LV', (970, 60), 9)
    # placa 90
    d.rect(1042, 37, 1128, 85, K)
    for c, r in (((1062, 50), 8), ((1062, 72), 8), ((1085, 61), 11), ((1110, 50), 8), ((1110, 72), 8)):
        d.circle(c, r, K)
    # isla con barra hacia el comedor
    d.rect(880, 190, 1080, 280, K)
    d.line((880, 250), (1080, 250), K, linetype='OCULTA')
    for x in (920, 980, 1040):
        d.circle((x, 302), 19, 'A-MOBILIARIO')
    d.text('ISLA', (980, 220), 10)
    # columnas: frigo, horno+micro, despensa, escobero
    d.rect(1170, 190, 1230, 440, K)
    for y in (260, 320, 380):
        d.line((1170, y), (1230, y), K)
    for (y0, y1, t) in ((190, 260, 'FRIGO'), (260, 320, 'HORNO'),
                        (320, 380, 'DESPENSA'), (380, 440, 'ESCOBERO')):
        d.line((1170, y0), (1230, y1), K, linetype='OCULTA')
        d.text(t, (1200, (y0 + y1) / 2), 7, rot=90)


def build_services(d):
    S = 'A-SANITARIOS'
    # aseo: inodoro al fondo y lavabo junto a la puerta
    d.rect(1272, 362, 1310, 380, S)
    d.ellipse((1291, 335), 18, 26, S)
    d.rect(1295, 215, IN_X1, 275, S)
    d.ellipse((1318, 245), 15, 20, S)
    # vestibulo: banco zapatero + patinillo bajante
    d.rect(1180, IN_Y0, 1295, 70, 'A-MOBILIARIO')
    d.text('BANCO', (1237, 50), 8)
    d.rect(1305, IN_Y0, IN_X1, 65, 'A-SANEAMIENTO', linetype='CONTINUOUS')
    d.circle((1322, 47), 6, 'A-SANEAMIENTO', linetype='CONTINUOUS')
    d.rect(IN_X0, IN_Y0, 65, 65, 'A-SANEAMIENTO', linetype='CONTINUOUS')
    d.circle((47, 47), 6, 'A-SANEAMIENTO', linetype='CONTINUOUS')
    # lavadero
    d.rect(1490, 490, 1560, 560, 'A-COCINA')
    d.circle((1525, 525), 28, 'A-COCINA')
    d.text('AEROTERMIA', (1525, 478), 7)
    d.rect(1570, 495, 1635, 560, 'A-COCINA')
    d.circle((1602, 527), 24, 'A-COCINA')
    d.text('LAV+SEC', (1602, 483), 7)
    d.rect(1645, 500, 1770, 560, 'A-COCINA')
    d.rect(1700, 507, 1760, 553, 'A-COCINA')
    d.text('PILA', (1672, 530), 8)
    # saneamiento (esquema)
    SN = 'A-SANEAMIENTO'
    d.pl([(1291, 372), (1395, 372), (1395, -60)], SN)                 # inodoro/lavabo
    d.pl([(1318, 250), (1395, 250)], SN)
    d.pl([(874, 45), (1322, 45)], SN)                                 # fregadero
    d.pl([(1322, 45), (1322, -40), (1375, -60)], SN)
    d.pl([(1740, 530), (1755, 530), (1755, 30), (1640, -55), (1415, -60)], SN)
    d.rect(1375, -80, 1415, -40, SN, linetype='CONTINUOUS')
    d.line((1375, -80), (1415, -40), SN, linetype='CONTINUOUS')
    d.line((1375, -40), (1415, -80), SN, linetype='CONTINUOUS')
    d.text('ARQUETA', (1395, -95), 8, SN)


# ----------------------------------------------------- textos y cotas
ROOMS = {  # nombre: (poligono en cm, punto de etiqueta, altura, mostrar superficie)
    'SALÓN': (None, (215, 395), 14, False),
    'COMEDOR': (None, (700, 520), 14, False),
    'COCINA': (None, (980, 130), 14, False),
    'RECIBIDOR': (None, (525, 250), 12, False),
    'ESCALERA': (box(960, 450, 1110, 550), (1050, 482), 10, True),
    'ASEO': (box(1240, 190, IN_X1, 380), (1270, 300), 10, True),
    'VESTÍBULO': (box(1170, IN_Y0, IN_X1, 180), (1262, 150), 11, True),
    'LAVADERO': (box(1370, 425, 1770, 560), (1440, 540), 14, True),
    'GARAJE / ALMACÉN': (box(1370, 10, 1770, 415), (1570, 250), 14, True),
}


def area_txt(a_cm2):
    return f"{a_cm2 / 1e4:.2f}".replace('.', ',') + ' m²'


def build_texts(d):
    open_plan = box(IN_X0, IN_Y0, IN_X1, IN_Y1).difference(unary_union([
        box(950, 440, IN_X1, IN_Y1), box(1230, 180, IN_X1, 450), box(1170, 180, 1240, 190),
        box(1170, IN_Y0, IN_X1, 180)]))
    for name, (poly, p, h, show) in ROOMS.items():
        d.text(name, p, h)
        if show:
            d.text(area_txt(poly.area), (p[0], p[1] - h - 4), 8)
    d.text('SALÓN-COMEDOR-COCINA: ' + area_txt(open_plan.area), (700, 235), 9)
    # cotas exteriores
    d.chain([0, 480, 570, 850, 930, H_OUT_X, G_OUT_X], 0, -140)
    d.chain([0, H_OUT_X, G_OUT_X], 0, -185)
    d.chain([0, 300, 480, 860, 940, H_OUT_X], OUT_Y, OUT_Y + 60)
    d.chain([0, OUT_Y], 0, -60, vertical=True)
    d.chain([0, 415, 425, OUT_Y], G_OUT_X, G_OUT_X + 60, vertical=True)


NOTES = [
    '1  Entrada: puerta abriendo hacia dentro, recibidor con armario 140x60 y consola que separa el salón.',
    '2  Salón: sofá en L orientado a la TV (2,6 m) y butaca hacia la chimenea; paso libre de 1,3 m desde la entrada.',
    '3  Comedor 8 plazas (240x100) separado 60 cm del muro trasero: antes las sillas quedaban pegadas a la pared.',
    '4  Cocina en L + isla: fregadero bajo ventana, placa y columnas; pasillos de 90-100 cm; barra de 3 taburetes hacia el comedor.',
    '5  Vinoteca bajo encimera en el extremo de la cocina más cercano al comedor.',
    '6  Columnas de frigorífico, horno+micro, despensa y escobero en lugar de la despensa con puertas plegables.',
    '7  Vestíbulo de servicio con banco: la puerta del garaje ya no choca con la encimera ni con la bajante (recomendado EI2 45-C5).',
    '8  Aseo con puerta corredera empotrada al vestíbulo (en el plano original no tenía acceso).',
    '9  Lavadero: lavadora+secadora en columna, pila con encimera y espacio de mantenimiento para la aerotermia.',
]


def build_notes(d):
    marks = {1: (525, 60), 2: (300, 345), 3: (525, 380), 4: (1000, 350), 5: (750, 110),
             6: (1150, 420), 7: (1200, 105), 8: (1297, 205), 9: (1690, 470)}
    for n, p in marks.items():
        d.mark(n, p)
    y = -300
    d.text('PLANTA BAJA - PROPUESTA OPTIMIZADA', (0, y), 30, align=TextEntityAlignment.LEFT)
    d.text('Redibujada a partir de una captura: cotas aproximadas (escala estimada con el mobiliario). '
           'Ajustar con las medidas reales antes de usar.', (0, y - 45), 12,
           align=TextEntityAlignment.LEFT)
    for i, n in enumerate(NOTES):
        d.text(n, (0, y - 90 - i * 26), 12, align=TextEntityAlignment.LEFT)
    d.text('Escalera existente sin cambios: comprobar número de peldaños y altura libre del aseo bajo el tramo superior.',
           (0, y - 90 - len(NOTES) * 26 - 10), 12, align=TextEntityAlignment.LEFT)
    d.text('Garaje: fondo útil aprox. 4,0 m (solo coche pequeño); comprobar con medidas reales.',
           (0, y - 90 - len(NOTES) * 26 - 36), 12, align=TextEntityAlignment.LEFT)


def build(units):
    d = Drawing(units)
    build_walls(d)
    build_openings(d)
    build_stair(d)
    build_living(d)
    build_kitchen(d)
    build_services(d)
    build_texts(d)
    build_notes(d)
    f = d.f
    d.doc.set_modelspace_vport(height=1100 * f, center=(900 * f, 50 * f))
    path = os.path.join(HERE, f'PB_propuesta_optimizada_{units}.dxf')
    d.doc.saveas(path)
    return path, d.doc


def preview(doc, path, width_px=3600):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from ezdxf import bbox
    from ezdxf.addons.drawing import Frontend, RenderContext
    from ezdxf.addons.drawing.config import BackgroundPolicy, Configuration
    from ezdxf.addons.drawing.matplotlib import MatplotlibBackend
    ext = bbox.extents(doc.modelspace(), fast=True)
    w, h = ext.size.x, ext.size.y
    fig = plt.figure()
    ax = fig.add_axes([0.01, 0.01, 0.98, 0.98])
    cfg = Configuration(background_policy=BackgroundPolicy.CUSTOM,
                        custom_bg_color='#212830', lineweight_scaling=0.5)
    Frontend(RenderContext(doc), MatplotlibBackend(ax), config=cfg).draw_layout(
        doc.modelspace(), finalize=True)
    fig.set_size_inches(18, 18 * h / w)
    fig.savefig(path, dpi=width_px / 18, facecolor='#212830')
    plt.close(fig)


if __name__ == '__main__':
    doc_cm = None
    for u in ('cm', 'm', 'mm'):
        p, doc = build(u)
        print('escrito', p)
        if u == 'cm':
            doc_cm = doc
    preview(doc_cm, os.path.join(HERE, 'PB_propuesta_optimizada_vista_previa.png'))
    print('vista previa generada')
