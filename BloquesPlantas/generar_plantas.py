#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Biblioteca de bloques CAD de plantas de interior (PLANTA + ALZADO).

Genera tres DXF con la misma geometria en distintas unidades de dibujo
(mm, cm y m) y una lamina de vista previa en PNG.

Caracteristicas de los bloques:
  - Punto base: centro de la maceta (vistas en planta) y centro de la
    base de la maceta, a cota de suelo (alzados). Excepcion: el pothos
    colgante en alzado tiene el punto base en el gancho del techo.
  - Lineas ocultas ya eliminadas: las hojas de delante tapan a las de
    detras, asi que el bloque queda limpio aunque se congele el relleno.
  - Capas:
      VEG-HOJAS    contorno de hojas y tallos verdes
      VEG-NERVIOS  nervios y detalles finos
      VEG-TRONCO   troncos y ramas leñosas
      VEG-MACETA   macetas, platos, patas y cuerdas
      VEG-FLOR     flores
      VEG-RELLENO  rellenos solidos de color (congelar para plano a linea)

Uso:  python3 generar_plantas.py        (requiere ezdxf y shapely;
                                          matplotlib para la vista previa)
"""
import math
import os
import random

import numpy as np
import shapely
from shapely import affinity
from shapely.geometry import (LineString, MultiLineString, Point, Polygon,
                              box)
from shapely.ops import linemerge, unary_union

import ezdxf
from ezdxf.colors import DXF_DEFAULT_COLORS, int2rgb
from ezdxf.enums import TextEntityAlignment

OUT_DIR = os.path.dirname(os.path.abspath(__file__))


def rad(d):
    return d * math.pi / 180.0


# ---------------------------------------------------------------- colores
GREEN = (112, 170, 104)
GREEN_DEEP = (84, 146, 92)
GREEN_FRESH = (132, 186, 104)
GREEN_STEM = (150, 188, 118)
SANSE = (70, 118, 82)
SANSE_EDGE = (222, 210, 120)
OLIVE = (150, 170, 128)
OLIVE_LEAF = (120, 146, 104)
SUCC = (134, 180, 166)
HAWOR = (74, 124, 94)
TERRACOTTA = (224, 142, 102)
SOIL = (122, 94, 74)
CREAM = (242, 234, 216)
WHITE = (248, 246, 242)
CONCRETE = (198, 196, 190)
BASKET = (216, 188, 142)
WOOD = (200, 154, 108)
BLUE = (152, 186, 216)
TRUNK = (150, 112, 82)
PINK = (244, 158, 184)
YELLOW = (250, 212, 102)
CORD = (234, 220, 194)

LAYERS = {
    # nombre: (rgb, grosor de linea en 1/100 mm)
    'VEG-HOJAS': ((46, 94, 56), 18),
    'VEG-NERVIOS': ((82, 140, 92), 9),
    'VEG-TRONCO': ((104, 72, 48), 18),
    'VEG-MACETA': ((116, 84, 64), 25),
    'VEG-FLOR': ((176, 72, 110), 13),
    'VEG-RELLENO': ((150, 200, 150), 0),
    'VEG-TEXTO': ((70, 70, 70), 18),
}


def tone(rgb, f):
    """Aclara (f>0) u oscurece (f<0) un color."""
    if f >= 0:
        return tuple(int(round(c + (255 - c) * f)) for c in rgb)
    return tuple(int(round(c * (1 + f))) for c in rgb)


_ACI = {}


def nearest_aci(rgb):
    if rgb not in _ACI:
        best, bd = 7, 1e18
        for i in range(1, 256):
            r, g, b = int2rgb(DXF_DEFAULT_COLORS[i])
            d = (r - rgb[0]) ** 2 + (g - rgb[1]) ** 2 + (b - rgb[2]) ** 2
            if d < bd:
                best, bd = i, d
        _ACI[rgb] = best
    return _ACI[rgb]


# ---------------------------------------------------------------- curvas
def catmull(pts, n=10):
    """Curva Catmull-Rom abierta que pasa por pts (extremos incluidos)."""
    P = [np.array(p, float) for p in pts]
    if len(P) < 3:
        return [tuple(p) for p in P]
    P = [2 * P[0] - P[1]] + P + [2 * P[-1] - P[-2]]
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for j in range(n):
            t = j / n
            out.append(0.5 * (2 * p1 + (-p0 + p2) * t
                              + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(P[-2])
    return [tuple(p) for p in out]


def bezier(p0, p1, p2, n=24):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1])
            for t in np.linspace(0, 1, n)]


def arch_path(x0, y0, th0, length, turn, n=48, power=1.3):
    """Trayectoria que arranca con angulo th0 y va girando 'turn' grados
    (como una fronda que se vence por su peso)."""
    pts = [(x0, y0)]
    x, y = x0, y0
    ds = length / n
    for i in range(n):
        s = (i + 0.5) * ds
        ph = rad(th0 + turn * (s / length) ** power)
        x += ds * math.cos(ph)
        y += ds * math.sin(ph)
        pts.append((x, y))
    return pts


class Path:
    """Polilinea parametrizada por longitud de arco."""

    def __init__(self, pts):
        self.P = np.array(pts, float)
        d = np.hypot(*np.diff(self.P, axis=0).T)
        self.s = np.concatenate([[0.0], np.cumsum(d)])
        self.L = float(self.s[-1])
        t = np.diff(self.P, axis=0)
        self.ang = np.unwrap(np.arctan2(t[:, 1], t[:, 0]))
        self.mid = (self.s[:-1] + self.s[1:]) / 2

    def at(self, s):
        x = float(np.interp(s, self.s, self.P[:, 0]))
        y = float(np.interp(s, self.s, self.P[:, 1]))
        a = float(np.interp(s, self.mid, self.ang))
        return x, y, math.degrees(a)

    def line(self):
        return LineString(self.P)


# ------------------------------------------------------------- geometria
def xform(geom, x0=0.0, y0=0.0, ang=0.0, k=0.0, sx=1.0, sy=1.0, seg=None):
    """Escala (sx, sy), curva el eje x local con curvatura k, gira 'ang'
    grados y traslada a (x0, y0)."""
    if seg:
        geom = shapely.segmentize(geom, seg)
    ca, sa = math.cos(rad(ang)), math.sin(rad(ang))

    def f(c):
        x = c[:, 0] * sx
        y = c[:, 1] * sy
        if abs(k) > 1e-12:
            ph = k * x
            X = np.sin(ph) / k - y * np.sin(ph)
            Y = (1 - np.cos(ph)) / k + y * np.cos(ph)
        else:
            X, Y = x, y
        return np.column_stack([x0 + X * ca - Y * sa, y0 + X * sa + Y * ca])

    out = shapely.transform(geom, f)
    if out.geom_type in ('Polygon', 'MultiPolygon') and not out.is_valid:
        out = out.buffer(0)
    return out


def largest(g):
    if g.geom_type == 'Polygon':
        return g
    polys = [p for p in getattr(g, 'geoms', []) if p.geom_type == 'Polygon']
    return max(polys, key=lambda p: p.area) if polys else Polygon()


def rounded(g, r):
    return g.buffer(-r, join_style=1).buffer(r, join_style=1)


def tapered(pts, w0, w1, round_end=True):
    """Tallo o tronco de ancho variable (w0 en el arranque, w1 al final)."""
    P = np.array(pts, float)
    t = np.gradient(P, axis=0)
    t /= np.hypot(t[:, 0], t[:, 1])[:, None]
    nr = np.column_stack([-t[:, 1], t[:, 0]])
    w = np.linspace(w0, w1, len(P))[:, None] / 2
    g = Polygon(np.vstack([P + nr * w, (P - nr * w)[::-1]])).buffer(0)
    if round_end:
        g = g.union(Point(P[-1]).buffer(w1 / 2, quad_segs=8))
    return g


def below_rim(half_w, top):
    """Zona interior de la maceta por debajo del borde (para recortar tallos)."""
    return box(-half_w, -1e4, half_w, top - 2)


def circle(x, y, r, n=64):
    return Point(x, y).buffer(r, quad_segs=max(4, n // 4))


def ellipse(x, y, a, b, ang=0.0, n=48):
    e = affinity.scale(Point(0, 0).buffer(1, quad_segs=n // 4), a, b)
    return affinity.translate(affinity.rotate(e, ang, origin=(0, 0)), x, y)


def leaf_from_half(half, L, wf=1.0, asym=0.0, n=8):
    """Hoja simetrica a partir de su medio contorno normalizado, dado de la
    punta (1,0) a la base (xb,0). La hoja apunta hacia +x."""
    up = catmull([(x * L, y * L * wf) for x, y in half], n)
    lo = [(x, -y * (1 + asym)) for x, y in reversed(up)]
    return Polygon(up + lo[1:-1]).buffer(0)


def profile_leaf(L, W, a=1.0, b=1.0, n=24):
    """Hoja con semiancho proporcional a t^a (1-t)^b, base en (0,0)."""
    ts = [(1 - math.cos(math.pi * i / n)) / 2 for i in range(n + 1)]
    f = [t ** a * (1 - t) ** b for t in ts]
    m = max(f)
    up = [(t * L, 0.5 * W * v / m) for t, v in zip(ts, f)]
    lo = [(x, -y) for x, y in reversed(up)]
    return Polygon(up + lo[1:-1]).buffer(0)


def half_width(poly, x, side):
    g = poly.intersection(LineString([(x, 0), (x, side * 1e5)]))
    if g.is_empty:
        return 0.0
    b = g.bounds
    return b[3] if side > 0 else -b[1]


def pinnate_veins(leaf, L, n, x0=0.1, x1=0.82, ang=55, reach=0.9,
                  base=0.03, tip=0.93):
    """Nervio central + n pares de nervios laterales curvados hacia la
    punta, recortados al interior de la hoja."""
    lines = [LineString([(base * L, 0), (tip * L, 0)])]
    for i in range(n):
        x = L * (x0 + (x1 - x0) * i / max(1, n - 1))
        for s in (1, -1):
            hw = half_width(leaf, x, s)
            d = hw * reach / math.sin(rad(ang))
            p0 = (x, 0)
            p2 = (x + d * math.cos(rad(ang)), s * d * math.sin(rad(ang)))
            p1 = (x + 0.2 * d * math.cos(rad(ang)),
                  s * 0.62 * d * math.sin(rad(ang)))
            lines.append(LineString(bezier(p0, p1, p2, 10)))
    return MultiLineString(lines).intersection(leaf.buffer(-0.012 * L))


# ------------------------------------------------------------ escena 2D
class Item:
    def __init__(self, geom, fill, edge, details, subfills, z):
        self.geom, self.fill, self.edge = geom, fill, edge
        self.details, self.subfills, self.z = details, subfills, z


class Scene:
    """Lista de figuras ordenadas de atras hacia delante. Al resolverla se
    eliminan las partes tapadas (lineas ocultas) de rellenos y lineas."""

    def __init__(self):
        self.items = []
        self._n = 0

    def add(self, geom, fill=None, edge='VEG-HOJAS', details=(),
            subfills=(), z=None):
        if geom is None or geom.is_empty:
            return
        if not geom.is_valid:
            geom = geom.buffer(0)
        self._n += 1
        zz = self._n * 1e-6 + (z if z is not None else 0.0)
        det = []
        for d in details:
            if len(d) == 2:
                d = (d[0], d[1], None)
            det.append(d)
        self.items.append(Item(geom, fill, edge, det, list(subfills), zz))

    def solve(self):
        items = sorted(self.items, key=lambda it: it.z)
        mask = None
        hatches, lines = [], []
        for it in reversed(items):
            g = it.geom
            vis = g if mask is None else g.difference(mask)
            if not vis.is_empty and vis.area > 2:
                if it.fill is not None:
                    rest, subs = vis, []
                    for sg, rgb in it.subfills:
                        sv = sg.intersection(vis)
                        if not sv.is_empty and sv.area > 1:
                            subs.append((sv, rgb))
                            rest = rest.difference(sg)
                    hatches.append((rest, it.fill))
                    hatches.extend(subs)
                if it.edge:
                    b = g.boundary if mask is None else g.boundary.difference(mask)
                    lines.append((b, it.edge, None))
                for dg, lay, lw in it.details:
                    dv = dg.intersection(vis)
                    if not dv.is_empty:
                        lines.append((dv, lay, lw))
            mask = g if mask is None else mask.union(g)
        return hatches[::-1], lines[::-1], mask

    def bounds(self):
        return unary_union([it.geom for it in self.items]).bounds


# ------------------------------------------------------------- DXF out
def iter_lines(g):
    if g.is_empty:
        return
    t = g.geom_type
    if t in ('LineString', 'LinearRing'):
        yield LineString(g.coords)
    elif t == 'Polygon':
        yield LineString(g.exterior.coords)
        for r in g.interiors:
            yield LineString(r.coords)
    elif t in ('MultiLineString', 'MultiPolygon', 'GeometryCollection'):
        for p in g.geoms:
            yield from iter_lines(p)


def iter_polys(g):
    t = g.geom_type
    if t == 'Polygon':
        yield g
    elif t in ('MultiPolygon', 'GeometryCollection'):
        for p in g.geoms:
            yield from iter_polys(p)


SIMPLIFY = 0.35  # tolerancia de simplificacion (mm)


def pt(x, y, s):
    nd = {1.0: 1, 0.1: 2, 0.001: 4}.get(s, 6)
    return (round(x * s, nd), round(y * s, nd))


def pts_dxf(coords, s):
    """Coordenadas escaladas y redondeadas, sin vertices repetidos."""
    out = []
    for x, y in coords:
        p = pt(x, y, s)
        if not out or p != out[-1]:
            out.append(p)
    return out


def add_lines(layout, g, layer, s, lw=None):
    lines = [l for l in iter_lines(g) if l.length > 0]
    if not lines:
        return
    merged = linemerge(MultiLineString(lines)) if len(lines) > 1 else lines[0]
    for l in iter_lines(merged):
        l = l.simplify(SIMPLIFY)
        if l.length < 1.5:
            continue
        pts = list(l.coords)
        closed = len(pts) > 3 and math.dist(pts[0], pts[-1]) < 1e-6
        if closed:
            pts = pts[:-1]
        attrs = {'layer': layer}
        if lw is not None:
            attrs['lineweight'] = lw
        pl = pts_dxf(pts, s)
        if len(pl) < 2:
            continue
        layout.add_lwpolyline(pl, close=closed,
                              dxfattribs=attrs)


def add_hatch(layout, g, rgb, s):
    polys = []
    for p in iter_polys(g):
        p = p.simplify(SIMPLIFY)
        if p.is_empty:
            continue
        polys.extend(q for q in iter_polys(p) if q.area > 3)
    if not polys:
        return
    rings = []
    for p in polys:
        ext = pts_dxf(p.exterior.coords[:-1], s)
        if len(ext) < 3:
            continue
        rings.append((ext, 1))
        for r in p.interiors:
            hole = pts_dxf(r.coords[:-1], s)
            if len(hole) >= 3:
                rings.append((hole, 0))
    if not rings:
        return
    h = layout.add_hatch(dxfattribs={'layer': 'VEG-RELLENO'})
    h.set_solid_fill(color=nearest_aci(rgb), rgb=rgb)
    for ring, flags in rings:
        h.paths.add_polyline_path(ring, is_closed=True, flags=flags)


# ============================================================== MACETAS
# ---- en planta (centradas en el origen)
def pot_plan_round(sc, R, color, rim=12, z=0.0, ticks=False, handles=False,
                   scallop=0, saucer=0):
    if saucer:
        sc.add(circle(0, 0, R + saucer, 96), tone(color, -0.06), 'VEG-MACETA',
               z=z - 0.2)
    if handles:
        for sgn in (1, -1):
            ear = rounded(box(-26, -30, 26, 30), 12).difference(
                rounded(box(-14, -18, 14, 18), 6))
            sc.add(affinity.translate(ear, sgn * (R + 6), 0),
                   tone(color, -0.1), 'VEG-MACETA', z=z - 0.1)
    if scallop:
        n = scallop
        pts = [((R - 5 + 5 * abs(math.cos(n * t / 2))) * math.cos(t),
                (R - 5 + 5 * abs(math.cos(n * t / 2))) * math.sin(t))
               for t in np.linspace(0, 2 * math.pi, 16 * n, endpoint=False)]
        outer = Polygon(pts)
    else:
        outer = circle(0, 0, R, 96)
    det = []
    if ticks:
        tl = []
        for t in np.arange(0, 360, 7.5):
            c, s_ = math.cos(rad(t)), math.sin(rad(t))
            tl.append(LineString([((R - rim + 2) * c, (R - rim + 2) * s_),
                                  ((R - 2) * c, (R - 2) * s_)]))
        det.append((MultiLineString(tl), 'VEG-MACETA', 9))
    sc.add(outer, color, 'VEG-MACETA', details=det, z=z)
    sc.add(circle(0, 0, R - rim, 96), SOIL, 'VEG-MACETA', z=z + 0.05)


def pot_plan_square(sc, W, color, rim=24, z=0.0):
    outer = rounded(box(-W / 2, -W / 2, W / 2, W / 2), 6)
    lines = []
    for x in np.arange(-W / 2 + 50, W / 2 - 1, 50):
        lines.append(LineString([(x, W / 2 - rim), (x, W / 2)]))
        lines.append(LineString([(x, -W / 2), (x, -W / 2 + rim)]))
        lines.append(LineString([(W / 2 - rim, x), (W / 2, x)]))
        lines.append(LineString([(-W / 2, x), (-W / 2 + rim, x)]))
    sc.add(outer, color, 'VEG-MACETA',
           details=[(MultiLineString(lines), 'VEG-MACETA', 9)], z=z)
    inner = box(-W / 2 + rim, -W / 2 + rim, W / 2 - rim, W / 2 - rim)
    sc.add(inner, SOIL, 'VEG-MACETA', z=z + 0.05)


# ---- en alzado (base de la maceta en y=0, centrada en x=0)
def pot_elev_terracotta(sc, Dt, Db, H, color=TERRACOTTA, saucer=True, z=10.0):
    y0 = 0.0
    if saucer:
        sw = Db * 1.3
        sp = rounded(Polygon([(-sw / 2 + 8, 0), (sw / 2 - 8, 0), (sw / 2, 18),
                              (-sw / 2, 18)]), 3)
        sc.add(sp, tone(color, -0.08), 'VEG-MACETA', z=z + 0.2)
        y0 = 16.0
    rim_h = H * 0.16
    body = rounded(Polygon([(-Db / 2, y0), (Db / 2, y0),
                            (Dt / 2, y0 + H - rim_h), (-Dt / 2, y0 + H - rim_h)]), 6)
    rim = rounded(box(-Dt / 2 * 1.06, y0 + H - rim_h, Dt / 2 * 1.06, y0 + H), 5)
    sc.add(body, color, 'VEG-MACETA', z=z)
    sc.add(rim, tone(color, -0.07), 'VEG-MACETA', z=z + 0.1)
    return y0 + H


def pot_elev_ribbed(sc, Dt, Db, H, color=CREAM, z=10.0):
    body = rounded(Polygon([(-Db / 2, 0), (Db / 2, 0), (Dt / 2, H),
                            (-Dt / 2, H)]), 14)
    lines = []
    for ph in range(-75, 90, 15):
        s_ = math.sin(rad(ph))
        lines.append(LineString([(Db / 2 * s_, 6), (Dt / 2 * s_, H - 16)]))
    sc.add(body, color, 'VEG-MACETA',
           details=[(MultiLineString(lines), 'VEG-MACETA', 9)], z=z)
    lip = rounded(box(-Dt / 2 - 4, H - 14, Dt / 2 + 4, H), 5)
    sc.add(lip, tone(color, -0.05), 'VEG-MACETA', z=z + 0.1)
    return H


def pot_elev_basket(sc, Dt, Db, H, color=BASKET, z=10.0):
    Dm = max(Dt, Db) * 1.05
    left = catmull([(-Db / 2, 0), (-Dm / 2, H * 0.45), (-Dt / 2, H)], 10)
    right = [(-x, y) for x, y in reversed(left)]
    body = rounded(Polygon(left + right), 10)
    lines = []
    for i, y in enumerate(np.arange(26, H - 20, 26)):
        lines.append(LineString([(-Dm, y), (Dm, y)]))
        off = 0 if i % 2 == 0 else 20
        for x in np.arange(-Dm / 2 + off, Dm / 2, 40):
            lines.append(LineString([(x, y + 5), (x, y + 21)]))
    det = [(MultiLineString(lines).intersection(body.buffer(-4)), 'VEG-MACETA', 9)]
    for sgn in (1, -1):
        ring = circle(sgn * (Dt / 2 + 6), H - 44, 26).difference(
            circle(sgn * (Dt / 2 + 6), H - 44, 15))
        sc.add(ring, tone(color, -0.12), 'VEG-MACETA', z=z - 0.1)
    sc.add(body, color, 'VEG-MACETA', details=det, z=z)
    rim = rounded(box(-Dt / 2 - 6, H - 20, Dt / 2 + 6, H), 9)
    sc.add(rim, tone(color, -0.1), 'VEG-MACETA', z=z + 0.1)
    return H


def pot_elev_cylinder(sc, D, H, color=CONCRETE, z=10.0, groove=True,
                      pores=0, seed=3):
    rng = random.Random(seed)
    body = rounded(box(-D / 2, 0, D / 2, H), 8)
    det = []
    if groove:
        det.append((LineString([(-D / 2, H - 34), (D / 2, H - 34)]),
                    'VEG-MACETA', 9))
    pl = []
    for _ in range(pores):
        x, y = rng.uniform(-D / 2 + 20, D / 2 - 20), rng.uniform(20, H - 50)
        pl.append(circle(x, y, rng.uniform(1.5, 3), 12).exterior)
    if pl:
        det.append((MultiLineString([list(p.coords) for p in pl]), 'VEG-MACETA', 9))
    sc.add(body, color, 'VEG-MACETA', details=det, z=z)
    return H


def pot_elev_legs(sc, D, H, leg_h, color=WHITE, leg=WOOD, z=10.0):
    for x_top, x_bot, dz in ((-D * 0.02, -D * 0.01, -0.3),
                             (-D * 0.36, -D * 0.48, 0.2),
                             (D * 0.36, D * 0.48, 0.2)):
        lg = Polygon([(x_top - 11, leg_h + 30), (x_top + 11, leg_h + 30),
                      (x_bot + 6, 0), (x_bot - 6, 0)])
        sc.add(rounded(lg, 2), tone(leg, -0.08 if dz < 0 else 0), 'VEG-MACETA',
               z=z + dz)
    body = rounded(box(-D / 2, leg_h, D / 2, leg_h + H), 26).union(
        box(-D / 2, leg_h + H - 30, D / 2, leg_h + H))
    sc.add(body, color, 'VEG-MACETA',
           details=[(LineString([(-D / 2, leg_h + H - 16), (D / 2, leg_h + H - 16)]),
                     'VEG-MACETA', 9)], z=z + 0.1)
    return leg_h + H


def pot_elev_bowl(sc, Dt, H, color=BLUE, z=10.0):
    half = [(-Dt / 2, H), (-Dt / 2 * 1.02, H * 0.72), (-Dt / 2 * 0.92, H * 0.34),
            (-Dt / 2 * 0.7, H * 0.08), (-Dt / 2 * 0.56, 0)]
    left = catmull(half, 10)
    right = [(-x, y) for x, y in reversed(left)]
    body = Polygon(left + right).buffer(0)
    shine = Polygon(catmull([(-Dt * 0.38, H * 0.78), (-Dt * 0.41, H * 0.5),
                             (-Dt * 0.33, H * 0.22), (-Dt * 0.30, H * 0.3),
                             (-Dt * 0.35, H * 0.52), (-Dt * 0.33, H * 0.76)], 6)).buffer(0)
    sc.add(body, color, 'VEG-MACETA', subfills=[(shine, tone(color, 0.55))], z=z)
    lip = rounded(box(-Dt / 2 - 5, H - 16, Dt / 2 + 5, H), 7)
    sc.add(lip, tone(color, -0.08), 'VEG-MACETA', z=z + 0.1)
    return H


def pot_elev_planter(sc, W, H, color=WOOD, z=10.0):
    for sgn in (1, -1):
        sc.add(box(sgn * (W / 2 - 40) - 20, 0, sgn * (W / 2 - 40) + 20, 22),
               tone(color, -0.2), 'VEG-MACETA', z=z - 0.1)
    body = box(-W / 2, 20, W / 2, H - 30)
    lines = [LineString([(x, 20), (x, H - 30)])
             for x in np.arange(-W / 2 + 50, W / 2 - 1, 50)]
    sc.add(body, color, 'VEG-MACETA',
           details=[(MultiLineString(lines), 'VEG-MACETA', 9)], z=z)
    rim = rounded(box(-W / 2 - 10, H - 34, W / 2 + 10, H), 4)
    sc.add(rim, tone(color, -0.1), 'VEG-MACETA', z=z + 0.1)
    return H


# ============================================================== PLANTAS
# Cada funcion devuelve dict(key, name, latin, pot, plan=Scene, elev=Scene)

MONSTERA_HALF = [(1.0, 0.0), (0.93, 0.10), (0.80, 0.24), (0.60, 0.37),
                 (0.38, 0.43), (0.17, 0.42), (0.0, 0.35), (-0.09, 0.22),
                 (-0.08, 0.09), (-0.01, 0.02), (0.03, 0.0)]


def monstera_leaf(L, rng, n_split=6, holes=True):
    leaf = leaf_from_half(MONSTERA_HALF, L, asym=rng.uniform(-0.06, 0.06))
    cuts, holes_g, vl = [], [], [LineString([(0.03 * L, 0), (0.94 * L, 0)])]
    for side in (1, -1):
        n = max(3, n_split + rng.choice([-1, 0, 0, 1]))
        xs = [x + rng.uniform(-0.02, 0.02) for x in np.linspace(0.13, 0.84, n)]

        def th(x):
            return rad(80 - 44 * x)

        for x in xs:
            X = x * L
            hw = half_width(leaf, X, side)
            d = np.array([math.cos(th(x)), side * math.sin(th(x))])
            nr = np.array([-d[1], d[0]])
            a = np.array([X, side * 0.24 * hw])
            b = a + d * hw * 1.8
            wa, wb = 0.006 * L, 0.03 * L
            cuts.append(Polygon([a + nr * wa, b + nr * wb, b - nr * wb,
                                 a - nr * wa]).union(Point(a).buffer(wa, 4)))
            if holes and rng.random() < 0.6 and L > 250:
                c = a - d * (0.13 * hw)
                if abs(c[1]) > 0.05 * L:
                    holes_g.append(ellipse(c[0], c[1], 0.075 * hw, 0.011 * L,
                                           math.degrees(math.atan2(d[1], d[0])), 20))
        mids = [(xs[i] + xs[i + 1]) / 2 for i in range(len(xs) - 1)]
        mids += [xs[0] - 0.08, xs[-1] + 0.07]
        for xm in mids:
            X = xm * L
            hw = half_width(leaf, X, side)
            d = np.array([math.cos(th(xm)), side * math.sin(th(xm))])
            p0 = np.array([X, 0.0])
            vl.append(LineString([p0, p0 + d * hw * 1.4]))
    leaf2 = largest(leaf.difference(unary_union(cuts)))
    for h in holes_g:
        leaf2 = leaf2.difference(h)
    veins = MultiLineString(vl).intersection(leaf2.buffer(-0.012 * L))
    return leaf2, veins


def monstera():
    rng = random.Random(7)
    # ---- planta
    P = Scene()
    pot_plan_round(P, 190, TERRACOTTA, z=0)
    specs = []
    n = 7
    for i in range(n):
        specs.append(dict(a=360 * i / n + rng.uniform(-12, 12) + 10,
                          r0=rng.uniform(90, 130), L=rng.uniform(320, 380),
                          z=1 + rng.random()))
    for a in (40, 170, 290):
        specs.append(dict(a=a + rng.uniform(-20, 20), r0=rng.uniform(10, 40),
                          L=rng.uniform(220, 260), z=3 + rng.random()))
    for sp in specs:
        leaf, veins = monstera_leaf(sp['L'], rng, 6 if sp['L'] > 300 else 4)
        k = rng.uniform(-6e-4, 6e-4)
        ang = sp['a'] + rng.uniform(-8, 8)
        x0 = sp['r0'] * math.cos(rad(sp['a']))
        y0 = sp['r0'] * math.sin(rad(sp['a']))
        g = xform(leaf, x0, y0, ang, k=k, seg=10)
        v = xform(veins, x0, y0, ang, k=k, seg=10)
        ext = (x0 + 30 * math.cos(rad(ang)), y0 + 30 * math.sin(rad(ang)))
        stem = LineString([(0, 0), ext]).buffer(7, cap_style=2)
        P.add(stem, GREEN_STEM, 'VEG-HOJAS', z=sp['z'] - 0.01)
        f = -0.16 + 0.1 * (sp['z'] - 1)
        P.add(g, tone(GREEN, f), 'VEG-HOJAS', details=[(v, 'VEG-NERVIOS')], z=sp['z'])
    # ---- alzado
    E = Scene()
    top = pot_elev_terracotta(E, 380, 290, 350)
    leaves = [  # (x, y, angulo, L, ancho aparente, z, x_tallo)
        (-400, 560, 205, 320, 0.7, 1, -30),
        (-330, 720, 195, 380, 0.9, 3, -20),
        (-230, 960, 150, 350, 0.8, 2, -10),
        (-40, 1060, 100, 300, 0.62, 2, 0),
        (190, 1010, 42, 330, 0.72, 2.5, 15),
        (300, 780, -12, 400, 0.95, 3, 25),
        (420, 560, -30, 300, 0.7, 1, 40),
        (-130, 560, 238, 300, 0.78, 12, -15),
        (150, 580, -55, 300, 0.8, 13, 20),
        (40, 840, 72, 270, 0.85, 14, 5),
    ]
    for (x, y, a, L, f, z, xs) in leaves:
        leaf, veins = monstera_leaf(L, rng, 6 if L > 300 else 4)
        k = rng.uniform(-4e-4, 4e-4)
        g = xform(leaf, x, y, a, k=k, sy=f, seg=10)
        v = xform(veins, x, y, a, k=k, sy=f, seg=10)
        pts = bezier((xs, top - 5), (xs + 0.15 * (x - xs), top + 0.8 * (y - top)), (x, y), 30)
        stem = LineString(pts).buffer(8, cap_style=1).difference(
            box(-1e4, -1e4, 1e4, top - 1))
        E.add(stem, tone(GREEN_STEM, -0.05), 'VEG-HOJAS', z=z - 0.05)
        ff = -0.18 + 0.12 * min(z, 4) / 4 + (0.08 if z > 10 else 0)
        E.add(g, tone(GREEN, ff), 'VEG-HOJAS', details=[(v, 'VEG-NERVIOS')], z=z)
    return dict(key='Monstera', name='MONSTERA', latin='Monstera deliciosa',
                pot='maceta de barro', plan=P, elev=E)


FIDDLE_HALF = [(1.0, 0.0), (0.985, 0.08), (0.95, 0.19), (0.87, 0.29),
               (0.75, 0.325), (0.63, 0.29), (0.53, 0.235), (0.42, 0.225),
               (0.28, 0.225), (0.14, 0.18), (0.04, 0.10), (0.0, 0.0)]


def fiddle_leaf(L, rng):
    leaf = leaf_from_half(FIDDLE_HALF, L, wf=rng.uniform(0.9, 1.08),
                          asym=rng.uniform(-0.08, 0.08))
    veins = pinnate_veins(leaf, L, 6, 0.1, 0.8, 58, 0.85, 0.0, 0.93)
    return leaf, veins


def ficus():
    rng = random.Random(21)
    P = Scene()
    pot_plan_round(P, 200, CREAM, rim=14, scallop=24, z=0)
    specs = []
    for tier, (n, r0, L0, z0) in enumerate(((10, (170, 230), (240, 280), 1),
                                            (9, (80, 150), (220, 260), 2),
                                            (7, (0, 60), (190, 230), 3))):
        off = rng.uniform(0, 360)
        for i in range(n):
            a = off + 360 * i / n + rng.uniform(-10, 10)
            specs.append((a, rng.uniform(*r0), rng.uniform(*L0), z0 + rng.random() * 0.9))
    for (a, r0, L, z) in specs:
        leaf, veins = fiddle_leaf(L, rng)
        ang = a + rng.uniform(-18, 18)
        k = rng.uniform(-8e-4, 8e-4)
        x0, y0 = r0 * math.cos(rad(a)), r0 * math.sin(rad(a))
        g = xform(leaf, x0, y0, ang, k=k, seg=10)
        v = xform(veins, x0, y0, ang, k=k, seg=10)
        P.add(g, tone(GREEN_DEEP, -0.14 + 0.1 * (z - 1)), 'VEG-HOJAS',
              details=[(v, 'VEG-NERVIOS')], z=z)
    # ---- alzado
    E = Scene()
    top = pot_elev_ribbed(E, 400, 340, 400)
    trunk_pts = catmull([(0, top - 30), (10, 700), (-8, 1050), (6, 1380), (0, 1580)], 10)
    tp = Path(trunk_pts)
    trunk = tapered(trunk_pts, 42, 16).difference(below_rim(200, top))
    E.add(trunk, TRUNK, 'VEG-TRONCO',
          details=[(LineString([(p[0] - 6, p[1]) for p in trunk_pts[6:30]]),
                    'VEG-TRONCO', 9)], z=5)
    # hojas en espiral (filotaxis): las que miran al observador van delante
    n = 26
    for i in range(n):
        u = i / (n - 1)
        s_ = (0.34 + 0.64 * u) * tp.L
        x, y, _ = tp.at(s_)
        phi = rad(i * 137.5 + 20)
        beta = rad(-12 + 62 * u + rng.uniform(-10, 10))
        hx = math.cos(beta) * math.cos(phi)
        a = math.degrees(math.atan2(math.sin(beta), hx))
        sx = max(0.55, math.hypot(hx, math.sin(beta)))
        L = (320 - 110 * u) * rng.uniform(0.92, 1.08)
        z = 5 - 4 * math.sin(phi) + rng.uniform(-0.2, 0.2)
        leaf, veins = fiddle_leaf(L, rng)
        k = rng.uniform(-6e-4, 6e-4)
        f = rng.uniform(0.65, 1.0)
        px, py = x + 30 * sx * math.cos(rad(a)), y + 30 * sx * math.sin(rad(a))
        pet = LineString([(x, y), (px, py)]).buffer(4, cap_style=1)
        E.add(pet, GREEN_STEM, 'VEG-HOJAS', z=z - 0.01)
        g = xform(leaf, px, py, a, k=k, sx=sx, sy=f, seg=10)
        v = xform(veins, px, py, a, k=k, sx=sx, sy=f, seg=10)
        E.add(g, tone(GREEN_DEEP, -0.2 + 0.04 * z), 'VEG-HOJAS',
              details=[(v, 'VEG-NERVIOS')], z=z)
    for a in (72, 96, 118):
        leaf, veins = fiddle_leaf(rng.uniform(190, 215), rng)
        x, y, _ = tp.at(tp.L)
        g = xform(leaf, x, y - 12, a, sy=0.8, seg=10)
        v = xform(veins, x, y - 12, a, sy=0.8, seg=10)
        E.add(g, tone(GREEN_DEEP, 0.12), 'VEG-HOJAS', details=[(v, 'VEG-NERVIOS')],
              z=10 + a / 1000)
    return dict(key='Ficus_lyrata', name='FICUS LYRATA', latin='Ficus lyrata',
                pot='macetero de ceramica estriada', plan=P, elev=E)


def pinna(l, w, a=0.6, b=1.2):
    return profile_leaf(l, w, a, b, 16)


def palm_frond_plan(L, rng, lmax=170, w=17, spacing=26, ang=52):
    parts = [LineString([(0, 0), (L, 0)]).buffer(5, cap_style=1)]
    s0 = 0.18 * L
    n = int((0.985 * L - s0) / spacing)
    for i in range(n + 1):
        s = s0 + i * spacing
        u = (s - s0) / (0.985 * L - s0)
        l = lmax * (0.35 + 0.65 * math.sin(math.pi * min(1.0, u * 1.02)) ** 0.8)
        for side in (1, -1):
            parts.append(xform(pinna(l, w), s, 0, side * (ang + rng.uniform(-6, 6)),
                               k=-side * 1.2e-3, seg=8))
    return unary_union(parts)


def kentia():
    rng = random.Random(33)
    P = Scene()
    pot_plan_round(P, 210, BASKET, rim=20, ticks=True, handles=True, z=0)
    fronds = []
    n = 8
    for i in range(n):
        fronds.append((360 * i / n + rng.uniform(-10, 10), rng.uniform(520, 640),
                       1 + rng.random()))
    for a in (20, 140, 260):
        fronds.append((a + rng.uniform(-15, 15), rng.uniform(360, 430), 3 + rng.random()))
    for (a, L, z) in fronds:
        fr = palm_frond_plan(L, rng)
        k = rng.uniform(-6e-4, 6e-4)
        g = xform(fr, 20 * math.cos(rad(a)), 20 * math.sin(rad(a)), a, k=k, seg=8)
        rach = xform(LineString([(0, 0), (L * 0.97, 0)]), 20 * math.cos(rad(a)),
                     20 * math.sin(rad(a)), a, k=k, seg=8)
        P.add(g, tone(GREEN_FRESH, -0.2 + 0.1 * (z - 1)), 'VEG-HOJAS',
              details=[(rach, 'VEG-NERVIOS')], z=z)
    # ---- alzado
    E = Scene()
    top = pot_elev_basket(E, 420, 330, 390)
    specs = [  # (x0, angulo inicial, longitud, giro, z)
        (-30, 142, 950, 80, 1), (25, 38, 980, -80, 1),
        (-15, 116, 1320, 105, 2), (15, 66, 1300, -105, 2),
        (-8, 100, 1450, 85, 3), (8, 82, 1400, -90, 3),
        (0, 91, 1150, 25, 4),
        (-35, 132, 1000, 85, 12), (35, 48, 1020, -85, 12),
    ]
    for (x0, th, L, turn, z) in specs:
        path = Path(arch_path(x0, top - 30, th, L, turn, power=2.0))
        parts = [tapered(path.P, 16, 6)]
        s = 0.3 * L
        while s < 0.985 * L:
            u = (s - 0.3 * L) / (0.685 * L)
            l = 100 + 160 * math.sin(math.pi * min(1.0, u * 1.02)) ** 0.7
            x, y, t = path.at(s)
            c = math.cos(rad(t))
            if c > 0.25:        # la fronda va hacia la derecha: foliolos colgando
                dirs = (t - 0.3 * (t + 90), t - 0.58 * (t + 90))
            elif c < -0.25:     # hacia la izquierda
                dirs = (t + 0.3 * (270 - t), t + 0.58 * (270 - t))
            else:               # tramo casi vertical: en V
                dirs = (t - 48, t + 48)
            for d in dirs:
                d += rng.uniform(-5, 5)
                kk = -1.6e-3 if math.cos(rad(d)) > 0 else 1.6e-3
                parts.append(xform(pinna(l, 17), x, y, d, k=kk, seg=8))
            s += 30
        fr = unary_union(parts).difference(below_rim(215, top))
        E.add(fr, tone(GREEN_FRESH, -0.22 + 0.04 * min(z, 5)), 'VEG-HOJAS',
              details=[(path.line(), 'VEG-NERVIOS')], z=z)
    return dict(key='Kentia', name='KENTIA', latin='Howea forsteriana',
                pot='cesta de fibra', plan=P, elev=E)


STRELITZIA_HALF = [(1.0, 0.0), (0.97, 0.10), (0.88, 0.17), (0.70, 0.205),
                   (0.45, 0.205), (0.22, 0.18), (0.08, 0.12), (0.01, 0.04),
                   (0.0, 0.0)]


def strelitzia_leaf(L, rng):
    leaf = leaf_from_half(STRELITZIA_HALF, L, asym=rng.uniform(-0.05, 0.05))
    cuts = []
    for side in (1, -1):
        for _ in range(rng.choice([0, 1, 2, 2, 3])):
            x = rng.uniform(0.2, 0.85) * L
            hw = half_width(leaf, x, side)
            depth = rng.uniform(0.45, 0.85) * hw
            th = rad(rng.uniform(64, 76))
            d = np.array([math.cos(th), side * math.sin(th)])
            a = np.array([x, side * (hw - depth)])
            b = a + d * hw * 1.5
            nr = np.array([-d[1], d[0]])
            cuts.append(Polygon([a + nr * 0.8, b + nr * 3.5, b - nr * 3.5, a - nr * 0.8]))
    if cuts:
        leaf = largest(leaf.difference(unary_union(cuts)))
    veins = pinnate_veins(leaf, L, 13, 0.08, 0.9, 64, 0.95, 0.0, 0.96)
    return leaf, veins


def strelitzia():
    rng = random.Random(44)
    P = Scene()
    pot_plan_round(P, 225, CONCRETE, rim=14, z=0)
    specs = []
    n = 7
    for i in range(n):
        specs.append((360 * i / n + rng.uniform(-12, 12), rng.uniform(170, 240),
                      rng.uniform(400, 460), 1.0, 1 + rng.random()))
    for a in (60, 190, 300):
        specs.append((a + rng.uniform(-20, 20), rng.uniform(60, 110),
                      rng.uniform(380, 430), 0.55, 3 + rng.random()))
    for (a, r0, L, sx, z) in specs:
        leaf, veins = strelitzia_leaf(L, rng)
        ang = a + rng.uniform(-8, 8)
        x0, y0 = r0 * math.cos(rad(a)), r0 * math.sin(rad(a))
        k = rng.uniform(-5e-4, 5e-4)
        g = xform(leaf, x0, y0, ang, k=k, sx=sx, seg=10)
        v = xform(veins, x0, y0, ang, k=k, sx=sx, seg=10)
        stem = LineString([(0, 0), (x0 + 20 * math.cos(rad(ang)),
                                    y0 + 20 * math.sin(rad(ang)))]).buffer(8, cap_style=2)
        P.add(stem, GREEN_STEM, 'VEG-HOJAS', z=z - 0.01)
        P.add(g, tone(GREEN_DEEP, -0.12 + 0.08 * (z - 1)), 'VEG-HOJAS',
              details=[(v, 'VEG-NERVIOS')], z=z)
    E = Scene()
    top = pot_elev_cylinder(E, 440, 440, pores=26)
    specs = [  # (x0, angulo peciolo, longitud peciolo, giro hoja, L, ancho, z)
        (-40, 128, 520, 30, 600, 0.8, 1), (40, 52, 540, -30, 620, 0.85, 1),
        (-25, 112, 760, 16, 650, 0.55, 2), (25, 70, 780, -16, 660, 0.9, 2),
        (-10, 99, 900, 8, 620, 0.35, 3), (10, 85, 880, -8, 640, 0.7, 3),
        (0, 92, 620, 2, 520, 0.22, 3.5),
        (-30, 140, 420, 36, 560, 1.0, 12), (30, 40, 430, -36, 580, 0.75, 12),
        (5, 78, 640, -12, 600, 0.95, 11),
    ]
    for (x0, a, pl, turn, L, f, z) in specs:
        path = Path(arch_path(x0, top - 20, a, pl, turn * 0.25, 24))
        x, y, t = path.at(path.L)
        stem = tapered(path.P, 22, 12, False).difference(below_rim(225, top))
        E.add(stem, tone(GREEN_STEM, -0.08), 'VEG-HOJAS', z=z - 0.02)
        leaf, veins = strelitzia_leaf(L, rng)
        k = rng.uniform(-5e-4, 5e-4)
        ang = t + turn
        g = xform(leaf, x, y, ang, k=k, sy=f, seg=10)
        v = xform(veins, x, y, ang, k=k, sy=f, seg=10)
        E.add(g, tone(GREEN_DEEP, -0.14 + 0.04 * min(z, 5)), 'VEG-HOJAS',
              details=[(v, 'VEG-NERVIOS')], z=z)
    return dict(key='Strelitzia', name='AVE DEL PARAISO', latin='Strelitzia nicolai',
                pot='macetero de hormigon', plan=P, elev=E)


def sansevieria():
    rng = random.Random(55)
    P = Scene()
    pot_plan_round(P, 145, WHITE, rim=10, z=0)
    n = 7
    for i in range(n):
        a = 360 * i / n + rng.uniform(-12, 12)
        L = rng.uniform(120, 160)
        blade = profile_leaf(L, rng.uniform(52, 64), 0.5, 0.9)
        r0 = rng.uniform(25, 45)
        g = xform(blade, r0 * math.cos(rad(a)), r0 * math.sin(rad(a)), a + rng.uniform(-15, 15))
        edge = g.difference(g.buffer(-5))
        P.add(g, tone(SANSE, 0.06), 'VEG-HOJAS', subfills=[(edge, SANSE_EDGE)], z=1)
    for i in range(7):
        r, a = rng.uniform(0, 55), rng.uniform(0, 360)
        g = ellipse(r * math.cos(rad(a)), r * math.sin(rad(a)), rng.uniform(30, 40),
                    rng.uniform(7, 11), a + 90 + rng.uniform(-35, 35), 32)
        edge = g.difference(g.buffer(-3))
        P.add(g, SANSE, 'VEG-HOJAS', subfills=[(edge, SANSE_EDGE)], z=2 + rng.random())
    E = Scene()
    top = pot_elev_legs(E, 290, 260, 190)
    specs = [  # (x, angulo, alto, ancho, z)  angulo > 90 = inclinada a la izquierda
        (-35, 95, 760, 86, 1), (35, 87, 700, 84, 1.2), (0, 91, 600, 80, 1.5),
        (-78, 101, 620, 78, 2), (78, 80, 640, 80, 2.2),
        (-112, 108, 480, 70, 3), (112, 73, 500, 70, 3.2),
        (-50, 99, 440, 72, 4), (55, 83, 460, 72, 4.2)]
    for i, (x, ang, H, W, z) in enumerate(specs):
        blade = profile_leaf(H, W, 0.5, 0.85, 32)
        bands = []
        yy = rng.uniform(20, 40)
        while yy < H * 0.9:
            pts = [(yy + 6 * math.sin(j * 1.3 + i), -W / 2 + W * j / 12) for j in range(13)]
            bands.append(LineString(pts))
            yy += rng.uniform(38, 55)
        k = (1 if ang > 90 else -1) * rng.uniform(0, 3e-4)
        g = xform(blade, x, top - 40, ang, k=k, seg=10)
        b = xform(MultiLineString(bands), x, top - 40, ang, k=k, seg=6)
        edge = g.difference(g.buffer(-6))
        E.add(g, tone(SANSE, -0.08 + 0.06 * (i % 3)), 'VEG-HOJAS',
              details=[(b.intersection(g.buffer(-7)), 'VEG-NERVIOS')],
              subfills=[(edge, SANSE_EDGE)], z=z)
    # la maceta se dibuja antes en la lista pero debe quedar delante
    for it in E.items:
        if it.edge == 'VEG-MACETA':
            it.z += 20
    return dict(key='Sansevieria', name='SANSEVIERIA', latin='Dracaena trifasciata',
                pot='macetero con patas', plan=P, elev=E)


def flower_plan(sc, x, y, r, n=6, z=50.0, rot=0.0, color=PINK):
    petals = [ellipse(x + r * 0.55 * math.cos(rad(rot + 360 * i / n)),
                      y + r * 0.55 * math.sin(rad(rot + 360 * i / n)),
                      r * 0.55, r * 0.3, rot + 360 * i / n, 20) for i in range(n)]
    sc.add(unary_union(petals), color, 'VEG-FLOR', z=z)
    sc.add(circle(x, y, r * 0.28, 20), YELLOW, 'VEG-FLOR', z=z + 0.01)


def scallop_disc(x, y, R, n, depth=0.05):
    pts = [(x + R * (1 - depth * (1 - abs(math.cos(n * t / 2)))) * math.cos(t),
            y + R * (1 - depth * (1 - abs(math.cos(n * t / 2)))) * math.sin(t))
           for t in np.linspace(0, 2 * math.pi, 14 * n, endpoint=False)]
    return Polygon(pts)


def cactus_top(sc, x, y, R, n, fill, z, spines=True):
    disc = scallop_disc(x, y, R, n)
    lines = []
    for i in range(n):
        t = 2 * math.pi * (i + 0.5) / n
        lines.append(LineString([(x + 0.3 * R * math.cos(t), y + 0.3 * R * math.sin(t)),
                                 (x + 0.93 * R * math.cos(t), y + 0.93 * R * math.sin(t))]))
        if spines:
            t2 = 2 * math.pi * i / n
            for dt in (-0.18, 0.18):
                lines.append(LineString([
                    (x + R * math.cos(t2), y + R * math.sin(t2)),
                    (x + (R + 0.16 * R) * math.cos(t2 + dt),
                     y + (R + 0.16 * R) * math.sin(t2 + dt))]))
    sc.add(disc, fill, 'VEG-HOJAS', details=[(MultiLineString(lines).intersection(
        disc.buffer(0.2 * R)), 'VEG-NERVIOS')], z=z)


def cactus():
    rng = random.Random(66)
    P = Scene()
    pot_plan_round(P, 135, TERRACOTTA, rim=12, saucer=14, z=0)
    arms = [(205, 118, 42), (28, 122, 38)]
    for (a, d, r) in arms:
        cx, cy = d * math.cos(rad(a)), d * math.sin(rad(a))
        band = LineString([(0.5 * cx, 0.5 * cy), (cx, cy)]).buffer(r * 0.8, cap_style=2)
        P.add(band, tone(GREEN, -0.12), 'VEG-HOJAS', z=1)
        cactus_top(P, cx, cy, r, 9, tone(GREEN, -0.04), 2)
    cactus_top(P, 0, 0, 72, 12, GREEN, 3)
    flower_plan(P, 8, 6, 30, 6, z=5)
    E = Scene()
    top = pot_elev_terracotta(E, 270, 200, 230)
    soil = top - 20
    main_path = [(0, soil), (0, 830)]
    main = LineString(main_path).buffer(70, cap_style=1).difference(
        box(-1e4, -1e4, 1e4, soil))
    armL = catmull([(-40, 430), (-100, 440), (-122, 490), (-122, 640)], 10)
    armR = catmull([(40, 540), (108, 548), (126, 600), (126, 720)], 10)
    for pts, r in ((armL, 40), (armR, 36)):
        g = LineString(pts).buffer(r, cap_style=1, join_style=1)
        rib = [LineString(pts).offset_curve(r * f) for f in (-0.55, 0, 0.55)]
        E.add(g, tone(GREEN, -0.08), 'VEG-HOJAS',
              details=[(MultiLineString([list(l.coords) for l in rib if not l.is_empty]
                                        ).intersection(g.buffer(-4)), 'VEG-NERVIOS')], z=1)
    ribs = [LineString([(dx, soil), (dx, 900)]) for dx in (-48, -24, 0, 24, 48)]
    spine = []
    for dx in (-48, -24, 0, 24, 48):
        for y in np.arange(soil + 40, 880, 55):
            spine.append(LineString([(dx - 5, y + 5), (dx, y), (dx + 5, y + 5)]))
    E.add(main, GREEN, 'VEG-HOJAS',
          details=[(MultiLineString(ribs).intersection(main.buffer(-5)), 'VEG-NERVIOS'),
                   (MultiLineString(spine).intersection(main.buffer(-3)), 'VEG-NERVIOS')],
          z=2)
    for i, a in enumerate((35, 62, 90, 118, 145)):
        p = ellipse(0 + 20 * math.cos(rad(a)), 895 + 20 * math.sin(rad(a)),
                    24, 11, a, 20)
        E.add(p, tone(PINK, -0.06 if i % 2 else 0.05), 'VEG-FLOR', z=5 + (i in (1, 3)) * 0.5)
    E.add(circle(0, 896, 8, 16), YELLOW, 'VEG-FLOR', z=7)
    for it in E.items:
        if it.edge == 'VEG-MACETA':
            it.z += 20
    return dict(key='Cactus', name='CACTUS', latin='Cereus / Carnegiea',
                pot='maceta de barro con plato', plan=P, elev=E)


def rosette_plan(sc, cx, cy, rings, base_col, z0, blush=True, rng=None):
    for ri, (n, L, W, off) in enumerate(rings):
        col = tone(base_col, -0.1 + 0.09 * ri)
        for i in range(n):
            a = off + 360 * i / n
            pet = profile_leaf(L, W, 1.3, 0.45, 20)
            g = xform(pet, cx + 3 * math.cos(rad(a)), cy + 3 * math.sin(rad(a)), a)
            subs = []
            if blush:
                tip = (cx + (L + 3) * math.cos(rad(a)), cy + (L + 3) * math.sin(rad(a)))
                subs.append((circle(*tip, W * 0.35, 16), (214, 150, 164)))
            sc.add(g, col, 'VEG-HOJAS', subfills=subs, z=z0 + ri + (i % 2) * 0.1)


def haworthia_plan(sc, cx, cy, z0):
    for ri, (n, L, W, off) in enumerate(((8, 50, 16, 0), (7, 38, 14, 25), (5, 24, 12, 10))):
        for i in range(n):
            a = off + 360 * i / n
            leaf = profile_leaf(L, W, 0.4, 1.0, 16)
            st = MultiLineString([[(L * t, -W * 0.28 * (1 - t)), (L * t, W * 0.28 * (1 - t))]
                                  for t in (0.3, 0.5, 0.7)])
            g = xform(leaf, cx, cy, a)
            s_ = xform(st, cx, cy, a)
            sc.add(g, tone(HAWOR, -0.08 + 0.08 * ri), 'VEG-HOJAS',
                   details=[(s_, 'VEG-NERVIOS')], z=z0 + ri)


def ball_cactus_plan(sc, cx, cy, R, z0):
    disc = circle(cx, cy, R, 64)
    dots = []
    ga = math.pi * (3 - math.sqrt(5))
    for i in range(1, 60):
        r = R * 0.95 * math.sqrt(i / 60)
        t = i * ga
        dots.append(circle(cx + r * math.cos(t), cy + r * math.sin(t), 1.6, 8).exterior)
    sc.add(disc, tone(GREEN, 0.05), 'VEG-HOJAS',
           details=[(MultiLineString([list(d.coords) for d in dots]), 'VEG-NERVIOS', 9)],
           z=z0)
    for i in range(7):
        t = 360 * i / 7
        flower_plan(sc, cx + R * 0.62 * math.cos(rad(t)), cy + R * 0.62 * math.sin(rad(t)),
                    11, 5, z=z0 + 1, rot=t)


def suculentas():
    P = Scene()
    tray = rounded(box(-245, -92, 245, 92), 30)
    P.add(tray, WOOD, 'VEG-MACETA', z=0)
    for (x, R, col) in ((-155, 68, TERRACOTTA), (0, 58, WHITE), (155, 62, CONCRETE)):
        g = circle(x, 0, R, 64)
        P.add(g, col, 'VEG-MACETA', z=1)
        P.add(circle(x, 0, R - 8, 64), SOIL, 'VEG-MACETA', z=1.05)
    rosette_plan(P, -155, 0, [(11, 60, 36, 0), (8, 46, 30, 16), (6, 30, 22, 5),
                              (4, 16, 14, 40)], SUCC, 2)
    haworthia_plan(P, 0, 0, 2)
    ball_cactus_plan(P, 155, 0, 46, 2)
    E = Scene()
    E.add(rounded(box(-245, 0, 245, 22), 8), WOOD, 'VEG-MACETA', z=20)
    # macetas
    t_top = 22 + 112
    E.add(rounded(Polygon([(-155 - 52, 22), (-155 + 52, 22), (-155 + 64, t_top - 16),
                           (-155 - 64, t_top - 16)]), 4), TERRACOTTA, 'VEG-MACETA', z=20)
    E.add(rounded(box(-155 - 69, t_top - 18, -155 + 69, t_top), 4),
          tone(TERRACOTTA, -0.07), 'VEG-MACETA', z=20.1)
    w_top = 22 + 100
    E.add(rounded(box(-56, 22, 56, w_top), 10).union(box(-56, w_top - 20, 56, w_top)),
          WHITE, 'VEG-MACETA', subfills=[(box(-56, 44, 56, 56), (240, 196, 186))], z=20)
    c_top = 22 + 86
    bowl = Polygon(catmull([(155 - 62, c_top), (155 - 60, 60), (155 - 44, 26),
                            (155 - 36, 22)], 8) +
                   catmull([(155 + 36, 22), (155 + 44, 26), (155 + 60, 60),
                            (155 + 62, c_top)], 8)).buffer(0)
    E.add(bowl, CONCRETE, 'VEG-MACETA', z=20)
    # echeveria en alzado: abanico de petalos
    cx, cy = -155, t_top - 8
    rings = [(9, 64, 30, 6, 172), (7, 50, 27, 18, 160), (5, 36, 22, 34, 146),
             (3, 22, 16, 60, 120)]
    for ri, (n, L, W, a0, a1) in enumerate(rings):
        for i, a in enumerate(np.linspace(a0, a1, n)):
            pet = profile_leaf(L, W, 1.3, 0.45, 20)
            g = xform(pet, cx, cy, a, sy=0.8)
            tip = (cx + (L + 2) * math.cos(rad(a)), cy + (L + 2) * math.sin(rad(a)))
            E.add(g, tone(SUCC, -0.1 + 0.09 * ri), 'VEG-HOJAS',
                  subfills=[(circle(*tip, W * 0.3, 16), (214, 150, 164))],
                  z=1 + ri + abs(a - 90) / 400)
    # haworthia en alzado
    cx, cy = 0, w_top - 6
    for ri, (n, L, W, a0, a1) in enumerate(((7, 62, 16, 14, 166), (5, 54, 15, 32, 148),
                                            (3, 44, 14, 62, 118))):
        for a in np.linspace(a0, a1, n):
            leaf = profile_leaf(L, W, 0.4, 1.0, 16)
            st = MultiLineString([[(L * t, -W * 0.3 * (1 - t)), (L * t, W * 0.3 * (1 - t))]
                                  for t in (0.3, 0.5, 0.7)])
            E.add(xform(leaf, cx, cy, a), tone(HAWOR, -0.08 + 0.08 * ri), 'VEG-HOJAS',
                  details=[(xform(st, cx, cy, a), 'VEG-NERVIOS')], z=1 + ri + abs(a - 90) / 400)
    # cactus bola en alzado
    cx, cy, R = 155, c_top + 34, 48
    body = ellipse(cx, cy, R, R * 0.92, 0, 64)
    mer = []
    for lon in (-60, -30, 0, 30, 60):
        pts = [(cx + R * math.cos(rad(lat)) * math.sin(rad(lon)),
                cy + R * 0.92 * math.sin(rad(lat))) for lat in range(-90, 91, 6)]
        mer.append(pts)
    E.add(body, tone(GREEN, 0.05), 'VEG-HOJAS',
          details=[(MultiLineString(mer).intersection(body.buffer(-3)), 'VEG-NERVIOS')],
          z=1)
    for i, lon in enumerate((-50, -25, 0, 25, 50)):
        fx = cx + R * 0.72 * math.sin(rad(lon))
        fy = cy + R * 0.92 * math.cos(rad(lon)) * 0.95
        for j, a in enumerate((50, 90, 130)):
            E.add(ellipse(fx + 6 * math.cos(rad(a)), fy + 6 * math.sin(rad(a)), 7, 3.5, a, 16),
                  tone(PINK, 0.05 * (j - 1)), 'VEG-FLOR', z=3 + i * 0.01 + (j == 1) * 0.005)
    return dict(key='Suculentas', name='TRIO DE SUCULENTAS',
                latin='Echeveria · Haworthia · Mammillaria',
                pot='bandeja con tres macetitas', plan=P, elev=E)


def fern_frond(L, rng, pmax=40, w=10, spacing=12, ang=72):
    parts = [LineString([(0, 0), (L, 0)]).buffer(2.5, cap_style=1)]
    s = 0.1 * L
    i = 0
    while s < 0.97 * L:
        u = (s - 0.1 * L) / (0.87 * L)
        l = 10 + pmax * math.sin(math.pi * u ** 0.8) ** 0.9
        side = 1 if i % 2 == 0 else -1
        for sd in (side, -side):
            parts.append(xform(profile_leaf(l, w, 0.6, 0.7, 12), s + (sd == -side) * spacing / 2, 0,
                               sd * (ang + rng.uniform(-6, 6))))
        s += spacing
        i += 1
    return unary_union(parts)


def helecho():
    rng = random.Random(77)
    P = Scene()
    pot_plan_round(P, 160, BLUE, rim=12, z=0)
    n = 24
    for i in range(n):
        a = 360 * i / n + rng.uniform(-6, 6)
        L = rng.uniform(290, 400) if i % 3 else rng.uniform(220, 280)
        r0 = rng.uniform(5, 35)
        k = rng.choice((-1, 1)) * rng.uniform(0.6e-3, 2.2e-3)
        fr = fern_frond(L, rng)
        x0, y0 = r0 * math.cos(rad(a)), r0 * math.sin(rad(a))
        g = xform(fr, x0, y0, a, k=k, seg=6)
        rach = xform(LineString([(0, 0), (L * 0.96, 0)]), x0, y0, a, k=k, seg=6)
        z = 1 + (400 - L) / 180 + rng.random() * 0.5
        P.add(g, tone(GREEN_FRESH, -0.22 + 0.1 * (z - 1)), 'VEG-HOJAS',
              details=[(rach, 'VEG-NERVIOS')], z=z)
    E = Scene()
    top = pot_elev_bowl(E, 320, 280)
    for i in range(20):
        th = 18 + 144 * i / 19 + rng.uniform(-6, 6)
        right = math.cos(rad(th)) > 0
        L = rng.uniform(380, 560) if abs(th - 90) > 25 else rng.uniform(320, 420)
        turn = (-1 if right else 1) * rng.uniform(80, 150) * (abs(math.cos(rad(th))) + 0.35)
        x0 = rng.uniform(-60, 60)
        path = Path(arch_path(x0, top - 20, th, L, turn, 40, 1.4))
        parts = [path.line().buffer(2.8, cap_style=1)]
        s, j = 0.08 * L, 0
        while s < 0.97 * L:
            u = (s - 0.08 * L) / (0.89 * L)
            l = 10 + 36 * math.sin(math.pi * u ** 0.8) ** 0.9
            x, y, t = path.at(s)
            for sd in (1, -1):
                parts.append(xform(profile_leaf(l, 9, 0.6, 0.7, 12), x, y,
                                   t + sd * (72 + rng.uniform(-6, 6))))
            s += 12
            j += 1
        fr = unary_union(parts).difference(below_rim(160, top))
        z = 12 if (i % 3 == 0) else 1 + rng.random()
        E.add(fr, tone(GREEN_FRESH, -0.22 + 0.07 * min(z, 3)), 'VEG-HOJAS',
              details=[(path.line(), 'VEG-NERVIOS')], z=z)
    return dict(key='Helecho', name='HELECHO', latin='Nephrolepis exaltata',
                pot='macetero de ceramica esmaltada', plan=P, elev=E)


POTHOS_HALF = [(1.0, 0.0), (0.86, 0.13), (0.64, 0.28), (0.40, 0.36), (0.18, 0.35),
               (0.02, 0.26), (-0.06, 0.13), (-0.03, 0.04), (0.03, 0.0)]


def pothos_leaf(L, rng):
    leaf = leaf_from_half(POTHOS_HALF, L, asym=rng.uniform(-0.1, 0.1))
    veins = pinnate_veins(leaf, L, 3, 0.2, 0.6, 50, 0.7, 0.04, 0.9)
    streak = xform(profile_leaf(L * 0.5, L * 0.07, 0.8, 0.8, 12), L * 0.25,
                   rng.uniform(-0.15, 0.15) * L, rng.uniform(-20, 20)).intersection(leaf)
    return leaf, veins, streak


def vine(sc, path, rng, z, L0=(55, 75), step=46, s_start=20, pot_clip=None):
    stem = path.line().buffer(3, cap_style=1)
    if pot_clip is not None:
        stem = stem.difference(pot_clip)
    sc.add(stem, tone(GREEN_STEM, -0.1), 'VEG-HOJAS', z=z - 0.02)
    s, i = s_start, 0
    while s < path.L - 10:
        x, y, t = path.at(s)
        sd = 1 if i % 2 == 0 else -1
        a = t + sd * rng.uniform(35, 60)
        L = rng.uniform(*L0) * (0.75 + 0.25 * min(1, s / 200))
        leaf, veins, streak = pothos_leaf(L, rng)
        g = xform(leaf, x, y, a)
        sc.add(g, tone(GREEN, -0.1 + rng.uniform(-0.06, 0.08)), 'VEG-HOJAS',
               details=[(xform(veins, x, y, a), 'VEG-NERVIOS')],
               subfills=[(xform(streak, x, y, a), (206, 214, 150))], z=z + rng.random() * 0.1)
        s += step * rng.uniform(0.8, 1.2)
        i += 1


def pothos():
    rng = random.Random(88)
    P = Scene()
    pot_plan_round(P, 115, TERRACOTTA, rim=10, z=0)
    for i in range(7):
        a = 360 * i / 7 + rng.uniform(-12, 12)
        r1 = rng.uniform(20, 60)
        r2 = rng.uniform(220, 330)
        pts = []
        for j in range(6):
            u = j / 5
            r = r1 + (r2 - r1) * u
            aa = a + 22 * math.sin(u * 3 + i) * u
            pts.append((r * math.cos(rad(aa)), r * math.sin(rad(aa))))
        vine(P, Path(catmull(pts, 8)), rng, 1 + rng.random())
    for i in range(4):
        a = rng.uniform(0, 360)
        leaf, veins, streak = pothos_leaf(rng.uniform(60, 75), rng)
        x0, y0 = 15 * math.cos(rad(a)), 15 * math.sin(rad(a))
        P.add(xform(leaf, x0, y0, a), tone(GREEN, 0.02), 'VEG-HOJAS',
              details=[(xform(veins, x0, y0, a), 'VEG-NERVIOS')],
              subfills=[(xform(streak, x0, y0, a), (206, 214, 150))], z=3)
    cords = [LineString([(0, 0), (108 * math.cos(rad(a)), 108 * math.sin(rad(a)))]).buffer(2.2)
             for a in (90, 210, 330)]
    P.add(unary_union(cords), CORD, 'VEG-MACETA', z=10)
    P.add(circle(0, 0, 12, 24).difference(circle(0, 0, 7, 24)), (170, 170, 170),
          'VEG-MACETA', z=10.1)
    # ---- alzado (punto base en el gancho)
    E = Scene()
    E.add(circle(0, -16, 16, 24).difference(circle(0, -16, 10, 24)), (170, 170, 170),
          'VEG-MACETA', z=30)
    rim_y, bot_y = -620, -780
    pot_poly = Polygon(catmull([(-112, rim_y - 14), (-110, -690), (-86, -752),
                                (-56, bot_y)], 8) +
                       catmull([(56, bot_y), (86, -752), (110, -690),
                                (112, rim_y - 14)], 8)).buffer(0)
    rim = rounded(box(-120, rim_y - 20, 120, rim_y), 5)
    E.add(pot_poly, TERRACOTTA, 'VEG-MACETA', z=20)
    E.add(rim, tone(TERRACOTTA, -0.07), 'VEG-MACETA', z=20.1)
    knot = (0, -300)
    cords = []
    for xr in (-104, -20, 104):
        cords.append(LineString([knot, (xr, rim_y - 6)]))
    cords.append(LineString([(0, -30), knot]))
    net = [LineString([(-104, rim_y - 6), (-60, -700), (0, -760), (60, -700), (104, rim_y - 6)]),
           LineString([(-20, rim_y - 6), (-60, -700)]), LineString([(-20, rim_y - 6), (60, -700)]),
           LineString([(-60, -700), (-30, -790)]), LineString([(60, -700), (30, -790)]),
           LineString([(0, -760), (0, -800)])]
    cg = unary_union([c.buffer(2.4) for c in cords + net])
    E.add(cg, CORD, 'VEG-MACETA', z=25)
    E.add(ellipse(0, -300, 9, 12, 0, 16), tone(CORD, -0.1), 'VEG-MACETA', z=25.1)
    E.add(rounded(box(-12, -815, 12, -790), 4), tone(CORD, -0.1), 'VEG-MACETA', z=25.1)
    tas = unary_union([LineString([(x, -815), (x * 1.6, -900)]).buffer(1.6)
                       for x in (-9, -4.5, 0, 4.5, 9)])
    E.add(tas, CORD, 'VEG-MACETA', z=25)
    pot_mask = pot_poly.union(rim)
    for i, (x0, dx, yend, z) in enumerate(((-100, -70, -1330, 1), (-60, -30, -1180, 26),
                                           (-20, 10, -1450, 1.5), (30, 40, -1260, 26.5),
                                           (80, 90, -1400, 1.2), (105, 150, -1150, 26.2),
                                           (-110, -150, -1080, 26.8))):
        pts = [(x0, rim_y - 4), (x0 + dx * 0.5, rim_y + 18), (x0 + dx, rim_y - 60)]
        y = rim_y - 60
        xx = x0 + dx
        while y > yend:
            y -= 110
            xx += rng.uniform(-30, 30)
            pts.append((xx, y))
        path = Path(catmull(pts, 8))
        vine(E, path, rng, z, step=50, s_start=30,
             pot_clip=None if z > 20 else pot_mask)
    for a in (70, 100, 125):
        leaf, veins, streak = pothos_leaf(rng.uniform(62, 72), rng)
        x0 = 30 * math.cos(rad(a))
        E.add(xform(leaf, x0, rim_y - 10, a), tone(GREEN, -0.04), 'VEG-HOJAS',
              details=[(xform(veins, x0, rim_y - 10, a), 'VEG-NERVIOS')],
              subfills=[(xform(streak, x0, rim_y - 10, a), (206, 214, 150))], z=2)
    return dict(key='Pothos_colgante', name='POTHOS COLGANTE', latin='Epipremnum aureum',
                pot='maceta colgante de macrame', plan=P, elev=E, hanging=True)


def cloud(cx, cy, R, rng, nb=9):
    parts = [circle(cx, cy, R * 0.72, 64)]
    for i in range(nb):
        t = 2 * math.pi * i / nb + rng.uniform(-0.2, 0.2)
        d = R * rng.uniform(0.6, 0.7)
        parts.append(circle(cx + d * math.cos(t), cy + d * math.sin(t),
                            R * rng.uniform(0.3, 0.38), 40))
    return unary_union(parts)


def olive_leaves(sc, region, rng, n, z, col):
    minx, miny, maxx, maxy = region.bounds
    placed = 0
    tries = 0
    while placed < n and tries < n * 20:
        tries += 1
        x, y = rng.uniform(minx, maxx), rng.uniform(miny, maxy)
        if not region.buffer(-12).contains(Point(x, y)):
            continue
        g = xform(profile_leaf(rng.uniform(34, 46), rng.uniform(7, 9), 0.8, 0.8, 12),
                  x, y, rng.uniform(0, 360))
        sc.add(g, tone(col, rng.uniform(-0.1, 0.12)), 'VEG-NERVIOS', z=z + rng.random() * 0.01)
        placed += 1


def olivo():
    rng = random.Random(99)
    P = Scene()
    pot_plan_square(P, 500, WOOD, z=0)
    base = cloud(0, 0, 480, rng, 11)
    P.add(base, tone(OLIVE, -0.12), 'VEG-HOJAS', z=1)
    olive_leaves(P, base, rng, 90, 1.2, OLIVE_LEAF)
    for (x, y, R) in ((-150, 120, 230), (160, 90, 210), (-60, -170, 220), (170, -170, 180)):
        c = cloud(x, y, R, rng, 8)
        P.add(c, OLIVE, 'VEG-HOJAS', z=2 + x / 1e4)
        olive_leaves(P, c, rng, 34, 2.2 + x / 1e4, OLIVE_LEAF)
    E = Scene()
    top = pot_elev_planter(E, 500, 440)
    tr = catmull([(0, top - 20), (-14, 700), (22, 950), (-10, 1180), (0, 1260)], 10)
    trunk = tapered(tr, 74, 34).difference(below_rim(250, top))
    fis = [LineString([(x + 10 * math.sin(y / 60), y) for x, y in tr[3:30]]),
           LineString([(x - 12 + 8 * math.sin(y / 45), y) for x, y in tr[6:34]])]
    E.add(trunk, TRUNK, 'VEG-TRONCO',
          details=[(MultiLineString(fis).intersection(trunk.buffer(-6)), 'VEG-TRONCO', 9)],
          z=5)
    branches = [((-5, 1150), (-150, 1300), (-300, 1400), 30, 12),
                ((0, 1200), (90, 1350), (280, 1440), 28, 12),
                ((-5, 1230), (-60, 1450), (-110, 1660), 26, 12),
                ((0, 1240), (60, 1450), (140, 1700), 24, 10),
                ((5, 1100), (120, 1180), (230, 1260), 20, 8)]
    for (p0, p1, p2, w0, w1) in branches:
        E.add(tapered(bezier(p0, p1, p2, 20), w0, w1), TRUNK, 'VEG-TRONCO', z=5.1)
    clusters = [(-320, 1420, 210, 1), (300, 1450, 200, 1), (-120, 1690, 230, 2),
                (150, 1720, 220, 2), (-190, 1290, 170, 8), (200, 1300, 165, 8),
                (10, 1500, 210, 9)]
    for (x, y, R, z) in clusters:
        c = cloud(x, y, R, rng, 9)
        col = tone(OLIVE, -0.12) if z < 5 else OLIVE
        E.add(c, col, 'VEG-HOJAS', z=z)
        olive_leaves(E, c, rng, 38, z + 0.2, OLIVE_LEAF)
    return dict(key='Olivo', name='OLIVO', latin='Olea europaea',
                pot='jardinera de madera', plan=P, elev=E)


def pilea_leaf(cx, cy, R, ang, sy=1.0, tilt=0.0):
    """Hoja redonda peltada: disco, punto de insercion del peciolo y nervios."""
    disc = Polygon([(R * math.cos(t) * (1 + 0.06 * max(0, math.cos(t)) ** 8), R * math.sin(t))
                    for t in np.linspace(0, 2 * math.pi, 72, endpoint=False)])
    dot = (-0.3 * R, 0)
    ven = MultiLineString([[dot, ((0.85 * R) * math.cos(t), (0.85 * R) * math.sin(t))]
                           for t in np.linspace(-2.2, 2.2, 5)])
    d = circle(dot[0], dot[1], R * 0.06, 12)
    g = xform(disc, cx, cy, ang, sy=sy)
    return g, xform(ven, cx, cy, ang, sy=sy), xform(d, cx, cy, ang, sy=sy)


def pilea():
    rng = random.Random(111)
    P = Scene()
    pot_plan_round(P, 95, WHITE, rim=8, saucer=12, z=0)
    specs = []
    for i in range(10):
        a = 36 * i + rng.uniform(-8, 8)
        specs.append((a, rng.uniform(120, 150), rng.uniform(36, 44), 1 + rng.random()))
    for i in range(6):
        a = 60 * i + 25 + rng.uniform(-10, 10)
        specs.append((a, rng.uniform(55, 85), rng.uniform(26, 34), 3 + rng.random()))
    specs.append((rng.uniform(0, 360), 10, 18, 5))
    for (a, r, R, z) in specs:
        cx, cy = r * math.cos(rad(a)), r * math.sin(rad(a))
        pet = LineString([(0, 0), (cx - 0.3 * R * math.cos(rad(a)),
                                   cy - 0.3 * R * math.sin(rad(a)))]).buffer(2.5)
        P.add(pet, GREEN_STEM, 'VEG-HOJAS', z=z - 0.01)
        g, v, d = pilea_leaf(cx, cy, R, a)
        P.add(g, tone(GREEN_FRESH, -0.12 + 0.07 * (z - 1)), 'VEG-HOJAS',
              details=[(v, 'VEG-NERVIOS')], subfills=[(d, tone(GREEN_STEM, -0.2))], z=z)
    E = Scene()
    E.add(rounded(Polygon([(-112, 0), (112, 0), (118, 14), (-118, 14)]), 3),
          tone(WHITE, -0.05), 'VEG-MACETA', z=20)
    E.add(rounded(Polygon([(-78, 12), (78, 12), (95, 142), (-95, 142)]), 8), WHITE,
          'VEG-MACETA', subfills=[(box(-120, 118, 120, 128), (242, 190, 170))], z=20)
    E.add(rounded(box(-100, 140, 100, 164), 5), tone(WHITE, -0.04), 'VEG-MACETA', z=20.1)
    top = 164
    stem = catmull([(0, top - 10), (5, 230), (-4, 300), (0, 350)], 8)
    E.add(tapered(stem, 12, 7), tone(GREEN_STEM, -0.1), 'VEG-HOJAS', z=5)
    sp = Path(stem)
    n = 17
    for i in range(n):
        u = i / (n - 1)
        nx, ny, _ = sp.at((0.08 + 0.92 * u) * sp.L)
        phi = rad(i * 137.5 + 40)
        beta = rad(-18 + 70 * u)
        ln = (175 - 105 * u) * rng.uniform(0.9, 1.1)
        hx = math.cos(beta) * math.cos(phi)
        ex, ey = nx + ln * hx, ny + ln * math.sin(beta) + 25 * (1 - u)
        R = (44 - 18 * u) * rng.uniform(0.92, 1.08)
        f = 0.32 + 0.5 * u + 0.15 * abs(math.sin(phi)) * (1 - u)
        t0 = math.degrees(math.atan(0.35 * math.sin(beta) / max(abs(hx), 0.2))) * 0.5
        tilt = t0 if hx > 0 else -t0
        z = 5 - 4 * math.sin(phi)
        g, v, d = pilea_leaf(ex, ey, R, 0, sy=f)
        # el peciolo se inserta en el punto (peltado), a 0.3R del centro
        ang = 0 if hx > 0 else 180
        g, v, d = (affinity.rotate(affinity.rotate(q, ang, origin=(ex, ey)), tilt,
                                   origin=(ex, ey)) for q in (g, v, d))
        dc = d.centroid
        pet = LineString(bezier((nx, ny), ((nx + dc.x) / 2, max(ny, dc.y) + 45 * (1 - u) + 10),
                                (dc.x, dc.y), 20)).buffer(2.2)
        E.add(pet, GREEN_STEM, 'VEG-HOJAS', z=z - 0.02)
        E.add(g, tone(GREEN_FRESH, -0.18 + 0.045 * z), 'VEG-HOJAS',
              details=[(v, 'VEG-NERVIOS')], subfills=[(d, tone(GREEN_STEM, -0.2))], z=z)
    return dict(key='Pilea', name='PILEA', latin='Pilea peperomioides',
                pot='macetita blanca con plato', plan=P, elev=E)


ROWS = [[monstera, ficus, kentia, strelitzia, olivo],
        [sansevieria, helecho, pothos, cactus, pilea, suculentas]]


# ============================================================ DOCUMENTO
UNITS = {'mm': (1.0, 4), 'cm': (0.1, 5), 'm': (0.001, 6)}


def new_doc(units):
    doc = ezdxf.new('R2010')
    doc.header['$INSUNITS'] = UNITS[units][1]
    doc.header['$MEASUREMENT'] = 1
    doc.header['$LUNITS'] = 2
    for name, (rgb, lw) in LAYERS.items():
        lay = doc.layers.add(name)
        lay.color = nearest_aci(rgb)
        lay.rgb = rgb
        if lw:
            lay.dxf.lineweight = lw
    doc.styles.add('VEG', font='arial.ttf')
    return doc


def fmt_cm(v):
    return f'{v / 10:.0f}'


def build(units, rows):
    s, iu = UNITS[units]
    doc = new_doc(units)
    msp = doc.modelspace()
    bmap = {}
    for p in (p for row in rows for p in row):
        for view, sc in (('PLANTA', p['plan']), ('ALZADO', p['elev'])):
            name = f"VEG_{p['key']}_{view}"
            minx, miny, maxx, maxy = sc.bounds()
            size = f"{fmt_cm(maxx - minx)} x {fmt_cm(maxy - miny)} cm"
            if view == 'ALZADO':
                size += ' (ancho x alto)'
            desc = f"{p['latin']} - {p['pot']} - vista en {view.lower()} - {size}"
            blk = doc.blocks.new(name=name, base_point=(0, 0),
                                 dxfattribs={'description': desc[:250]})
            blk.block_record.dxf.units = iu
            emit(blk, sc, s)
            bmap[(p['key'], view)] = (name, (minx, miny, maxx, maxy))

    # ---- lamina de presentacion (fuera de los bloques, capa VEG-TEXTO)
    txt = {'layer': 'VEG-TEXTO', 'style': 'VEG'}

    def text(t, x, y, h, align=TextEntityAlignment.TOP_CENTER, **kw):
        msp.add_text(t, height=h * s, dxfattribs=dict(txt, **kw)).set_placement(
            (x * s, y * s), align=align)

    def line(x0, y0, x1, y1):
        msp.add_line((x0 * s, y0 * s), (x1 * s, y1 * s), dxfattribs={'layer': 'VEG-TEXTO'})

    y_base, x_max = 0.0, 0.0
    first_h = max(bmap[(p['key'], 'ALZADO')][1][3] - bmap[(p['key'], 'ALZADO')][1][1]
                  for p in rows[0])
    text('PLANTAS DE INTERIOR  -  bloques en PLANTA y ALZADO', 0, first_h + 520, 150,
         TextEntityAlignment.BOTTOM_LEFT)
    text('Punto base: centro de la maceta (planta) / base de la maceta a cota 0 (alzado);'
         ' pothos colgante: gancho del techo.   Capa VEG-RELLENO = colores'
         ' (congelar para plano a linea).', 0, first_h + 330, 60,
         TextEntityAlignment.BOTTOM_LEFT)
    for row in rows:
        E = [bmap[(p['key'], 'ALZADO')] for p in row]
        Pl = [bmap[(p['key'], 'PLANTA')] for p in row]
        max_h = max(b[3] - b[1] for _, b in E)
        top_ext = max(b[3] for _, b in Pl)
        bot_ext = min(b[1] for _, b in Pl)
        y_plan = y_base - 380 - top_ext
        y_lab = y_plan + bot_ext - 260
        x = 0.0
        for p, (ne, be), (npl, bp) in zip(row, E, Pl):
            w = max(be[2] - be[0], bp[2] - bp[0], 1000)
            cx = x + w / 2
            hanging = p.get('hanging', False)
            ye = y_base - be[1]
            msp.add_blockref(ne, (cx * s, ye * s))
            if hanging:
                line(cx - 260, ye, cx + 260, ye)
            else:
                line(cx - w * 0.45, y_base, cx + w * 0.45, y_base)
            msp.add_blockref(npl, (cx * s, y_plan * s))
            d = max(bp[2] - bp[0], bp[3] - bp[1])
            dims = f"{fmt_cm(d)} cm diam. / h {fmt_cm(be[3] - be[1])} cm"
            text(p['name'], cx, y_lab, 80)
            text(p['latin'], cx, y_lab - 120, 50, oblique=12)
            text(dims, cx, y_lab - 200, 50)
            x += w + 350
        x_max = max(x_max, x)
        y_base = y_lab - 200 - 50 - 900 - max_h if row is not rows[-1] else y_lab - 250
    doc.set_modelspace_vport(height=(first_h + 700 - y_base) * s * 1.05,
                             center=(x_max / 2 * s, (first_h + 700 + y_base) / 2 * s))
    path = os.path.join(OUT_DIR, f'Plantas_interior_{units}.dxf')
    doc.saveas(path)
    return path, doc


def emit(layout, sc, s):
    hs, ls, _ = sc.solve()
    for g, rgb in hs:
        add_hatch(layout, g, rgb, s)
    for g, lay, lw in ls:
        add_lines(layout, g, lay, s, lw)


def preview(doc, path, width_px=3600):
    """Lamina PNG renderizada a partir del propio DXF (lo que se vera en CAD)."""
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from ezdxf import bbox
    from ezdxf.addons.drawing import Frontend, RenderContext
    from ezdxf.addons.drawing.config import BackgroundPolicy, Configuration
    from ezdxf.addons.drawing.matplotlib import MatplotlibBackend
    ext = bbox.extents(doc.modelspace(), fast=True)
    w, h = ext.size.x, ext.size.y
    fig = plt.figure(figsize=(18, 18 * h / w))
    ax = fig.add_axes([0.02, 0.02, 0.96, 0.96])
    cfg = Configuration(background_policy=BackgroundPolicy.WHITE,
                        lineweight_scaling=0.12)
    Frontend(RenderContext(doc), MatplotlibBackend(ax), config=cfg).draw_layout(
        doc.modelspace(), finalize=True)
    fig.set_size_inches(18, 18 * h / w)
    fig.savefig(path, dpi=width_px / 18, facecolor='white')
    plt.close(fig)


if __name__ == '__main__':
    rows = [[f() for f in row] for row in ROWS]
    doc_mm = None
    for u in ('mm', 'cm', 'm'):
        p, d = build(u, rows)
        print('escrito', p)
        if u == 'mm':
            doc_mm = d
    preview(doc_mm, os.path.join(OUT_DIR, 'Plantas_interior_vista_previa.png'))
    print('vista previa generada')
