#!/usr/bin/env python3
"""Imagenes de la propuesta de la planta segunda.

  planta2_propuesta.svg        lamina en color: planta amueblada, circulaciones,
                               cotas, seguridad y leyenda
  planta2_sobre_tu_plano.svg   lo que dibuja el DXF (mismas capas y colores que en
                               AutoCAD) encima de la captura del plano

Uso: python3 planta2_img.py [captura.png]
(la superposicion solo se genera si se da la captura; los SVG se pasan a PNG
con cualquier navegador, p. ej. Chromium en modo headless)
"""
import base64
import io
import math
import os
import sys

from ezdxf.colors import aci2rgb
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import planta2 as P

HERE = P.SALIDA
FONT = "Liberation Sans"
BL = P.bloques()


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def aci(n):
    return "#%02x%02x%02x" % tuple(aci2rgb(n))


def place_pts(pts, x, y, rot):
    a = math.radians(rot)
    c, s = math.cos(a), math.sin(a)
    return [(x + c * p[0] - s * p[1], y + s * p[0] + c * p[1]) for p in pts]


def place(it, x, y, rot):
    """Geometria de un elemento de bloque insertado, en cm del diseno."""
    if it.kind == "circle":
        cx, cy, r = it.geom
        return ("circle", place_pts([(cx, cy)], x, y, rot)[0], r)
    if it.kind == "line":
        return ("poly", place_pts(it.geom, x, y, rot), False)
    if it.kind == "dash":
        return ("dash", place_pts(P.tess(it.geom, False), x, y, rot), False)
    return ("poly", place_pts(P.tess(it.geom, it.closed), x, y, rot), it.closed)


class Canvas:
    """Primitivas SVG sobre una transformacion cm -> px."""

    def __init__(self, T, k):
        self.T, self.k, self.out = T, k, []

    def add(self, s):
        self.out.append(s)

    def pts(self, pts):
        return " ".join("%.2f,%.2f" % self.T(*p[:2]) for p in pts)

    def poly(self, pts, fill="none", stroke="none", sw=1.0, closed=True, extra=""):
        tag = "polygon" if closed else "polyline"
        self.add('<%s points="%s" fill="%s" stroke="%s" stroke-width="%.2f" stroke-linejoin="round" '
                 'stroke-linecap="round" %s/>' % (tag, self.pts(pts), fill if closed else "none", stroke, sw, extra))

    def rect(self, x0, y0, x1, y1, fill="none", stroke="none", sw=1.0, extra=""):
        self.poly([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], fill, stroke, sw, True, extra)

    def circle(self, c, r, fill="none", stroke="none", sw=1.0, extra=""):
        x, y = self.T(*c)
        self.add('<circle cx="%.2f" cy="%.2f" r="%.2f" fill="%s" stroke="%s" stroke-width="%.2f" %s/>'
                 % (x, y, r * self.k, fill, stroke, sw, extra))

    def line(self, p0, p1, stroke, sw=1.0, extra=""):
        a, b = self.T(*p0)
        c, d = self.T(*p1)
        self.add('<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="%s" stroke-width="%.2f" '
                 'stroke-linecap="round" %s/>' % (a, b, c, d, stroke, sw, extra))

    def text(self, p, s, size, fill, anchor="middle", weight="normal", rot=0.0, extra=""):
        x, y = self.T(*p)
        self.add('<text x="%.2f" y="%.2f" font-family="%s" font-size="%.1f" fill="%s" text-anchor="%s" '
                 'font-weight="%s" transform="rotate(%.1f %.2f %.2f)" %s>%s</text>'
                 % (x, y, FONT, size, fill, anchor, weight, -rot, x, y, extra, esc(s)))

    def svg(self):
        return "\n".join(self.out)


def railing_x(y):
    """Cara de la barandilla hacia la zona de juego (algo inclinada en el plano)."""
    return 574.0 + 6.0 * (P.TECHO_Y - y) / (P.TECHO_Y - 134.6)


# ================================================================= A) lamina en color
INK, DET = "#3a332b", "#8d867b"
WALL, FLOOR, FLOOR2, WET = "#46494f", "#fbf7ef", "#efebe4", "#e3e1dc"
BLUE, SAFE = "#2f76b0", "#e07020"


