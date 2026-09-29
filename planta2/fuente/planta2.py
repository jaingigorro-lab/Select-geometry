#!/usr/bin/env python3
"""Planta segunda: SALA DE ESTAR en el cuarto inferior central y ZONA DE JUEGO
Y LECTURA junto a la escalera.

Genera los bloques CAD detallados y la distribucion en DXF (en cm y en m) y las
imagenes de la propuesta. Todas las medidas salen de las cotas del plano
(4,03 / 2,67 / 2,47 / 3,23 / 1,01 / 1,71) medidas sobre la captura
(75,43 px/m).

Coordenadas del diseno en cm: origen en la esquina interior inferior izquierda
de la sala (cara interior del tabique izquierdo y del muro inferior fino), X
hacia la derecha e Y hacia arriba. En el DXF el origen (0,0) se lleva a la
ESQUINA INTERIOR SUPERIOR IZQUIERDA DE LA SALA (encuentro del tabique izquierdo
con el tabique del pasillo), que es el punto base para copiar y pegar.
"""
import math
import os
import sys

import ezdxf
from ezdxf import units
from shapely.geometry import LineString, MultiLineString, Point, Polygon
from shapely.ops import unary_union

HERE = os.path.dirname(os.path.abspath(__file__))
SALIDA = os.path.dirname(HERE)              # carpeta planta2/ (junto a fuente/)
B90 = math.tan(math.pi / 8)

# ---------------------------------------------------------------- medidas del plano (cm)
K = 100.0 / 75.43                      # cm por pixel de la captura
PX0, PY0 = 516.5, 441.5                # pixel del origen del diseno


def px2cm(px, py):
    return ((px - PX0) * K, (PY0 - py) * K)


SALA_W, SALA_H = 403.0, 266.5          # sala (interior)
PILAR_X, PILAR_Y = 172.6, 19.9         # zona del pilar (muro grueso) abajo a la izquierda
PUERTA_X0, PUERTA_X1 = 126.6, 214.8    # hueco de paso de la sala (tabique superior)
PASILLO_Y0, PASILLO_Y1 = 273.1, 373.9  # pasillo de 1,01
BANO_X = 252.5                         # cara del tabique del bano hacia la zona de juego
TECHO_Y = 539.6                        # cara interior del muro superior (medianera)
BARANDA_X = 574.0                      # cara de la barandilla de la escalera (arriba)
REF_BASE = (0.0, SALA_H)               # punto base del DXF


# ---------------------------------------------------------------- geometria
def rr4(x0, y0, x1, y1, r1, r2, r3, r4):
    """Rectangulo antihorario con esquinas redondeadas (x y bulge)."""
    out = []
    out += [(x0, y0 + r1, B90), (x0 + r1, y0, 0.0)] if r1 > 0 else [(x0, y0, 0.0)]
    out += [(x1 - r2, y0, B90), (x1, y0 + r2, 0.0)] if r2 > 0 else [(x1, y0, 0.0)]
    out += [(x1, y1 - r3, B90), (x1 - r3, y1, 0.0)] if r3 > 0 else [(x1, y1, 0.0)]
    out += [(x0 + r4, y1, B90), (x0, y1 - r4, 0.0)] if r4 > 0 else [(x0, y1, 0.0)]
    return out


def rr(x0, y0, x1, y1, r):
    return rr4(x0, y0, x1, y1, r, r, r, r)


def rect(x0, y0, x1, y1):
    return rr(x0, y0, x1, y1, 0)


def xf(pts, cx, cy, a):
    c, s = math.cos(a), math.sin(a)
    return [(cx + c * p[0] - s * p[1], cy + s * p[0] + c * p[1]) + tuple(p[2:]) for p in pts]


def seg_arc(p, q, b, step=math.radians(8)):
    """Puntos (sin p) del tramo p->q con bulge b."""
    if abs(b) < 1e-12:
        return [q]
    th = 4 * math.atan(b)
    dx, dy = q[0] - p[0], q[1] - p[1]
    ch = math.hypot(dx, dy)
    d = (ch / 2) * (1 - b * b) / (2 * b)
    cx, cy = (p[0] + q[0]) / 2 - dy / ch * d, (p[1] + q[1]) / 2 + dx / ch * d
    r = math.hypot(p[0] - cx, p[1] - cy)
    a0 = math.atan2(p[1] - cy, p[0] - cx)
    n = max(2, int(math.ceil(abs(th) / step)))
    out = [(cx + r * math.cos(a0 + th * i / n), cy + r * math.sin(a0 + th * i / n)) for i in range(1, n)]
    return out + [q]


