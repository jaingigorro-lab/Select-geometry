#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Genera BloquesMobiliarioPlanta.dxf: biblioteca de bloques de mobiliario en
vista en planta, dibujados a tamaño real en milímetros.

- El contenido de cada bloque está en la capa 0 con color, tipo y grosor
  PorCapa, así que el bloque toma las propiedades de la capa donde se inserta.
- Cada bloque guarda sus unidades de inserción (mm): AutoCAD lo escala solo
  al insertarlo en un dibujo en metros o centímetros (variable INSUNITS).
- En el espacio modelo queda un catálogo con todos los bloques insertados,
  rotulados y con el punto de inserción marcado (cruz roja, capa que no se
  imprime).

Orientación y punto de inserción (P.I.):
- Muebles contra pared: trasera en y = 0 y frente hacia -Y. P.I. en el
  centro de la trasera.
- Piezas exentas (mesas bajas, alfombras, plantas...): P.I. en el centro.
- Sillas de despacho: miran hacia +Y, para ir delante de una mesa sin
  girarlas.
- Armarios empotrados: P.I. en la esquina izquierda del hueco, en el plano
  de la pared; el armario queda hacia +Y y la estancia hacia -Y.
- Aspa (X) dentro de un mueble = mueble alto.

Requiere ezdxf (pip install ezdxf). Uso: python3 generar_bloques.py
"""
import math
import os
import random

import ezdxf
from ezdxf import bbox, units
from ezdxf.enums import TextEntityAlignment

AQUI = os.path.dirname(os.path.abspath(__file__))
SALIDA = os.path.join(AQUI, "BloquesMobiliarioPlanta.dxf")

K90 = math.tan(math.radians(90.0) / 4.0)  # bulge de un cuarto de circunferencia
ESTILO = "MOB_TEXTO"


# ---------------------------------------------------------------------------
# Geometría auxiliar
# ---------------------------------------------------------------------------

def rrect_pts(x0, y0, x1, y1, r=0.0, bl=None, br=None, tr=None, tl=None):
    """Vértices (x, y, bulge) de un rectángulo con esquinas redondeadas.
    bl/br/tr/tl: radio de cada esquina (abajo-izq., abajo-der., ...)."""
    bl = r if bl is None else bl
    br = r if br is None else br
    tr = r if tr is None else tr
    tl = r if tl is None else tl
    p = [(x0 + bl, y0, 0.0)]
    p += [(x1 - br, y0, K90), (x1, y0 + br, 0.0)] if br > 0 else [(x1, y0, 0.0)]
    p += [(x1, y1 - tr, K90), (x1 - tr, y1, 0.0)] if tr > 0 else [(x1, y1, 0.0)]
    p += [(x0 + tl, y1, K90), (x0, y1 - tl, 0.0)] if tl > 0 else [(x0, y1, 0.0)]
    if bl > 0:
        p.append((x0, y0 + bl, K90))
    return p


def fillet_pts(pts, radios):
    """Polígono cerrado con cada vértice redondeado con su radio (0 = vivo)."""
    n = len(pts)
    out = []
    for i in range(n):
        p0, p1, p2 = pts[i - 1], pts[i], pts[(i + 1) % n]
        r = radios[i]
        if r <= 0:
            out.append((p1[0], p1[1], 0.0))
            continue
        v1 = (p0[0] - p1[0], p0[1] - p1[1])
        v2 = (p2[0] - p1[0], p2[1] - p1[1])
        l1, l2 = math.hypot(*v1), math.hypot(*v2)
        u1 = (v1[0] / l1, v1[1] / l1)
        u2 = (v2[0] / l2, v2[1] / l2)
        phi = math.acos(max(-1.0, min(1.0, u1[0] * u2[0] + u1[1] * u2[1])))
        t = r / math.tan(phi / 2.0)
        giro = (p1[0] - p0[0]) * (p2[1] - p1[1]) - (p1[1] - p0[1]) * (p2[0] - p1[0])
        bulge = math.tan((math.pi - phi) / 4.0) * (1.0 if giro > 0 else -1.0)
        out.append((p1[0] + u1[0] * t, p1[1] + u1[1] * t, bulge))
        out.append((p1[0] + u2[0] * t, p1[1] + u2[1] * t, 0.0))
    return out


def puntos_arco(p1, p2, b, n):
    """Puntos del arco con bulge b de p1 a p2 (incluye p1, excluye p2)."""
    theta = 4.0 * math.atan(b)
    dx, dy = p2[0] - p1[0], p2[1] - p1[1]
    c = math.hypot(dx, dy)
    r = c / (2.0 * math.sin(theta / 2.0))
    d = r * math.cos(theta / 2.0)
    cx = (p1[0] + p2[0]) / 2.0 - dy / c * d
    cy = (p1[1] + p2[1]) / 2.0 + dx / c * d
    a1 = math.atan2(p1[1] - cy, p1[0] - cx)
    return [(cx + abs(r) * math.cos(a1 + theta * i / n),
             cy + abs(r) * math.sin(a1 + theta * i / n)) for i in range(n)]


def muestrear(pts, cerrado=True, n_arco=16):
    """Aproxima una polilínea (x, y, bulge) por puntos, para ocultaciones."""
    out = []
    m = len(pts)
    for i in range(m if cerrado else m - 1):
        p1, p2 = pts[i], pts[(i + 1) % m]
        b = p1[2] if len(p1) > 2 else 0.0
        if abs(b) < 1e-12:
            out.append((p1[0], p1[1]))
        else:
            out.extend(puntos_arco(p1, p2, b, n_arco))
    if not cerrado:
        out.append((pts[-1][0], pts[-1][1]))
    return out


def dentro(pt, poly):
    x, y = pt
    c = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
            c = not c
    return c


def libre(pt, ocultos):
    return not any(dentro(pt, o) for o in ocultos)


def frontera(f, ta, tb, it=30):
    """Bisección entre ta y tb, donde f cambia de valor."""
    fa = f(ta)
    for _ in range(it):
        tm = (ta + tb) / 2.0
        if f(tm) == fa:
            ta = tm
        else:
            tb = tm
    return (ta + tb) / 2.0


def tramos_visibles(p, q, ocultos, paso=2.0):
    """Partes del segmento p-q que quedan fuera de los polígonos 'ocultos'."""
    n = max(2, int(math.dist(p, q) / paso) + 1)

    def en(t):
        return (p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t)

    def fuera(t):
        return libre(en(t), ocultos)

    ts = [i / (n - 1) for i in range(n)]
    fl = [fuera(t) for t in ts]
    tramos = []
    i = 0
    while i < n:
        if not fl[i]:
            i += 1
            continue
        j = i
        while j + 1 < n and fl[j + 1]:
            j += 1
        t0 = ts[i] if i == 0 else frontera(fuera, ts[i - 1], ts[i])
        t1 = ts[j] if j == n - 1 else frontera(fuera, ts[j], ts[j + 1])
        if t1 - t0 > 1e-6:
            tramos.append((en(t0), en(t1)))
        i = j + 1
    return tramos


# ---------------------------------------------------------------------------
# Pieza: dibujo dentro de un bloque (todo en capa 0, PorCapa)
# ---------------------------------------------------------------------------

class Pieza:
    def __init__(self, blk):
        self.b = blk

    def pl(self, pts, cerrado=False, ancho=None):
        attrs = {"const_width": ancho} if ancho else None
        self.b.add_lwpolyline(
            [(p[0], p[1], p[2] if len(p) > 2 else 0.0) for p in pts],
            format="xyb", close=cerrado, dxfattribs=attrs)

    def linea(self, x0, y0, x1, y1):
        self.b.add_line((x0, y0), (x1, y1))

    def circulo(self, x, y, r):
        self.b.add_circle((x, y), r)

    def arco(self, x, y, r, a0, a1):
        self.b.add_arc((x, y), r, a0, a1)

    def rect(self, x0, y0, x1, y1, r=0.0, **esquinas):
        self.pl(rrect_pts(x0, y0, x1, y1, r, **esquinas), cerrado=True)

    def aspa(self, x0, y0, x1, y1):
        self.linea(x0, y0, x1, y1)
        self.linea(x0, y1, x1, y0)

    def tirador(self, x0, x1, y, fondo=12.0):
        """Tirador visto en planta: una U abierta pegada al frente (y)."""
        self.pl([(x0, y), (x0, y - fondo), (x1, y - fondo), (x1, y)])

    def texto(self, s, x, y, h, alinear=TextEntityAlignment.LEFT):
        t = self.b.add_text(s, height=h, dxfattribs={"style": ESTILO})
        t.set_placement((x, y), align=alinear)

    def linea_oculta(self, p, q, ocultos):
        for a, b in tramos_visibles(p, q, ocultos):
            self.linea(a[0], a[1], b[0], b[1])

    def circulo_oculto(self, cx, cy, r, ocultos, n=180):
        """Círculo del que solo se dibujan los arcos visibles."""
        def fuera(a):
            return libre((cx + r * math.cos(a), cy + r * math.sin(a)), ocultos)

        angs = [2.0 * math.pi * i / n for i in range(n)]
        fl = [fuera(a) for a in angs]
        if all(fl):
            self.circulo(cx, cy, r)
            return
        if not any(fl):
            return
        k0 = fl.index(False)
        i = 1
        while i <= n:
            idx = (k0 + i) % n
            if not fl[idx]:
                i += 1
                continue
            j = i
            while j + 1 <= n and fl[(k0 + j + 1) % n]:
                j += 1
            a_ini = frontera(fuera, angs[(k0 + i - 1) % n], angs[idx]
                             if idx != 0 else 2.0 * math.pi)
            fin = (k0 + j) % n
            sig = (k0 + j + 1) % n
            a_fin = frontera(fuera, angs[fin], angs[sig] if sig != 0 else 2.0 * math.pi)
            self.arco(cx, cy, r, math.degrees(a_ini) % 360.0, math.degrees(a_fin) % 360.0)
            i = j + 1

    def insertar(self, nombre, x=0.0, y=0.0, rot=0.0):
        self.b.add_blockref(nombre, (x, y), dxfattribs={"rotation": rot})


# ---------------------------------------------------------------------------
# Despacho
# ---------------------------------------------------------------------------

def mesa(P, w, d):
    P.rect(-w / 2, -d, w / 2, 0, 8)


def mesa_direccion(P, w=1800.0, d=900.0, flecha=100.0):
    """Mesa exenta: el usuario en el lado recto (-Y), el frente curvo para
    las visitas (+Y). P.I. en el centro."""
    h, m = w / 2, d / 2
    P.pl([(-h, -m), (h, -m), (h, m - flecha, flecha / h), (-h, m - flecha)], True)
    P.rect(-400, -m + 60, 400, -m + 560, 10)  # vade de escritorio


def mesa_l(P):
    P.pl([(-800, 0), (800, 0), (800, -1600), (200, -1600),
          (200, -950, K90), (50, -800), (-800, -800)], True)


def mesa_reunion(P, w, d):
    P.rect(-w / 2, -d / 2, w / 2, d / 2, 80)


def mesa_redonda(P, diam):
    P.circulo(0, 0, diam / 2)


def monitor_teclado(P):
    P.rect(-270, -165, 270, -135, 8)       # pantalla
    P.rect(-110, -235, 110, -175, 20)      # pie
    P.rect(-230, -420, 230, -285, 10)      # teclado
    P.rect(-215, -405, 215, -300, 4)       # zona de teclas
    P.rect(300, -395, 360, -295, 28)       # ratón


def portatil(P):
    P.rect(-170, 5, 170, 75, 6)            # pantalla abierta (proyección)
    P.rect(-170, -235, 170, 0, 10)         # base
    P.rect(-150, -125, 150, -20, 4)        # teclado
    P.rect(-55, -215, 55, -140, 6)         # panel táctil


def papelera(P):
    P.circulo(0, 0, 150)
    P.circulo(0, 0, 135)


def perchero(P):
    P.circulo(0, 0, 250)                   # base
    P.circulo(0, 0, 22)                    # mástil
    for k in range(6):
        a = math.radians(30 + 60 * k)
        c, s = math.cos(a), math.sin(a)
        P.linea(22 * c, 22 * s, 190 * c, 190 * s)
        P.circulo(205 * c, 205 * s, 15)


def base_estrella(P, R, rc, ancho, ocultos, a0=90.0):
    """Base de 5 radios con ruedas; solo se ve lo que asoma bajo el asiento."""
    hw = ancho / 2.0
    fin = R - math.sqrt(rc * rc - (0.8 * hw) ** 2)
    for k in range(5):
        a = math.radians(a0 + 72.0 * k)
        ux, uy = math.cos(a), math.sin(a)
        px, py = -uy, ux
        for s in (-1.0, 1.0):
            p = (px * hw * s, py * hw * s)
            q = (ux * fin + px * hw * 0.8 * s, uy * fin + py * hw * 0.8 * s)
            P.linea_oculta(p, q, ocultos)
        P.circulo_oculto(ux * R, uy * R, rc, ocultos)


def respaldo_curvo(semi, y_int, flecha, grueso):
    """Respaldo en arco: cara interior en y_int, curvado hacia -Y."""
    return [(-semi, y_int, flecha / semi), (semi, y_int, 0.0),
            (semi, y_int - grueso, -flecha / semi), (-semi, y_int - grueso, 0.0)]


def silla_operativa(P):
    asiento = rrect_pts(-240, -190, 240, 270, bl=40, br=40, tr=75, tl=75)
    respaldo = respaldo_curvo(230, -200, 50, 50)
    bi = rrect_pts(-275, -110, -247, 150, 14)
    bd = rrect_pts(247, -110, 275, 150, 14)
    for s in (asiento, respaldo, bi, bd):
        P.pl(s, True)
    base_estrella(P, 330, 25, 36, [muestrear(s) for s in (asiento, respaldo, bi, bd)])


def silla_direccion(P):
    asiento = rrect_pts(-270, -210, 270, 280, bl=50, br=50, tr=90, tl=90)
    respaldo = respaldo_curvo(265, -225, 60, 85)
    bi = rrect_pts(-322, -150, -278, 170, 22)
    bd = rrect_pts(278, -150, 322, 170, 22)
    for s in (asiento, respaldo, bi, bd):
        P.pl(s, True)
    base_estrella(P, 350, 28, 40, [muestrear(s) for s in (asiento, respaldo, bi, bd)])


def silla_confidente(P):
    P.rect(-250, -220, 250, 240, bl=40, br=40, tr=60, tl=60)
    P.pl(respaldo_curvo(245, -235, 30, 40), True)
    P.rect(-285, -200, -255, 200, 14)
    P.rect(255, -200, 285, 200, 14)


def puesto_trabajo(P):
    P.insertar("MESA_DESPACHO_160x80")
    P.insertar("MONITOR_TECLADO")
    P.insertar("SILLA_OPERATIVA", 0, -1090)


def conjunto_reunion(P):
    P.insertar("MESA_REUNION_200x100")
    for x in (-450.0, 450.0):
        P.insertar("SILLA_CONFIDENTE", x, -800)
        P.insertar("SILLA_CONFIDENTE", x, 800, 180)
    P.insertar("SILLA_CONFIDENTE", -1300, 0, -90)
    P.insertar("SILLA_CONFIDENTE", 1300, 0, 90)


# ---------------------------------------------------------------------------
# Archivo
# ---------------------------------------------------------------------------

def cajonera(P):
    P.rect(-210, -580, 210, 0, 6)
    P.tirador(-60, 60, -580)


def archivador_vertical(P):
    P.rect(-235, -620, 235, 0)
    P.aspa(-235, -620, 235, 0)
    P.tirador(-70, 70, -620)


def archivador_lateral(P):
    P.rect(-400, -450, 400, 0)
    P.linea(-400, -430, 400, -430)
    P.tirador(-100, 100, -450)


def armario_archivo(P, w=1000.0, d=450.0):
    h = w / 2
    P.rect(-h, -d, h, 0)
    P.aspa(-h, -d, h, 0)
    P.arco(-h, -d, h, 270, 360)            # barrido de las dos puertas
    P.arco(h, -d, h, 180, 270)


# ---------------------------------------------------------------------------
# Televisión
# ---------------------------------------------------------------------------

def tv_pared(P, w):
    P.pl([(-200, -30), (-200, 0), (200, 0), (200, -30)])   # soporte de pared
    P.rect(-w / 2, -62, w / 2, -30, 4)                     # pantalla


def tv_pie(P, w=1235.0):
    P.rect(-w / 2, -170, w / 2, -135, 4)                   # pantalla
    # pie: partes que asoman detrás y delante de la pantalla
    P.pl([(-210, -135), (-210, -85, -K90), (-185, -60), (185, -60, -K90),
          (210, -85), (210, -135)])
    P.pl([(-210, -170), (-210, -230, K90), (-185, -255), (185, -255, K90),
          (210, -230), (210, -170)])


def mueble_bajo(P, w, d, divisiones):
    P.rect(-w / 2, -d, w / 2, 0, 4)
    P.linea(-w / 2, -d + 20, w / 2, -d + 20)
    for x in divisiones:
        P.linea(x, -d, x, -d + 20)


# ---------------------------------------------------------------------------
# Sillones y sofás (respaldo arriba, asiento hacia -Y)
# ---------------------------------------------------------------------------

def sillon(P, w=850.0, d=850.0, brazo=160.0, resp=200.0):
    h = w / 2
    xi = h - brazo
    P.rect(-h, -d, h, 0, 70)
    P.pl([(-xi, -d), (-xi, -resp), (xi, -resp), (xi, -d)])
    P.rect(-xi + 10, -d + 15, xi - 10, -resp - 10, 35)


def butaca(P):
    P.rect(-350, -750, 350, 0, bl=40, br=40, tr=150, tl=150)
    P.pl([(-290, -750), (-290, -250, -120 / 290), (290, -250), (290, -750)])
    P.pl([(-280, -740), (-280, -255, -112 / 280), (280, -255), (280, -740)], True)


def sofa(P, w, plazas, d=900.0, brazo=180.0, resp=220.0):
    h = w / 2
    xi = h - brazo
    P.rect(-h, -d, h, 0, 60)
    P.pl([(-xi, -d), (-xi, -resp), (xi, -resp), (xi, -d)])
    x0, x1, g = -xi + 10, xi - 10, 10.0
    wc = (x1 - x0 - (plazas - 1) * g) / plazas
    for i in range(plazas):
        a = x0 + i * (wc + g)
        P.rect(a, -d + 15, a + wc, -resp - 10, 35)


def sofa_chaise(P):
    contorno = [(-1400, 0), (1400, 0), (1400, -1600), (600, -1600), (600, -900), (-1400, -900)]
    P.pl(fillet_pts(contorno, [60, 60, 60, 60, 0, 60]), True)
    P.pl([(-1220, -900), (-1220, -220), (1220, -220), (1220, -1600)])
    P.rect(-1210, -885, -315, -230, 35)
    P.rect(-305, -885, 590, -230, 35)
    P.rect(610, -1585, 1210, -230, 35)


# ---------------------------------------------------------------------------
# Mesas bajas, mesillas y alfombras
# ---------------------------------------------------------------------------

def mesa_centro(P, w, d):
    P.rect(-w / 2, -d / 2, w / 2, d / 2, 40)
    P.rect(-w / 2 + 35, -d / 2 + 35, w / 2 - 35, d / 2 - 35, 8)


def mesa_centro_redonda(P, diam, borde=35.0):
    P.circulo(0, 0, diam / 2)
    P.circulo(0, 0, diam / 2 - borde)


def mesilla(P, w=500.0, d=400.0):
    P.rect(-w / 2, -d, w / 2, 0, 10)
    P.linea(-w / 2, -d + 20, w / 2, -d + 20)
    P.tirador(-50, 50, -d, 10)


def alfombra(P, largo, ancho, borde=80.0, fleco=50.0, paso=40.0):
    hl, ha = largo / 2, ancho / 2
    P.rect(-hl, -ha, hl, ha)
    P.rect(-hl + borde, -ha + borde, hl - borde, ha - borde)
    y = -ha + paso / 2
    while y < ha:
        P.linea(-hl, y, -hl - fleco, y)
        P.linea(hl, y, hl + fleco, y)
        y += paso


def alfombra_redonda(P, diam, borde=80.0):
    P.circulo(0, 0, diam / 2)
    P.circulo(0, 0, diam / 2 - borde)


# ---------------------------------------------------------------------------
# Armarios empotrados
# ---------------------------------------------------------------------------

def flecha_doble(P, xa, xb, y, h=35.0):
    P.linea(xa, y, xb, y)
    P.linea(xa, y, xa + h, y + h / 2)
    P.linea(xa, y, xa + h, y - h / 2)
    P.linea(xb, y, xb - h, y + h / 2)
    P.linea(xb, y, xb - h, y - h / 2)


def armario_empotrado(P, w, hojas, corredera=False, d=600.0):
    """Hueco de w x d. Frente en y=0 (plano de pared), fondo hacia +Y."""
    # Frente: tapajuntas 70x10, premarco 70x35 y cerco 70x30 a cada lado
    P.rect(-20, -10, 50, 0)
    P.rect(w - 50, -10, w + 20, 0)
    P.rect(0, 0, 35, 70)
    P.rect(w - 35, 0, w, 70)
    P.rect(35, 0, 65, 70)
    P.rect(w - 65, 0, w - 35, 70)
    # Casco: costados de 16 mm y trasera de 10 mm
    P.rect(0, 80, 16, d)
    P.rect(w - 16, 80, w, d)
    P.rect(16, d - 10, w - 16, d)

    x0, x1 = 67.0, w - 67.0
    if not corredera:
        g = 3.0
        wh = (x1 - x0 - (hojas - 1) * g) / hojas
        bisagras = {2: "ID", 3: "IDD", 4: "IDID"}[hojas]
        for i in range(hojas):
            a = x0 + i * (wh + g)
            P.rect(a, 0, a + wh, 19)
            if bisagras[i] == "I":
                P.arco(a, 0, wh, 270, 360)
            else:
                P.arco(a + wh, 0, wh, 180, 270)
        divisiones = [x0 + 2 * (wh + g) - g / 2] if hojas > 2 else []
    else:
        solape = 40.0
        wh = (x1 - x0 + (hojas - 1) * solape) / hojas
        for i in range(hojas):
            a = x0 + i * (wh - solape)
            y0 = 23.0 if i % 2 == 0 else 0.0          # guía trasera / delantera
            P.rect(a, y0, a + wh, y0 + 19)
            flecha_doble(P, a + wh * 0.3, a + wh * 0.7, -80)
        divisiones = [w * k / hojas for k in range(1, hojas)]

    for xd in divisiones:
        P.rect(xd - 8, 80, xd + 8, d - 10)

    # Interior: barra de colgar y perchas en cada módulo
    limites = [16.0]
    for xd in divisiones:
        limites += [xd - 8, xd + 8]
    limites.append(w - 16.0)
    yb = (80.0 + d - 10.0) / 2.0
    for m0, m1 in zip(limites[0::2], limites[1::2]):
        P.linea(m0 + 10, yb, m1 - 10, yb)
        x = m0 + 55
        while x <= m1 - 45:
            P.linea(x - 12, yb - 205, x + 12, yb + 205)
            x += 85


def rotura(P, pts):
    P.pl(pts)


def detalle_jamba(P):
    """Sección horizontal por la jamba de un armario empotrado (mm reales)."""
    # Tabique con enlucido de 15 mm
    h = P.b.add_hatch(color=256)
    h.set_pattern_fill("ANSI31", color=256, scale=3.0)
    h.paths.add_polyline_path([(-160, 15), (-15, 15), (-15, 260), (-160, 260)], is_closed=True)
    P.linea(-160, 0, 0, 0)
    P.linea(0, 0, 0, 260)
    P.linea(-160, 15, -15, 15)
    P.linea(-15, 15, -15, 260)
    rotura(P, [(-160, -12), (-160, 118), (-150, 124), (-170, 136), (-160, 142), (-160, 272)])
    rotura(P, [(-172, 260), (-90, 260), (-84, 250), (-72, 270), (-66, 260), (28, 260)])
    # Premarco 70x35 (pino, con aspa) y cerco 70x30
    P.rect(0, 0, 35, 70)
    P.aspa(0, 0, 35, 70)
    P.rect(35, 0, 65, 70)
    # Tapajuntas 70x10
    P.rect(-20, -10, 50, 0, bl=3, br=0, tr=0, tl=0)
    # Puerta de DM de 19 mm (holgura de 2 mm con el cerco)
    P.pl([(300, 0), (67, 0), (67, 19), (300, 19)])
    rotura(P, [(300, -14), (300, 4), (310, 8), (290, 14), (300, 18), (300, 33)])
    # Bisagra de cazoleta: cazoleta Ø35 en la puerta, brazo y base en el cerco
    P.rect(72, 6, 107, 19)
    P.rect(65, 28, 75, 62)
    P.pl([(89.5, 17), (75, 45)], ancho=5)
    # Costado del casco, 16 mm
    P.pl([(0, 80), (16, 80), (16, 260)])
    # Rótulos (altura 12,5 = 2,5 mm impresos a E 1:5)
    th = 12.5
    rot = [
        (235, "COSTADO DEL CASCO 16 mm", [(330, 239), (16, 239)]),
        (185, "BASE DE LA BISAGRA", [(330, 189), (120, 189), (75, 58)]),
        (135, "PREMARCO DE PINO 70x35", [(330, 139), (60, 139), (18, 62)]),
        (85, "CERCO 70x30", [(330, 89), (100, 89), (50, 66)]),
        (35, "BISAGRA DE CAZOLETA Ø35", [(330, 39), (110, 39), (100, 16)]),
        (-15, "PUERTA DE DM 19 mm", [(330, -11), (270, -11), (250, 8)]),
        (-65, "TAPAJUNTAS 70x10", [(330, -61), (40, -61), (15, -6)]),
    ]
    for y, s, dirz in rot:
        P.pl(dirz)
        P.texto(s, 340, y, th)
    P.pl([(-100, -52), (-90, 100)])
    P.texto("TABIQUE + ENLUCIDO 15 mm", -165, -75, th)


# ---------------------------------------------------------------------------
# Decoración
# ---------------------------------------------------------------------------

def aparador(P, w, d, puertas):
    mueble_bajo(P, w, d, [-w / 2 + w * k / puertas for k in range(1, puertas)])


def consola(P, w, d):
    P.rect(-w / 2, -d, w / 2, 0, 6)
    P.rect(-w / 2 + 25, -d + 25, w / 2 - 25, -25, 2)


def mueble_alto(P, w, d, frente=False):
    P.rect(-w / 2, -d, w / 2, 0)
    P.aspa(-w / 2, -d, w / 2, 0)
    if frente:
        P.linea(-w / 2, -d + 15, w / 2, -d + 15)


def balda(P, w=800.0, d=250.0):
    P.rect(-w / 2, -d, w / 2, 0)


def peana(P, lado=400.0, escalon=50.0):
    h = lado / 2
    P.rect(-h, -h, h, h)
    P.rect(-h + escalon, -h + escalon, h - escalon, h - escalon)


def peana_redonda(P, diam=400.0, escalon=50.0):
    P.circulo(0, 0, diam / 2)
    P.circulo(0, 0, diam / 2 - escalon)


def planta(P, r_maceta, r_hojas, n, semilla):
    rnd = random.Random(semilla)
    P.circulo(0, 0, r_maceta)
    for anillo, (f0, f1, desfase) in enumerate(((0.72, 1.0, 0.0), (0.45, 0.62, 0.5))):
        for k in range(n):
            a = math.radians(360.0 * (k + desfase) / n + rnd.uniform(-8, 8))
            r0 = r_maceta * 0.12
            r1 = r_hojas * rnd.uniform(f0, f1)
            b = rnd.uniform(0.26, 0.36)
            c, s = math.cos(a), math.sin(a)
            P.pl([(r0 * c, r0 * s, b), (r1 * c, r1 * s, b)], True)


def lampara(P, r_pantalla, r_centro):
    P.circulo(0, 0, r_pantalla)
    P.circulo(0, 0, r_centro)
    for k in range(4):
        a = math.radians(45 + 90 * k)
        c, s = math.cos(a), math.sin(a)
        P.linea(r_centro * c, r_centro * s, r_pantalla * c, r_pantalla * s)


def jarron(P):
    P.circulo(0, 0, 100)
    P.circulo(0, 0, 70)


# ---------------------------------------------------------------------------
# Catálogo: (categoría, [(nombre, descripción, función)])
# Los bloques compuestos van al final de su lista y usan otros ya creados.
# ---------------------------------------------------------------------------

CATALOGO = [
    ("MESAS DE DESPACHO Y REUNIÓN", [
        ("MESA_DESPACHO_120x60", "Mesa de despacho 120 x 60 cm", lambda P: mesa(P, 1200, 600)),
        ("MESA_DESPACHO_140x70", "Mesa de despacho 140 x 70 cm", lambda P: mesa(P, 1400, 700)),
        ("MESA_DESPACHO_160x80", "Mesa de despacho 160 x 80 cm", lambda P: mesa(P, 1600, 800)),
        ("MESA_DIRECCION_180x90", "Mesa de dirección 180 x 90 cm, exenta (P.I. centro)", mesa_direccion),
        ("MESA_DESPACHO_L_160x160", "Mesa en L 160 x 160 cm, ala a la derecha", mesa_l),
        ("MESA_REUNION_200x100", "Mesa de reuniones 200 x 100 cm", lambda P: mesa_reunion(P, 2000, 1000)),
        ("MESA_REUNION_D120", "Mesa de reuniones redonda Ø120 cm", lambda P: mesa_redonda(P, 1200)),
    ]),
    ("SILLAS DE DESPACHO", [
        ("SILLA_OPERATIVA", "Silla operativa con ruedas, base Ø71 cm", silla_operativa),
        ("SILLA_DIRECCION", "Sillón de dirección, base Ø76 cm", silla_direccion),
        ("SILLA_CONFIDENTE", "Silla de confidente 57 x 52 cm", silla_confidente),
    ]),
    ("ARCHIVO", [
        ("CAJONERA_42x58", "Cajonera con ruedas 42 x 58 cm", cajonera),
        ("ARCHIVADOR_4C_47x62", "Archivador vertical de 4 cajones 47 x 62 cm", archivador_vertical),
        ("ARCHIVADOR_LATERAL_80x45", "Archivador bajo de cajones 80 x 45 cm", archivador_lateral),
        ("ARMARIO_ARCHIVO_100x45", "Armario de archivo alto, 2 puertas, 100 x 45 cm", armario_archivo),
    ]),
    ("ACCESORIOS DE DESPACHO", [
        ("MONITOR_TECLADO", "Monitor, teclado y ratón (P.I. = trasera de la mesa)", monitor_teclado),
        ("PORTATIL", "Portátil abierto 34 x 24 cm", portatil),
        ("PAPELERA_D30", "Papelera Ø30 cm", papelera),
        ("PERCHERO_D50", "Perchero de pie Ø50 cm", perchero),
    ]),
    ("CONJUNTOS", [
        ("PUESTO_TRABAJO_160x80", "Mesa 160x80, silla operativa y ordenador", puesto_trabajo),
        ("CONJUNTO_REUNION_6P", "Mesa 200x100 con 6 sillas de confidente", conjunto_reunion),
    ]),
    ("TELEVISIÓN", [
        ("TV_43_PARED", "TV de 43 pulgadas colgada en la pared", lambda P: tv_pared(P, 970)),
        ("TV_55_PARED", "TV de 55 pulgadas colgada en la pared", lambda P: tv_pared(P, 1235)),
        ("TV_65_PARED", "TV de 65 pulgadas colgada en la pared", lambda P: tv_pared(P, 1450)),
        ("TV_75_PARED", "TV de 75 pulgadas colgada en la pared", lambda P: tv_pared(P, 1680)),
        ("TV_55_PIE", "TV de 55 pulgadas con pie (sobre mueble)", tv_pie),
        ("MUEBLE_TV_180x40", "Mueble de TV 180 x 40 cm", lambda P: mueble_bajo(P, 1800, 400, [-300, 300])),
        ("MUEBLE_TV_240x45", "Mueble de TV 240 x 45 cm", lambda P: mueble_bajo(P, 2400, 450, [-600, 0, 600])),
    ]),
    ("SILLONES Y SOFÁS", [
        ("SILLON_85x85", "Sillón tapizado 85 x 85 cm", sillon),
        ("BUTACA_70x75", "Butaca envolvente 70 x 75 cm", butaca),
        ("SOFA_2P_160x90", "Sofá de 2 plazas 160 x 90 cm", lambda P: sofa(P, 1600, 2)),
        ("SOFA_3P_210x90", "Sofá de 3 plazas 210 x 90 cm", lambda P: sofa(P, 2100, 3)),
        ("SOFA_CHAISELONGUE_280x160", "Sofá con chaise longue 280 x 160 cm", sofa_chaise),
    ]),
    ("MESAS BAJAS Y MESILLAS", [
        ("MESA_CENTRO_120x60", "Mesa de centro 120 x 60 cm", lambda P: mesa_centro(P, 1200, 600)),
        ("MESA_CENTRO_D80", "Mesa de centro redonda Ø80 cm", lambda P: mesa_centro_redonda(P, 800)),
        ("MESA_AUXILIAR_50x50", "Mesa auxiliar 50 x 50 cm", lambda P: mesa_centro(P, 500, 500)),
        ("MESA_AUXILIAR_D45", "Mesa auxiliar redonda Ø45 cm", lambda P: mesa_centro_redonda(P, 450, 30)),
        ("MESILLA_NOCHE_50x40", "Mesilla de noche 50 x 40 cm", mesilla),
    ]),
    ("ALFOMBRAS", [
        ("ALFOMBRA_120x170", "Alfombra 120 x 170 cm", lambda P: alfombra(P, 1700, 1200)),
        ("ALFOMBRA_160x230", "Alfombra 160 x 230 cm", lambda P: alfombra(P, 2300, 1600)),
        ("ALFOMBRA_200x300", "Alfombra 200 x 300 cm", lambda P: alfombra(P, 3000, 2000)),
        ("ALFOMBRA_240x340", "Alfombra 240 x 340 cm", lambda P: alfombra(P, 3400, 2400)),
        ("ALFOMBRA_D160", "Alfombra redonda Ø160 cm", lambda P: alfombra_redonda(P, 1600)),
        ("ALFOMBRA_D200", "Alfombra redonda Ø200 cm", lambda P: alfombra_redonda(P, 2000)),
    ]),
    ("ARMARIOS EMPOTRADOS", [
        ("ARMARIO_EMP_BATIENTE_2H_100x60", "Empotrado 2 puertas batientes, hueco 100 x 60 cm",
         lambda P: armario_empotrado(P, 1000, 2)),
        ("ARMARIO_EMP_BATIENTE_3H_150x60", "Empotrado 3 puertas batientes, hueco 150 x 60 cm",
         lambda P: armario_empotrado(P, 1500, 3)),
        ("ARMARIO_EMP_BATIENTE_4H_200x60", "Empotrado 4 puertas batientes, hueco 200 x 60 cm",
         lambda P: armario_empotrado(P, 2000, 4)),
        ("ARMARIO_EMP_CORREDERA_2H_180x60", "Empotrado 2 puertas correderas, hueco 180 x 60 cm",
         lambda P: armario_empotrado(P, 1800, 2, corredera=True)),
        ("ARMARIO_EMP_CORREDERA_3H_240x60", "Empotrado 3 puertas correderas, hueco 240 x 60 cm",
         lambda P: armario_empotrado(P, 2400, 3, corredera=True)),
        ("DETALLE_ARMARIO_JAMBA", "Detalle de jamba, tamaño real (para E 1:2 a 1:5)", detalle_jamba),
    ]),
    ("DECORACIÓN", [
        ("APARADOR_160x45", "Aparador 160 x 45 cm", lambda P: aparador(P, 1600, 450, 4)),
        ("APARADOR_200x50", "Aparador 200 x 50 cm", lambda P: aparador(P, 2000, 500, 4)),
        ("CONSOLA_100x30", "Consola 100 x 30 cm", lambda P: consola(P, 1000, 300)),
        ("CONSOLA_120x35", "Consola 120 x 35 cm", lambda P: consola(P, 1200, 350)),
        ("ESTANTERIA_80x35", "Estantería alta 80 x 35 cm", lambda P: mueble_alto(P, 800, 350)),
        ("ESTANTERIA_120x35", "Estantería alta 120 x 35 cm", lambda P: mueble_alto(P, 1200, 350)),
        ("VITRINA_100x40", "Vitrina alta 100 x 40 cm", lambda P: mueble_alto(P, 1000, 400, True)),
        ("BALDA_80x25", "Balda de pared 80 x 25 cm", balda),
        ("PEANA_40x40", "Peana 40 x 40 cm", peana),
        ("PEANA_D40", "Peana redonda Ø40 cm", peana_redonda),
        ("PLANTA_GRANDE_D80", "Planta en maceta, Ø80 cm", lambda P: planta(P, 200, 400, 11, 7)),
        ("PLANTA_PEQUENA_D40", "Planta pequeña en maceta, Ø40 cm", lambda P: planta(P, 100, 200, 9, 3)),
        ("LAMPARA_PIE_D45", "Lámpara de pie Ø45 cm", lambda P: lampara(P, 225, 40)),
        ("LAMPARA_MESA_D30", "Lámpara de sobremesa Ø30 cm", lambda P: lampara(P, 150, 25)),
        ("JARRON_D20", "Jarrón Ø20 cm", jarron),
    ]),
]

NOTAS = [
    "Unidades: milímetros. Cada bloque guarda sus unidades (mm): AutoCAD lo escala solo al insertarlo en un dibujo en metros o centímetros (INSUNITS).",
    "El contenido de los bloques está en la capa 0 y PorCapa: el bloque toma la capa, el color y el grosor de la capa donde lo insertas.",
    "Cruz roja = punto de inserción (capa CAT-PUNTO-INSERCION, no se imprime). Muebles de pared: centro de la trasera. Piezas exentas: centro. Armarios empotrados: esquina izquierda del hueco.",
    "Frente de los muebles hacia abajo (-Y). Las sillas de despacho miran hacia arriba (+Y) para ir delante de la mesa sin girarlas. Aspa = mueble alto.",
]


# ---------------------------------------------------------------------------
# Construcción del documento
# ---------------------------------------------------------------------------

def crear_documento():
    doc = ezdxf.new("R2010")
    doc.units = units.MM
    doc.header["$MEASUREMENT"] = 1
    doc.styles.add(ESTILO, font="arial.ttf")
    doc.layers.add("CAT-BLOQUES", color=7)
    doc.layers.add("CAT-TEXTOS", color=8)
    doc.layers.add("CAT-TITULOS", color=7)
    pi = doc.layers.add("CAT-PUNTO-INSERCION", color=1)
    pi.dxf.plot = 0

    for _, items in CATALOGO:
        for nombre, desc, dibujar in items:
            blk = doc.blocks.new(name=nombre)
            blk.units = units.MM
            blk.block.dxf.description = desc
            dibujar(Pieza(blk))
    return doc


def texto(msp, s, x, y, h, capa):
    t = msp.add_text(s, height=h, dxfattribs={"layer": capa, "style": ESTILO})
    t.set_placement((x, y), align=TextEntityAlignment.LEFT)


def marca_pi(msp, x, y, s=60.0):
    a = {"layer": "CAT-PUNTO-INSERCION"}
    msp.add_line((x - s, y), (x + s, y), dxfattribs=a)
    msp.add_line((x, y - s), (x, y + s), dxfattribs=a)
    msp.add_circle((x, y), s * 0.45, dxfattribs=a)


def crear_catalogo(doc, ancho_max=21000.0):
    msp = doc.modelspace()
    y = 0.0
    texto(msp, "BIBLIOTECA DE BLOQUES DE MOBILIARIO · VISTA EN PLANTA", 0, y, 320, "CAT-TITULOS")
    y -= 520
    for linea in NOTAS:
        texto(msp, linea, 0, y, 90, "CAT-TEXTOS")
        y -= 160
    y -= 500
    x_max = 0.0
    for categoria, items in CATALOGO:
        texto(msp, categoria, 0, y, 200, "CAT-TITULOS")
        y -= 500
        x = 0.0
        alto_fila = 0.0
        for nombre, desc, _ in items:
            ext = bbox.extents(doc.blocks.get(nombre))
            w, h = ext.size.x, ext.size.y
            ancho = max(w, len(nombre) * 75 * 0.68, len(desc) * 60 * 0.56)
            if x > 0 and x + ancho > ancho_max:
                y -= alto_fila + 900
                x, alto_fila = 0.0, 0.0
            ix, iy = x - ext.extmin.x, y - ext.extmax.y
            msp.add_blockref(nombre, (ix, iy), dxfattribs={"layer": "CAT-BLOQUES"})
            marca_pi(msp, ix, iy)
            texto(msp, nombre, x, y - h - 200, 75, "CAT-TEXTOS")
            texto(msp, desc, x, y - h - 330, 60, "CAT-TEXTOS")
            x += ancho + 700
            x_max = max(x_max, x)
            alto_fila = max(alto_fila, h)
        y -= alto_fila + 1100
    doc.set_modelspace_vport(height=-y * 1.05, center=(x_max / 2, y / 2))


def main():
    doc = crear_documento()
    crear_catalogo(doc)
    auditor = doc.audit()
    if auditor.has_errors:
        auditor.print_error_report()
        raise SystemExit("El DXF tiene errores")
    doc.saveas(SALIDA, encoding="utf-8")
    n = sum(len(items) for _, items in CATALOGO)
    print(f"{n} bloques -> {SALIDA}")


if __name__ == "__main__":
    main()