def draw_block(cv, name, x, y, rot):
    for it in sorted(BL[name]["items"], key=lambda i: i.z):
        g = place(it, x, y, rot)
        main = it.style == "main"
        stroke, sw = (INK, 1.0) if main else (DET, 0.55)
        if g[0] == "circle":
            cv.circle(g[1], g[2], it.fill or "none", stroke, sw)
        elif g[0] == "dash":
            cv.poly(g[1], stroke=stroke, sw=sw, closed=False, extra='stroke-dasharray="4 3"')
        else:
            cv.poly(g[1], it.fill or "none", stroke, sw, closed=g[2])


def dim(cv, p0, p1, off, label, color="#5d5850", size=11.5, ext=None, at=0.5):
    """Cota entre p0 y p1 (horizontal o vertical), desplazada 'off' cm."""
    horiz = abs(p1[1] - p0[1]) < 1e-6
    if horiz:
        y = p0[1] + off
        a, b = (p0[0], y), (p1[0], y)
        if ext is not None:
            for xx in (p0[0], p1[0]):
                cv.line((xx, ext), (xx, y + (3 if off > 0 else -3)), color, 0.6)
    else:
        x = p0[0] + off
        a, b = (x, p0[1]), (x, p1[1])
        if ext is not None:
            for yy in (p0[1], p1[1]):
                cv.line((ext, yy), (x + (3 if off > 0 else -3), yy), color, 0.6)
    cv.line(a, b, color, 0.8)
    for q in (a, b):
        cv.line((q[0] - 3, q[1] - 3), (q[0] + 3, q[1] + 3), color, 1.4)
    m = (a[0] + (b[0] - a[0]) * at, a[1] + (b[1] - a[1]) * at)
    if horiz:
        cv.text((m[0], m[1] + 3.5), label, size, color, weight="bold")
    else:
        cv.text((m[0] - 3.5, m[1]), label, size, color, weight="bold", rot=90)


def callout(cv, n, p):
    x, y = cv.T(*p)
    cv.add('<g><circle cx="%.2f" cy="%.2f" r="11" fill="#2f3a45" stroke="#fff" stroke-width="1.5"/>'
           '<text x="%.2f" y="%.2f" font-family="%s" font-size="12" font-weight="bold" fill="#fff" '
           'text-anchor="middle">%d</text></g>' % (x, y, x, y + 4.2, FONT, n))