def tess(pts, closed):
    n = len(pts)
    out = [(pts[0][0], pts[0][1])]
    for i in range(n if closed else n - 1):
        p, q = pts[i], pts[(i + 1) % n]
        b = p[2] if len(p) > 2 else 0.0
        out += seg_arc((p[0], p[1]), (q[0], q[1]), b)
    return out


def circle_pts(cx, cy, r, n=64):
    return [(cx + r * math.cos(2 * math.pi * i / n), cy + r * math.sin(2 * math.pi * i / n)) for i in range(n)]


def dashes(pts, tr=4.0, hu=2.5):
    """Trazos (lista de pares de puntos) a lo largo de una linea quebrada."""
    out, s0, per = [], 0.0, tr + hu
    for a, b in zip(pts, pts[1:]):
        L = math.hypot(b[0] - a[0], b[1] - a[1])
        if L < 1e-9:
            continue
        k = int(s0 // per)
        while k * per < s0 + L:
            d0, d1 = max(s0, k * per), min(s0 + L, k * per + tr)
            if d1 > d0 + 1e-6:
                u0, u1 = (d0 - s0) / L, (d1 - s0) / L
                out.append(((a[0] + (b[0] - a[0]) * u0, a[1] + (b[1] - a[1]) * u0),
                            (a[0] + (b[0] - a[0]) * u1, a[1] + (b[1] - a[1]) * u1)))
            k += 1
        s0 += L
    return out


# ---------------------------------------------------------------- elementos
class It:
    """Elemento de un bloque. kind: pl (pts con bulge, closed), circle (cx cy r),
    line (p0 p1), dash (pts: se dibuja a trazos), text (x y h rot txt).
    style: main (capa de la insercion) / det (gris 8, 0,13 mm).
    z: orden de dibujo; cover: tapa (oculta) lo que tiene debajo."""

    def __init__(self, kind, geom, style="main", fill=None, z=0, cover=False, closed=True):
        self.kind, self.geom, self.style, self.fill, self.z, self.cover, self.closed = \
            kind, geom, style, fill, z, cover, closed

    def polygon(self):
        if self.kind == "pl" and self.closed:
            return Polygon(tess(self.geom, True))
        if self.kind == "circle":
            return Point(self.geom[0], self.geom[1]).buffer(self.geom[2], 64)
        return None

    def path(self):
        if self.kind == "pl":
            return tess(self.geom, self.closed)
        if self.kind == "circle":
            p = circle_pts(*self.geom)
            return p + [p[0]]
        if self.kind == "line":
            return list(self.geom)
        if self.kind == "dash":
            return tess(self.geom, False)
        return None


def PL(pts, **kw):
    return It("pl", pts, **kw)


def CI(cx, cy, r, **kw):
    return It("circle", (cx, cy, r), **kw)


def LN(p0, p1, **kw):
    return It("line", (p0, p1), **kw)


def DS(pts, **kw):
    kw.setdefault("style", "det")
    return It("dash", pts, **kw)


def cojin_pts(lp, gp, r=3.5):
    """Cojin suelto: rectangulo redondeado con los lados largos abombados."""
    hx, hy = lp / 2, gp / 2
    bl = 3.0 / (lp - 2 * r)
    return [(-hx + r, -hy, bl), (hx - r, -hy, B90), (hx, -hy + r, 0.0), (hx, hy - r, B90),
            (hx - r, hy, bl), (-hx + r, hy, B90), (-hx, hy - r, 0.0), (-hx, -hy + r, B90)]


def cojin(cx, cy, a, lp, gp, fill, z):
    hx, hy = lp / 2, gp / 2
    its = [PL(xf(cojin_pts(lp, gp), cx, cy, a), fill=fill, z=z, cover=True)]
    for s in [((hx - 1.2, hy - 1.2), (hx - 3.8, hy - 2.6)), ((hx - 1.2, -hy + 1.2), (hx - 3.8, -hy + 2.6)),
              ((-hx + 1.2, hy - 1.2), (-hx + 3.8, hy - 2.6)), ((-hx + 1.2, -hy + 1.2), (-hx + 3.8, -hy + 2.6)),
              ((-hx + 5, 0), (hx - 5, 0))]:
        its.append(PL(xf(list(s), cx, cy, a), style="det", z=z + 1, closed=False))
    return its


def hoja(b, p, bu=0.38, fill="#6f9a5b", z=3):
    return PL([(b[0], b[1], bu), (p[0], p[1], bu)], style="det", fill=fill, z=z)


# colores de la lamina (solo para las imagenes)
C = dict(tela="#b7c3c8", cojin="#cbd5d9", madera="#d4b384", madera_osc="#a57c52", mostaza="#e2a65a",
         salvia="#8fb3a5", salvia_cl="#b3cdbf", coral="#e07a5f", amarillo="#f2c14e", azul="#8ab6d6",
         alfombra="#ece2d2", alfombra_j="#dfe8d2", asfalto="#a9b1b7", blanco="#f7f3ea", tv="#2a2e33",
         luz="#f6d98a", gris="#7d8288", verde="#6f9a5b", terracota="#c96f4a", libros=["#b5654a", "#5f7d8c",
         "#c9a24a", "#7a8f5e", "#8c5f7a", "#d08a5a", "#4f6f8f", "#a4a39c"])


# ---------------------------------------------------------------- bloques
def blk_sofa():
    """Sofa de 3 plazas con chaise longue, 240 x 160. Origen en la esquina de
    atras de la chaise (pared derecha / muro inferior); el sofa queda hacia -X."""
    its = []
    out = [(0, 0, 0), (0, 240, 0), (-91, 240, B90), (-95, 236, 0), (-95, 95, 0), (-154, 95, B90),
           (-160, 89, 0), (-160, 4, B90), (-156, 0, 0)]
    its.append(PL(out, fill=C["tela"], z=0, cover=True))
    its.append(LN((-18, 0), (-18, 225), z=1))                        # estructura del respaldo
    its.append(LN((-95, 225), (-18, 225), z=1))                       # brazo
    for y0, y1 in ((1, 94), (96, 159.5), (160.5, 224)):               # cojines de respaldo
        its.append(PL(rr(-34, y0, -18.5, y1, 4), fill=C["cojin"], z=2, cover=True))
    for x0, y0, x1, y1, r in ((-159, 1, -34.5, 94, 5), (-94, 96, -34.5, 159.5, 4), (-94, 160.5, -34.5, 224, 4)):
        its.append(PL(rr(x0, y0, x1, y1, r), fill=C["cojin"], z=2, cover=True))
        its.append(PL(rr(x0 + 2, y0 + 2, x1 - 2, y1 - 2, r - 2), style="det", z=3))
    its += cojin(-44, 206, math.radians(72), 40, 14, C["mostaza"], 4)
    its += cojin(-44, 112, math.radians(104), 40, 14, C["salvia"], 4)
    return its


def blk_mueble_tv():
    """Mueble bajo volado de TV 200 x 40 con TV de 65" colgada, barra de sonido y
    objetos. Origen en la pared, extremo inferior; el mueble queda hacia +X."""
    its = [PL(rr4(0, 0, 40, 200, 0, 1.5, 1.5, 0), fill=C["madera"], z=0, cover=True),
           LN((38.5, 1), (38.5, 199), style="det", z=1)]
    for y in (50, 100, 150):
        its.append(LN((38.5, y), (40, y), style="det", z=1))
    its.append(PL(rect(1.5, 27.5, 7.5, 172.5), fill=C["tv"], z=2, cover=True))       # TV colgada
    its.append(PL(rect(0, 92, 1.5, 108), style="det", z=3))                         # soporte
    its.append(PL(rr(24, 57.5, 31, 142.5, 2), fill=C["tv"], z=2, cover=True))       # barra de sonido
    its.append(CI(20, 184, 7, style="det", fill=C["terracota"], z=2))              # planta
    for k in range(6):
        a = 0.3 + k * math.pi / 3
        its.append(hoja((20 + 2 * math.cos(a), 184 + 2 * math.sin(a)),
                        (20 + 12 * math.cos(a + 0.2), 184 + 12 * math.sin(a + 0.2))))
    its.append(PL(xf(rect(-11, -11, 11, 11), 19, 18, math.radians(8)), style="det", fill="#e8d7b0", z=2))
    its.append(PL(xf(rect(-9, -9, 9, 9), 19, 18, math.radians(-6)), style="det", fill=C["libros"][1], z=3))
    return its


def blk_mesa_centro():
    """Mesa de centro redonda de 75 con bandeja, velas y libros; pie oculto."""
    its = [CI(0, 0, 37.5, fill=C["madera_osc"], z=0, cover=True),
           CI(0, 0, 34.5, style="det", z=1),
           DS(tess(rr(-20, -20, 20, 20, 20), True), z=1),
           PL(xf(rr(-14, -9, 14, 9, 3), -8, 8, math.radians(20)), style="det", fill="#d9c3a0", z=2),
           CI(-13, 5, 3, style="det", fill=C["blanco"], z=3), CI(-4, 10, 3, style="det", fill=C["blanco"], z=3),
           PL(xf(rect(-9, -6, 9, 6), 14, -15, math.radians(-12)), style="det", fill=C["libros"][4], z=2),
           PL(xf(rect(-8, -5, 8, 5), 14, -15, math.radians(6)), style="det", fill=C["libros"][1], z=3)]
    return its


def blk_alfombra_salon():
    """Alfombra 200 x 200 de pelo corto con doble cenefa y rombo central
    (sin flecos: asi no invade el pilar ni el paso de la corredera)."""
    its = [PL(rr(-100, -100, 100, 100, 2), fill=C["alfombra"], z=0),
           PL(rr(-92, -92, 92, 92, 1), style="det", z=1),
           PL(rr(-88, -88, 88, 88, 1), style="det", z=1),
           PL([(0, -50, 0), (50, 0, 0), (0, 50, 0), (-50, 0, 0)], style="det", z=1),
           PL([(0, -41, 0), (41, 0, 0), (0, 41, 0), (-41, 0, 0)], style="det", z=1)]
    for a in (0, 90, 180, 270):                                      # esquinas de la cenefa
        its.append(PL(xf([(88, 78, 0), (78, 78, 0), (78, 88, 0)], 0, 0, math.radians(a)),
                      style="det", closed=False, z=1))
    return its


def blk_puf():
    its = [CI(0, 0, 25, fill=C["mostaza"], z=0, cover=True), CI(0, 0, 22, style="det", z=1),
           CI(0, 0, 1.5, style="det", z=2)]
    for k in range(8):
        a = k * math.pi / 4
        its.append(LN((3 * math.cos(a), 3 * math.sin(a)), (11 * math.cos(a), 11 * math.sin(a)), style="det", z=1))
    return its


def blk_lampara_pie():
    """Lampara de pie: base, fuste y pantalla (por encima: a trazos)."""
    return [CI(0, 0, 15, fill=C["gris"], z=0, cover=True), CI(0, 0, 13, style="det", z=1),
            CI(0, 0, 1.5, z=2), DS(circle_pts(0, 0, 22) + [circle_pts(0, 0, 22)[0]], z=3)]


def blk_aplique():
    """Aplique de pared con brazo (pared en X = 0, hacia +X)."""
    return [PL(rect(0, -5, 1.5, 5), z=0), LN((1.5, 0), (10, 0), z=0),
            CI(15, 0, 5.5, fill=C["luz"], z=1, cover=True), CI(15, 0, 2, style="det", z=2)]


def blk_corredera():
    """Puerta corredera vista de 90 para el hueco de 88: hoja cerrada, posicion
    abierta a trazos, guia y flecha. Origen en la jamba izquierda, cara del
    tabique hacia la sala (la sala queda hacia -Y)."""
    its = [PL(rect(-3, -8, 91.2, -4), fill=C["madera"], z=1, cover=True),
           CI(4, -6, 1.1, style="det", z=2),
           LN((-5, -2), (181, -2), style="det", z=0),
           DS(tess(rect(85, -8, 179.2, -4), True), z=0),
           PL([(28, -14, 0), (62, -14, 0)], style="det", closed=False, z=2),
           PL([(57, -16.5, 0), (62, -14, 0), (57, -11.5, 0)], style="det", closed=False, z=2)]
    return its


def blk_libreria_infantil():
    """Libreria-almacen infantil 256 x 35 contra la medianera, 7 modulos: libros,
    cajas de tela, cuentos de frente, juguetes y el modulo junto a la escalera
    cerrado (costado de 3 cm). Origen en el extremo izquierdo, en la pared; el
    mueble queda hacia -Y."""
    L, D, n = 256.0, 35.0, 7
    m = L / n
    its = [PL(rect(0, -D, L, 0), fill="#e8d6b4", z=0, cover=True),
           LN((1.8, -0.8), (L - 3.0, -0.8), style="det", z=1)]
    for i in range(n + 1):
        x = i * m
        x0, x1 = (0, 1.8) if i == 0 else ((L - 3.0, L) if i == n else (x - 0.9, x + 0.9))
        its.append(PL(rect(x0, -D, x1, 0), fill=C["madera_osc"], z=2, cover=True))
    import random
    rnd = random.Random(7)
    for i in range(n):
        xa = i * m + (1.8 if i == 0 else 0.9)
        xb = (i + 1) * m - (3.0 if i == n - 1 else 0.9)
        xm = (xa + xb) / 2
        kind = ["libros", "caja", "cuentos", "juguetes", "caja2", "libros", "cerrado"][i]
        if kind == "libros":
            x = xa + 1.0
            j = 0
            while x < xb - 2.0:
                w = rnd.uniform(1.8, 4.2)
                d = rnd.uniform(15, 22)
                if x + w > xb - 1.0:
                    break
                its.append(PL(rect(x, -D + 1.5, x + w, -D + 1.5 + d), style="det",
                              fill=C["libros"][j % len(C["libros"])], z=3))
                x += w + 0.25
                j += 1
        elif kind in ("caja", "caja2"):
            col = C["salvia"] if kind == "caja" else C["mostaza"]
            its.append(PL(rr(xa + 1.5, -D + 2, xb - 1.5, -3, 3), style="det", fill=col, z=3, cover=True))
            its.append(PL(rr(xm - 5, -D + 3.2, xm + 5, -D + 5.6, 1.2), style="det", fill="#00000022", z=4))
        elif kind == "cuentos":
            for k, yy in enumerate((-30.5, -24.5, -18.5)):
                its.append(PL(rect(xa + 2, yy, xb - 2, yy + 1.6), style="det", fill=C["libros"][k + 2], z=3))
        elif kind == "juguetes":
            its.append(CI(xm - 5, -17, 8.5, style="det", fill=C["coral"], z=3, cover=True))
            its.append(PL([(xm - 13.5, -17, 0.4), (xm + 3.5, -17, 0)], style="det", closed=False, z=4))
            its.append(PL(xf(rect(-3.5, -3.5, 3.5, 3.5), xm + 10, -27, 0.2), style="det", fill=C["azul"], z=3))
            its.append(PL(xf(rect(-3.5, -3.5, 3.5, 3.5), xm + 10, -12, -0.3), style="det", fill=C["amarillo"], z=3))
        elif kind == "cerrado":
            its.append(LN((xa, -D + 1.8), (xb, -D + 1.8), style="det", z=3))
            its.append(PL(rect(xm - 4, -D + 0.3, xm + 4, -D + 1.3), style="det", z=3))
    return its


def blk_banco_arcon():
    """Banco de lectura con arcon 110 x 45 contra la pared del bano: cojin de
    asiento con vivo, cojin de respaldo, dos cojines sueltos y un libro abierto.
    Origen en la pared, extremo inferior; el banco queda hacia +X."""
    its = [PL(rr4(0, 0, 45, 110, 0, 2, 2, 0), fill=C["madera"], z=0, cover=True),
           LN((43, 1), (43, 109), style="det", z=1),
           PL(rr(0.5, 2, 8.5, 108, 3), fill=C["salvia"], z=1, cover=True),
           PL(rr(9.5, 1.5, 42, 108.5, 4), fill=C["salvia_cl"], z=1, cover=True),
           PL(rr(11.5, 3.5, 40, 106.5, 2), style="det", z=2)]
    its += cojin(16.5, 88, math.pi / 2, 34, 12, C["mostaza"], 3)
    its += cojin(16.5, 22, math.pi / 2, 34, 12, C["coral"], 3)
    libro = [PL(xf(rect(0, -7, 11, 7), 30, 55, math.radians(20)), style="det", fill=C["blanco"], z=5, cover=True),
             PL(xf(rect(-11, -7, 0, 7), 30, 55, math.radians(20)), style="det", fill=C["blanco"], z=5, cover=True),
             PL(xf([(0, -7, 0), (0, 7, 0)], 30, 55, math.radians(20)), style="det", closed=False, z=6)]
    return its + libro


def blk_alfombra_juego():
    """Alfombra de juego 170 x 120 con carretera para coches y paso de cebra."""
    its = [PL(rr(-85, -60, 85, 60, 12), fill=C["alfombra_j"], z=0),
           PL(rr(-72, -47, 72, 47, 26), style="det", fill=C["asfalto"], z=1),
           PL(rr(-52, -27, 52, 27, 10), style="det", fill=C["alfombra_j"], z=2),
           DS(tess(rr(-62, -37, 62, 37, 18), True), z=3)]
    for k in range(5):
        x = -11 + k * 5
        its.append(PL(rect(x, -46, x + 3, -28), style="det", fill=C["blanco"], z=4))
    its.append(CI(-30, 0, 8, style="det", fill="#f4d58d", z=3))        # una casita / plaza
    its.append(CI(30, 0, 8, style="det", fill="#9cc5a1", z=3))         # un arbol
    return its


def blk_mesa_infantil():
    return [CI(0, 0, 30, fill=C["amarillo"], z=0, cover=True), CI(0, 0, 27.5, style="det", z=1),
            PL(xf(rect(-11, -8, 11, 8), -5, 5, math.radians(15)), style="det", fill=C["blanco"], z=2, cover=True),
            CI(14, -12, 4, style="det", fill=C["libros"][1], z=2),
            LN((12.5, -12), (10, -18), style="det", z=3), LN((15, -11), (17, -18.5), style="det", z=3),
            LN((14, -13.5), (14.5, -19.5), style="det", z=3)]


def blk_taburete():
    return [CI(0, 0, 15, fill=C["coral"], z=0, cover=True), CI(0, 0, 12.5, style="det", z=1)]


def blk_puf_pera():
    """Puf pera de ~72 x 62 visto desde arriba, con la hendidura del asiento."""
    n = 36
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        r = 1 + 0.07 * math.sin(3 * a + 0.4) + 0.03 * math.cos(5 * a)
        pts.append((36 * r * math.cos(a), 31 * r * math.sin(a), 0.0))
    ins = []
    for i in range(n):
        a = 2 * math.pi * i / n
        ins.append((-5 + 19 * math.cos(a), 2 + 15 * math.sin(a), 0.0))
    return [PL(pts, fill=C["azul"], z=0, cover=True), PL(ins, style="det", z=1),
            PL([(20, -24, 0.12), (30, -8, 0)], style="det", closed=False, z=1),
            PL([(-26, 16, 0.12), (-14, 27, 0)], style="det", closed=False, z=1)]


def blk_lampara_techo():
    """Lampara colgante (planta): pantalla, borde, cable y aspa de punto de luz."""
    return [CI(0, 0, 20, fill=C["luz"], z=0, cover=True), CI(0, 0, 17, style="det", z=1),
            CI(0, 0, 1.5, z=2), LN((-3.5, -3.5), (3.5, 3.5), z=2), LN((-3.5, 3.5), (3.5, -3.5), z=2)]


def blk_puerta_seguridad(W):
    """Puerta de seguridad infantil de W de ancho en la llegada de la escalera:
    postes, puerta y su barrido hacia el descansillo (nunca hacia la escalera)."""
    arc = [(W - 3 + 70 * math.cos(math.radians(a)), 70 * math.sin(math.radians(a))) for a in range(180, 271, 5)]
    return [PL(rect(0, -3, 3, 3), fill=C["gris"], z=0), PL(rect(W - 3, -3, W, 3), fill=C["gris"], z=0),
            PL(rect(3, -1, W - 3, 1), fill=C["blanco"], z=0),
            DS(arc, z=1), DS([(W - 3, 0), (W - 3, -70)], z=1)]


# ---------------------------------------------------------------- distribucion
W_ESC = 109.5
BLOQUES = {
    "PS_ALFOMBRA_SALON_200x200": (blk_alfombra_salon, None),
    "PS_SOFA_CHAISE_240x160": (blk_sofa, "outline"),
    "PS_MUEBLE_TV_200x40": (blk_mueble_tv, "outline"),
    "PS_MESA_CENTRO_D75": (blk_mesa_centro, "outline"),
    "PS_PUF_D50": (blk_puf, "outline"),
    "PS_LAMPARA_PIE": (blk_lampara_pie, "outline"),
    "PS_APLIQUE_PARED": (blk_aplique, None),
    "PS_PUERTA_CORREDERA_90": (blk_corredera, None),
    "PS_ALFOMBRA_JUEGO_170x120": (blk_alfombra_juego, None),
    "PS_LIBRERIA_INFANTIL_256x35": (blk_libreria_infantil, "outline"),
    "PS_BANCO_ARCON_110x45": (blk_banco_arcon, "outline"),
    "PS_MESA_INFANTIL_D60": (blk_mesa_infantil, "outline"),
    "PS_TABURETE_D30": (blk_taburete, "outline"),
    "PS_PUF_PERA": (blk_puf_pera, "outline"),
    "PS_LAMPARA_TECHO": (blk_lampara_techo, None),
    "PS_PUERTA_SEGURIDAD": (lambda: blk_puerta_seguridad(W_ESC), None),
}

# (bloque, x, y, giro en grados, capa)  -- en orden de dibujo (alfombras primero)
INSERCIONES = [
    ("PS_ALFOMBRA_SALON_200x200", 225.0, 143.0, 0, "PS-ALFOMBRAS"),
    ("PS_ALFOMBRA_JUEGO_170x120", 390.0, 440.0, 0, "PS-ALFOMBRAS"),
    ("PS_SOFA_CHAISE_240x160", SALA_W - 0.5, 1.0, 0, "PS-MOBILIARIO"),
    ("PS_MUEBLE_TV_200x40", 0.5, 43.0, 0, "PS-MOBILIARIO"),
    ("PS_MESA_CENTRO_D75", 228.0, 150.0, 0, "PS-MOBILIARIO"),
    ("PS_PUF_D50", 97.0, 68.0, 0, "PS-MOBILIARIO"),
    ("PS_LAMPARA_PIE", 225.0, 24.0, 0, "PS-ILUMINACION"),
    ("PS_APLIQUE_PARED", SALA_W, 50.0, 180, "PS-ILUMINACION"),
    ("PS_APLIQUE_PARED", SALA_W, 160.0, 180, "PS-ILUMINACION"),
    ("PS_PUERTA_CORREDERA_90", PUERTA_X0, SALA_H, 0, "PS-CARPINTERIA"),
    ("PS_LIBRERIA_INFANTIL_256x35", BANO_X, TECHO_Y, 0, "PS-MOBILIARIO"),
    ("PS_BANCO_ARCON_110x45", BANO_X, 390.0, 0, "PS-MOBILIARIO"),
    ("PS_PUF_PERA", 345.0, 440.0, 0, "PS-MOBILIARIO"),
    ("PS_MESA_INFANTIL_D60", 437.0, 440.0, 0, "PS-MOBILIARIO"),
    ("PS_TABURETE_D30", 437.0, 394.0, 0, "PS-MOBILIARIO"),
    ("PS_TABURETE_D30", 437.0, 486.0, 0, "PS-MOBILIARIO"),
    ("PS_LAMPARA_TECHO", 437.0, 440.0, 0, "PS-ILUMINACION"),
    ("PS_APLIQUE_PARED", BANO_X, 478.0, 0, "PS-ILUMINACION"),
    ("PS_PUERTA_SEGURIDAD", 586.5, 190.0, 0, "PS-SEGURIDAD"),
]

TEXTOS = [  # (x, y, altura, texto, capa)
    (225.0, 213.0, 10.0, "SALA DE ESTAR\\P\\H0.7x;S = 10,40 m²", "PS-TEXTOS"),
    (380.0, 345.0, 9.0, "ZONA DE JUEGO Y LECTURA\\P\\H0.7x;S = 5,3 m² (sin contar el paso)", "PS-TEXTOS"),
    (492.0, 228.0, 6.5, "BARANDILLA: h ≥ 1,10 m,\\Psin huecos > 10 cm\\Py no escalable", "PS-SEGURIDAD"),
    (641.0, 168.0, 6.5, "PUERTA DE\\PSEGURIDAD", "PS-SEGURIDAD"),
]
LIDERES = [((522.0, 246.0), (579.0, 262.0), "PS-SEGURIDAD")]

COTAS = [  # (p1, p2, base, angulo, texto)  en cm
    ((40.5, 150.0), (190.5, 150.0), (0, 150.0), 0, "paso <>"),
    ((7.5, 104.0), (SALA_W - 95.5, 104.0), (0, 104.0), 0, "TV-sofá <>"),
    ((508.5, 522.0), (BARANDA_X, 522.0), (0, 522.0), 0, "libre <>"),
    ((500.0, PASILLO_Y0), (500.0, PASILLO_Y1), (500.0, 0), 90, "paso <>"),
]

CAPAS = {"PS-MOBILIARIO": 3, "PS-ALFOMBRAS": 42, "PS-ILUMINACION": 6, "PS-CARPINTERIA": 4,
         "PS-SEGURIDAD": 30, "PS-TEXTOS": 7, "PS-COTAS": 1, "PS-REF-PLANO": 9}


# ---------------------------------------------------------------- ocultas (dentro de cada bloque)
def lines_of(geom):
    if geom.is_empty:
        return []
    if isinstance(geom, LineString):
        return [list(geom.coords)]
    if isinstance(geom, MultiLineString):
        return [list(g.coords) for g in geom.geoms]
    out = []
    for g in getattr(geom, "geoms", []):
        out += lines_of(g)
    return out


def procesar(its):
    """Para el DXF: cada elemento sin las partes tapadas por los de encima.
    Devuelve (elemento, None) si queda entero o (elemento, [lineas]) si se recorta."""
    res = []
    covers = [(it.z, it.polygon()) for it in its if it.cover and it.polygon() is not None]
    for it in its:
        if it.kind == "text":
            res.append((it, None))
            continue
        encima = [p for z, p in covers if z > it.z]
        path = it.path()
        if not encima or path is None:
            res.append((it, None))
            continue
        tapa = unary_union(encima)
        ls = LineString(path)
        if not ls.intersects(tapa):
            res.append((it, None))
            continue
        vis = ls.difference(tapa.buffer(0.02))
        res.append((it, [l for l in lines_of(vis) if LineString(l).length > 0.05]))
    return res


def contorno(its):
    polys = [it.polygon() for it in its if it.cover and it.polygon() is not None]
    u = unary_union(polys)
    if u.geom_type == "MultiPolygon":
        u = max(u.geoms, key=lambda g: g.area)
    return list(u.exterior.coords)[:-1]


def bloques():
    out = {}
    for name, (fn, wipe) in BLOQUES.items():
        its = fn()
        base = [it for it in its if it.z == 0 and it.cover] if wipe == "outline" else []
        out[name] = dict(items=its, wipeout=contorno(base) if base else None)
    return out


# ---------------------------------------------------------------- plano de referencia (del usuario)
def ref_plano():
    """Muros del plano del usuario alrededor de las dos zonas, medidos en la
    captura (poligonos en cm). Solo para comprobar el encaje (capa congelada)."""
    P = []

    def R(x0, y0, x1, y1):
        P.append([(x0, y0), (x1, y0), (x1, y1), (x0, y1)])
    # sala
    R(-6.6, -9.3, 0, 273.1)                       # tabique izquierdo
    R(SALA_W, -9.3, SALA_W + 6.6, 273.1)          # tabique derecho
    R(-6.6, SALA_H, PUERTA_X0, 273.1)             # tabique superior (izq. del hueco)
    R(PUERTA_X1, SALA_H, SALA_W + 6.6, 273.1)     # tabique superior (dcha.)
    R(0, -9.3, PILAR_X, PILAR_Y)                  # zona del pilar
    R(PILAR_X, -9.3, 720, 0)                      # muro inferior
    R(-110, -29.2, 720, -9.3)                     # medianera inferior
    # bano y medianera superior
    R(245.8, PASILLO_Y1, BANO_X, TECHO_Y)
    R(-101.4, PASILLO_Y1, -27.2, 380.5)
    R(101.4, PASILLO_Y1, BANO_X, 380.5)
    R(-110, TECHO_Y, 720, 569.0)
    # tabique de los dormitorios (con los accesos)
    R(-101.4, -9.3, -94.8, 174.0)
    R(-101.4, 366.0, -94.8, TECHO_Y)
    # escalera: barandilla (algo inclinada en el plano) y su lado derecho
    P.append([(574.0, TECHO_Y), (581.3, TECHO_Y), (587.3, 134.6), (580.0, 134.6)])
    P.append([(688.1, TECHO_Y), (694.7, TECHO_Y), (702.6, 180.0), (695.3, 180.0)])
    # dormitorio principal (tabique con su puerta)
    R(713.0, -9.3, 722.0, 55.0)
    R(713.0, 140.0, 722.0, TECHO_Y)
    return P


def ref_escalera():
    """Peldanos, compensacion y linea de huella (solo lineas)."""
    L = []
    for y in (434.9, 404.7, 373.0, 344.2, 314.6, 284.5, 254.5, 224.8, 195.4):
        t = (TECHO_Y - y) / (TECHO_Y - 134.6)
        L.append([(581.3 + 6.0 * t, y), (694.7 + 7.9 * t, y)])
    piv = (581.3, 434.9)
    for q in ((603.0, TECHO_Y), (640.0, TECHO_Y), (694.7, 492.0)):
        L.append([piv, q])
    return L


def ref_pilar():
    return [(3.3, -9.9), (163.7, -9.9), (163.7, 10.6), (3.3, 10.6)]


if __name__ == "__main__":
    B = bloques()
    for n, b in B.items():
        print("%-30s %4d elementos  wipeout=%s" % (n, len(b["items"]), "si" if b["wipeout"] else "no"))