def lamina():
    X0, X1, Y0, Y1 = -62.0, 736.0, -78.0, 602.0
    k = 1.62
    mx, top = 34, 104
    pw, ph = (X1 - X0) * k, (Y1 - Y0) * k
    leg_w = 540
    Wsvg = int(mx + pw + 28 + leg_w + 30)
    Hsvg = int(top + ph + 30)

    def T(x, y):
        return (mx + (x - X0) * k, top + (Y1 - y) * k)
    cv = Canvas(T, k)
    cv.add('<defs>'
           '<radialGradient id="glow"><stop offset="0" stop-color="#ffd36b" stop-opacity="0.55"/>'
           '<stop offset="0.55" stop-color="#ffd36b" stop-opacity="0.18"/>'
           '<stop offset="1" stop-color="#ffd36b" stop-opacity="0"/></radialGradient>'
           '<pattern id="rayado" width="7" height="7" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">'
           '<rect width="7" height="7" fill="%s" fill-opacity="0.10"/>'
           '<line x1="0" y1="0" x2="0" y2="7" stroke="%s" stroke-width="1.6" stroke-opacity="0.55"/></pattern>'
           '<pattern id="pilar" width="5" height="5" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">'
           '<rect width="5" height="5" fill="#6f6480"/><line x1="0" y1="0" x2="0" y2="5" stroke="#9d92ad" '
           'stroke-width="1.2"/></pattern>'
           '<marker id="flecha" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" '
           'orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="%s"/></marker>'
           '<marker id="flecha_g" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="8" markerHeight="8" '
           'orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="#7b746a"/></marker>'
           '</defs>' % (SAFE, SAFE, BLUE))

    # ---- suelos (contexto)
    cv.rect(X0, -9.3, 713.0, P.TECHO_Y, FLOOR2)                           # pasillo, descansillo...
    cv.rect(0, 0, P.SALA_W, P.SALA_H, FLOOR)                              # sala
    cv.rect(P.BANO_X, P.PASILLO_Y1, railing_x(P.PASILLO_Y1), P.TECHO_Y, FLOOR)  # zona de juego
    cv.rect(-94.8, 380.5, 245.8, P.TECHO_Y, WET)                          # bano
    cv.rect(X0, -9.3, -101.4, P.TECHO_Y, WET)                             # dormitorios (izq.)
    cv.rect(722.0, -9.3, X1, P.TECHO_Y, WET)                              # dormitorio principal
    # escalera: huella, peldanos y compensacion
    cv.poly([(581.3, P.TECHO_Y), (688.1, P.TECHO_Y), (695.3, 180.0), (587.0, 180.0)], "#e6e1d8", "#b9b1a4", 0.6)
    for l in P.ref_escalera():
        cv.poly(l, stroke="#a79f92", sw=0.8, closed=False)
    cv.circle((641.0, 505.0), 3.2, "#7b746a")
    cv.poly([(641.0, 505.0), (641.0, 212.0)], stroke="#7b746a", sw=1.1, closed=False,
            extra='stroke-dasharray="6 4" marker-end="url(#flecha_g)"')
    cv.text((666.0, 330.0), "llega de planta 1ª", 10.5, "#7b746a", rot=90, extra='font-style="italic"')
    # franja de 60 cm junto a la barandilla sin muebles trepables
    cv.poly([(514.0, P.PASILLO_Y1), (railing_x(P.PASILLO_Y1), P.PASILLO_Y1), (railing_x(P.TECHO_Y), P.TECHO_Y),
             (514.0, P.TECHO_Y)], "url(#rayado)", SAFE, 0.8, extra='stroke-dasharray="5 3"')

    # ---- mobiliario (en el orden de dibujo del DXF)
    lamps = []
    for name, x, y, rot, layer in P.INSERCIONES:
        if name == "PS_LAMPARA_TECHO":
            lamps.append(("techo", x, y))
            continue
        draw_block(cv, name, x, y, rot)
        if name == "PS_APLIQUE_PARED":
            a = math.radians(rot)
            lamps.append(("aplique", x + 15 * math.cos(a), y + 15 * math.sin(a)))
        elif name == "PS_LAMPARA_PIE":
            lamps.append(("pie", x, y))

    # ---- muros (encima, para cantos limpios), pilar y barandilla
    for poly in P.ref_plano():
        if abs(poly[0][0] - 574.0) < 1e-6:                                # barandilla de la escalera
            cv.poly(poly, SAFE, "#9a4a12", 0.8)
        else:
            cv.poly(poly, WALL, WALL, 0.5)
    cv.poly(P.ref_pilar(), "url(#pilar)", "#4b4257", 0.8)

    # ---- luz (encima de todo, translucida)
    sala = '<clipPath id="c_sala"><polygon points="%s"/></clipPath>' % cv.pts(
        [(0, P.PILAR_Y), (P.PILAR_X, P.PILAR_Y), (P.PILAR_X, 0), (P.SALA_W, 0), (P.SALA_W, P.SALA_H), (0, P.SALA_H)])
    juego = '<clipPath id="c_juego"><polygon points="%s"/></clipPath>' % cv.pts(
        [(P.BANO_X, P.PASILLO_Y0), (railing_x(P.PASILLO_Y0), P.PASILLO_Y0), (railing_x(P.TECHO_Y), P.TECHO_Y),
         (P.BANO_X, P.TECHO_Y)])
    cv.add("<defs>%s%s</defs>" % (sala, juego))
    for kind, x, y in lamps:
        clip = "c_juego" if y > P.SALA_H else "c_sala"
        r = {"techo": 88, "aplique": 62, "pie": 95}[kind]
        cv.circle((x, y), r, "url(#glow)", extra='clip-path="url(#%s)"' % clip)
        if kind == "techo":                                               # colgante: por encima, a trazos
            cv.circle((x, y), 20, "none", "#8a6d2f", 1.1, 'stroke-dasharray="5 3"')
            for s in (1, -1):
                cv.line((x - 5, y - 5 * s), (x + 5, y + 5 * s), "#8a6d2f", 1.0)

    # ---- circulaciones
    def path(pts):
        return " ".join(("M" if i == 0 else "L") + " %.2f %.2f" % T(*p) for i, p in enumerate(pts))
    yc = (P.PASILLO_Y0 + P.PASILLO_Y1) / 2
    for pts, end in (([(641.0, 184.0), (641.0, 96.0), (492.0, 96.0), (492.0, yc), (-52.0, yc)], True),
                     ([(641.0, 96.0), (706.0, 96.0)], True),
                     ([(172.0, yc), (172.0, 236.0)], True),
                     ([(492.0, yc), (492.0, 368.0)], True)):
        cv.add('<path d="%s" fill="none" stroke="%s" stroke-width="2.2" stroke-dasharray="8 5" '
               'stroke-linejoin="round" opacity="0.9" %s/>'
               % (path(pts), BLUE, 'marker-end="url(#flecha)"' if end else ""))
    cv.circle((641.0, 96.0), 2.4, BLUE)
    cv.circle((492.0, yc), 2.4, BLUE)

    # ---- rotulos de estancias
    lab = dict(size=11, fill="#8a8378", weight="bold", extra='letter-spacing="2"')
    cv.text((75.0, 452.0), "BAÑO", **lab)
    cv.text((598.0, 40.0), "DESCANSILLO", **lab)
    cv.text((729.0, 330.0), "DORM. PRINCIPAL", rot=90, **lab)
    cv.text((42.0, 290.0), "PASILLO", **lab)
    cv.text((300.0, 283.0), "SALA DE ESTAR · 10,4 m²", 13, "#2f3a45", weight="bold", extra='letter-spacing="1"')
    cv.text((392.0, 351.0), "ZONA DE JUEGO Y LECTURA · 5,3 m²", 13, "#2f3a45", weight="bold",
            extra='letter-spacing="1"')
    cv.text((544.0, 478.0), "sin muebles", 10.5, SAFE, rot=90, weight="bold")
    cv.text((556.0, 478.0), "trepables", 10.5, SAFE, rot=90, weight="bold")

    # ---- cotas
    GR = "#5d5850"
    dim(cv, (0.0, -9.3), (P.SALA_W, -9.3), -44.0, "4,03", GR, ext=-12.0)
    dim(cv, (0.0, 0.0), (0.0, P.SALA_H), -34.0, "2,67", GR)
    dim(cv, (P.BANO_X, P.TECHO_Y + 29.4), (railing_x(P.TECHO_Y), P.TECHO_Y + 29.4), 18.0, "3,23", GR,
        ext=P.TECHO_Y + 31.0)
    dim(cv, (545.0, P.PASILLO_Y0), (545.0, P.PASILLO_Y1), 0.0, "paso 101", BLUE, size=11)
    dim(cv, (40.5, 150.0), (190.5, 150.0), 0.0, "paso 150", BLUE, size=11)
    dim(cv, (7.5, 104.0), (P.SALA_W - 95.5, 104.0), 0.0, "TV–sofá 3,00 m", GR, size=11, at=0.28)
    dim(cv, (508.5, 522.0), (railing_x(522.0), 522.0), 0.0, "66", SAFE, size=11)
    # escala grafica
    sx, sy = 590.0, -58.0
    for i in range(4):
        cv.rect(sx + i * 25, sy, sx + (i + 1) * 25, sy + 5, "#2f3a45" if i % 2 == 0 else "#ffffff", "#2f3a45", 0.8)
    cv.text((sx, sy - 13), "0", 10, GR)
    cv.text((sx + 100, sy - 13), "1 m", 10, GR)

    # ---- numeros de las piezas
    for n, p in enumerate([(330.0, 172.0), (62.0, 200.0), (204.0, 178.0), (150.0, 62.0), (97.0, 68.0),
                           (195.0, 24.0), (104.0, 250.0),
                           (380.0, 521.0), (276.0, 446.0), (322.0, 392.0), (478.0, 470.0), (346.0, 440.0),
                           (641.0, 172.0)], 1):
        callout(cv, n, p)

    # ---- leyenda
    lx = mx + pw + 28
    g = ['<rect x="%.1f" y="%.1f" width="%d" height="%.1f" rx="10" fill="#ffffff" stroke="#e2ddd4"/>'
         % (lx, top, leg_w, ph)]
    yy = [top + 40]

    def t(x, y, txt, size, fill, weight="normal", extra=""):
        g.append('<text x="%.1f" y="%.1f" font-family="%s" font-size="%.1f" font-weight="%s" fill="%s" %s>%s</text>'
                 % (x, y, FONT, size, weight, fill, extra, txt))

    def title(txt, color="#2f3a45"):
        t(lx + 24, yy[0], esc(txt), 14.5, color, "bold", 'letter-spacing="1.6"')
        yy[0] += 29

    def item(n, head, tail="", more=()):
        g.append('<circle cx="%.1f" cy="%.1f" r="11.5" fill="#2f3a45"/>' % (lx + 36, yy[0] - 5))
        t(lx + 36, yy[0], "%d" % n, 12, "#fff", "bold", 'text-anchor="middle"')
        t(lx + 56, yy[0], '<tspan font-weight="bold">%s</tspan>%s' % (esc(head), esc(tail)), 14, "#2b2b2b")
        for ln in more:
            yy[0] += 19
            t(lx + 56, yy[0], esc(ln), 13.5, "#5a554d")
        yy[0] += 28

    def bullet(lines):
        g.append('<circle cx="%.1f" cy="%.1f" r="3.4" fill="%s"/>' % (lx + 31, yy[0] - 5, SAFE))
        for i, ln in enumerate(lines):
            t(lx + 44, yy[0], esc(ln), 13.5, "#2b2b2b" if i == 0 else "#5a554d")
            yy[0] += 19
        yy[0] += 8

    def rule():
        g.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#e2ddd4"/>'
                 % (lx + 24, yy[0] - 12, lx + leg_w - 24, yy[0] - 12))
        yy[0] += 14

    title("SALA DE ESTAR")
    item(1, "Sofá 3 plazas + chaise 240×160", " · modular, en piezas")
    item(2, "Mueble TV volado 200×40", " · TV 65\" colgada + barra de sonido")
    item(3, "Mesa de centro redonda Ø75", " · sin esquinas en el paso")
    item(4, "Alfombra 200×200", " · bajo las patas delanteras del sofá")
    item(5, "Puf Ø50", " · asiento extra que se mueve")
    item(6, "Luz: lámpara de pie + 2 apliques", " de lectura")
    item(7, "Corredera vista de 90", " · no invade el pasillo de 1,01")
    rule()
    title("ZONA DE JUEGO Y LECTURA")
    item(8, "Librería infantil 256×35", " · 7 módulos",
         ["libros de frente y cajas de tela; el módulo junto a la", "escalera, cerrado"])
    item(9, "Banco de lectura con arcón 110×45", " · aplique")
    item(10, "Alfombra de juego 170×120", " · con carretera")
    item(11, "Mesa infantil Ø60 + 2 taburetes", " · lámpara colgante")
    item(12, "Puf pera", " · rincón de cuentos")
    item(13, "Puerta de seguridad", " en la llegada de la escalera")
    rule()
    title("POR SER PLANTA SEGUNDA", SAFE)
    bullet(["Barandilla del hueco: 1,10 m de alto (el CTE pide 0,90 m",
            "si el desnivel es menor de 6 m), sin huecos de más de",
            "10 cm y sin barrotes horizontales que hagan de escalón."])
    bullet(["Franja de 60 cm junto a la barandilla sin nada a lo que",
            "subirse: la librería acaba a 66 cm y su último módulo es",
            "cerrado. Pufs y taburetes, lejos del hueco."])
    bullet(["Puerta de seguridad atornillada (no a presión) arriba",
            "de la escalera, abriendo hacia el descansillo."])
    bullet(["Librería y mueble de TV anclados a la pared (antivuelco)."])
    bullet(["Todo tiene que subir por la escalera: sofá modular y",
            "librería por módulos. Mide antes la escalera y el giro."])
    bullet(["Sala interior sin ventana: luz cálida (2700–3000 K),",
            "regulable y en capas: techo, apliques y lámpara de pie."])
    bullet(["Dormitorios en la misma planta: corredera con cepillos",
            "y alfombras para que la tele se oiga menos."])
    g.append('<path d="M %.1f %.1f L %.1f %.1f" stroke="%s" stroke-width="2.4" stroke-dasharray="8 5"/>'
             % (lx + 24, yy[0] - 5, lx + 62, yy[0] - 5, BLUE))
    t(lx + 72, yy[0], "Recorridos que quedan libres (pasillo 1,01 y banda 1,71)", 13.5, "#5a554d")
    yy[0] += 34
    rule()
    title("MATERIALES")
    sw = [(P.C["madera"], "Roble claro"), (P.C["madera_osc"], "Nogal"), (P.C["tela"], "Tela gris azulado"),
          (P.C["salvia"], "Verde salvia"), (P.C["mostaza"], "Mostaza"), (P.C["coral"], "Coral")]
    for i, (c_, name) in enumerate(sw):
        xx = lx + 24 + (i % 3) * 166
        y0 = yy[0] - 14 + (i // 3) * 34
        g.append('<rect x="%.1f" y="%.1f" width="24" height="24" rx="5" fill="%s" stroke="#00000022"/>' % (xx, y0, c_))
        t(xx + 32, y0 + 17, esc(name), 13.5, "#5a554d")
    yy[0] += 80
    for ln in ["Medidas tomadas de tu captura (75,4 px/m): compruébalas en obra",
               "antes de encargar muebles a medida."]:
        t(lx + 24, yy[0], esc(ln), 12.5, "#8a847a", extra='font-style="italic"')
        yy[0] += 17

    head = ('<text x="%d" y="46" font-family="%s" font-size="26" font-weight="bold" fill="#2b2b2b">'
            'Planta segunda · sala de estar y zona de juego</text>'
            '<text x="%d" y="74" font-family="%s" font-size="14" fill="#6b655c">Propuesta en planta · medidas '
            'tomadas de tus cotas (4,03 × 2,67 y 3,23 × 2,67) · cotas en m y cm</text>' % (mx, FONT, mx, FONT))
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' % (Wsvg, Hsvg, Wsvg, Hsvg)
           + '<rect width="100%" height="100%" fill="#f7f4ee"/>' + head
           + '<clipPath id="plano"><rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="6"/></clipPath>' % (mx, top, pw, ph)
           + '<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="6" fill="#ffffff" stroke="#e2ddd4"/>' % (mx, top, pw, ph)
           + '<g clip-path="url(#plano)">' + cv.svg() + "</g>" + "\n".join(g) + "</svg>")
    out = os.path.join(HERE, "planta2_propuesta.svg")
    open(out, "w", encoding="utf-8").write(svg)
    return out, Wsvg, Hsvg


# ================================================================= B) sobre la captura
BG = "#212830"


def overlay(shot):
    im = Image.open(shot).convert("RGB")
    cx0, cy0, cx1, cy1 = 492, 14, 1066, 466
    U = 2.4
    buf = io.BytesIO()
    im.crop((cx0, cy0, cx1, cy1)).save(buf, "PNG")
    Wi, Hi = (cx1 - cx0) * U, (cy1 - cy0) * U
    band = 58

    def T(x, y):
        return ((P.PX0 + x / P.K - cx0) * U, (P.PY0 - y / P.K - cy0) * U)
    k = U / P.K
    cv = Canvas(T, k)
    col = {name: aci(c) for name, c in P.CAPAS.items()}
    gray = aci(8)
    dash = 'stroke-dasharray="%.1f %.1f"' % (4 * k, 2.5 * k)

    for name, x, y, rot, layer in P.INSERCIONES:
        b = BL[name]
        if b["wipeout"]:
            cv.poly(place_pts(b["wipeout"], x, y, rot), BG)
        for it, runs in P.procesar(sorted(b["items"], key=lambda i: i.z)):
            c, sw = (col[layer], 1.0) if it.style == "main" else (gray, 0.6)
            if runs is not None:
                for r in runs:
                    cv.poly(place_pts(r, x, y, rot), stroke=c, sw=sw, closed=False,
                            extra=dash if it.kind == "dash" else "")
                continue
            g = place(it, x, y, rot)
            if g[0] == "circle":
                cv.circle(g[1], g[2], "none", c, sw)
            else:
                cv.poly(g[1], stroke=c, sw=sw, closed=g[2], extra=dash if g[0] == "dash" else "")

    # textos (MTEXT con mascara de fondo)
    for x, y, h, txt, layer in P.TEXTOS:
        lines = txt.split("\\P")
        hs = [h * (0.7 if ln.startswith("\\H0.7x;") else 1.0) for ln in lines]
        lines = [ln.replace("\\H0.7x;", "") for ln in lines]
        tot = hs[0] + 1.667 * sum(hs[1:])                  # alto del bloque de texto
        yy = y + tot / 2
        wmax = max(len(ln) * hh * 0.62 for ln, hh in zip(lines, hs))
        cv.rect(x - wmax / 2 - 2, y - tot / 2 - 2, x + wmax / 2 + 2, y + tot / 2 + 2, BG)
        for i, (ln, hh) in enumerate(zip(lines, hs)):
            yy -= hh if i == 0 else 1.667 * hh
            cv.text((x, yy), ln, hh * k / 0.716, col[layer])
    for p0, p1, layer in P.LIDERES:
        cv.line(p0, p1, col[layer], 1.0)
        cv.circle(p1, 1.6, col[layer])
    # cotas
    red = col["PS-COTAS"]
    for p1, p2, base, ang, txt in P.COTAS:
        if ang == 0:
            a, b = (p1[0], base[1]), (p2[0], base[1])
            L = abs(p2[0] - p1[0])
        else:
            a, b = (base[0], p1[1]), (base[0], p2[1])
            L = abs(p2[1] - p1[1])
        cv.line(a, b, red, 0.8)
        for q in (a, b):
            cv.line((q[0] - 2, q[1] - 2), (q[0] + 2, q[1] + 2), red, 1.3)
        m = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        lab = txt.replace("<>", "%d" % round(L))
        if ang == 0:
            cv.text((m[0], m[1] + 2.0), lab, 7 * k / 0.716, red)
        else:
            cv.text((m[0] - 2.0, m[1]), lab, 7 * k / 0.716, red, rot=90)

    legend = [("PS-MOBILIARIO", "mobiliario"), ("PS-ALFOMBRAS", "alfombras"), ("PS-ILUMINACION", "iluminación"),
              ("PS-CARPINTERIA", "corredera"), ("PS-SEGURIDAD", "seguridad"), ("PS-COTAS", "cotas")]
    items = []
    x = 18
    for layer, name in legend:
        items.append('<rect x="%d" y="%.1f" width="12" height="12" fill="%s"/>' % (x, Hi + 34, col[layer]))
        items.append('<text x="%d" y="%.1f" font-family="%s" font-size="13" fill="#c9ced6">%s  <tspan fill="#8b939e">%s'
                     '</tspan></text>' % (x + 18, Hi + 45, FONT, layer, name))
        x += 222
    b64 = base64.b64encode(buf.getvalue()).decode()
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">'
           % (Wi, Hi + band, Wi, Hi + band)
           + '<rect width="100%%" height="100%%" fill="%s"/>' % BG
           + '<image href="data:image/png;base64,%s" x="0" y="0" width="%.1f" height="%.1f" preserveAspectRatio="none" '
             'opacity="0.78"/>' % (b64, Wi, Hi)
           + cv.svg()
           + '<rect x="0" y="%.1f" width="%.1f" height="%d" fill="#161a20"/>' % (Hi, Wi, band)
           + '<text x="18" y="%.1f" font-family="%s" font-size="14" font-weight="bold" fill="#eef0f3">El DXF sobre '
             'tu plano (planta segunda) · capas y colores tal cual salen en AutoCAD</text>' % (Hi + 22, FONT)
           + "".join(items) + "</svg>")
    out = os.path.join(HERE, "planta2_sobre_tu_plano.svg")
    open(out, "w", encoding="utf-8").write(svg)
    return out, int(Wi), int(Hi + band)


if __name__ == "__main__":
    print(lamina())
    if len(sys.argv) > 1:
        print(overlay(sys.argv[1]))
