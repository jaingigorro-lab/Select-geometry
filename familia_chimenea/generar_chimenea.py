#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
generar_chimenea.py
===================
Chimenea de esquina minimalista: plantilla de calco (DXF 2D), modelo 3D de referencia (DXF con
entidades MESH) y lámina de presentación (PNG + PDF) para construir la FAMILIA de Revit.

Es AUTOCONTENIDO: solo necesita ezdxf, matplotlib y numpy. No genera el .rfa (formato propietario);
produce dibujos y modelos de referencia verificados para construir la familia en el Editor de familias.

Uso:
    python3 generar_chimenea.py [--tmp CARPETA]

    --tmp  carpeta temporal donde se guarda el PNG de comprobación del DXF 2D (por defecto, la del sistema).
Salida (en la carpeta del script):
    Chimenea_esquina_plantilla.dxf   planta + alzado + sección, mm, escala real 1:1 (texto para 1:20)
    Chimenea_esquina_3D.dxf          MESH cerradas por componente (zócalo, cuerpo con hueco, marco, vidrio, anclaje)
    Chimenea_esquina_diseno.png/.pdf lámina de presentación
Al final imprime la lista de comprobaciones (OK / FALLO).
"""
from __future__ import annotations

import argparse
import math
import os
import sys
import tempfile

import numpy as np
import ezdxf
from ezdxf import bbox as ezbbox
from ezdxf import zoom as ezzoom
from ezdxf.enums import TextEntityAlignment as TA

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon as MPolygon, PathPatch, Circle as MCircle
from matplotlib.path import Path as MPath
from matplotlib.collections import PolyCollection
from mpl_toolkits.mplot3d.art3d import Poly3DCollection

OUT_DIR = os.path.dirname(os.path.abspath(__file__))
F_PLANTILLA = "Chimenea_esquina_plantilla.dxf"
F_3D = "Chimenea_esquina_3D.dxf"
F_PNG = "Chimenea_esquina_diseno.png"
F_PDF = "Chimenea_esquina_diseno.pdf"

TITULO = "Chimenea de esquina minimalista — plantilla de calco para la familia de Revit"
AVISO = "No es una familia paramétrica: sirve para comprobar posiciones sobre la familia construida"

# ======================================================================================
# 1. PARÁMETROS Y GEOMETRÍA (contrato: spec.md)
# ======================================================================================
PAR = dict(W=1380.0, D=1420.0, CX=720.0, CY=920.0, S=100.0, ZH=60.0, ZR=25.0,
           OW=850.0, OH=600.0, OZ=400.0, OD=450.0, MF=20.0, MD=40.0, VG=10.0, H=2600.0)
T_MURO = 200.0          # grosor simbólico del muro en los dibujos
Z_CORTE = 1200.0        # plano de corte de la planta
DESV_MM, DESV_DEG = 59.0, 2.39

V2 = lambda x, y: np.array([float(x), float(y)])


def fmt(x, nd=0):
    """Número con coma decimal (español); sin ceros sobrantes si nd=0."""
    s = f"{x:.{nd}f}".replace(".", ",")
    return s


def shoelace(pts):
    a = 0.0
    n = len(pts)
    for i in range(n):
        x0, y0 = pts[i][0], pts[i][1]
        x1, y1 = pts[(i + 1) % n][0], pts[(i + 1) % n][1]
        a += x0 * y1 - x1 * y0
    return a / 2.0


def ccw(pts):
    return list(pts) if shoelace(pts) > 0 else list(reversed(pts))


class Geo:
    """Geometría derivada. Origen O = esquina interior; +X a la derecha; +Y hacia el muro de fondo."""

    def __init__(self, **kw):
        p = dict(PAR)
        p.update(kw)
        self.__dict__.update(p)
        W, D, CX, CY = self.W, self.D, self.CX, self.CY
        self.O = V2(0, 0)
        self.B = V2(W, 0)
        self.C = V2(W, -(D - CY))
        self.Dv = V2(W - CX, -D)
        self.E = V2(0, -D)
        self.Q = V2(W, -D)                                  # esquina virtual (catetos CX, CY)
        v = self.C - self.Dv
        self.L = float(np.hypot(*v))                        # longitud del chaflán
        self.d = v / self.L                                 # dirección Dv -> C
        self.n = V2(-self.d[1], self.d[0])                  # normal interior (hacia la esquina)
        self.M = (self.C + self.Dv) / 2
        self.ang = math.degrees(math.atan2(CY, CX))         # ángulo sobre el eje X
        self.dO = float(self.n @ (self.O - self.M))         # distancia de O al plano del chaflán
        self.mar = (self.L - self.OW) / 2                   # margen del hueco a cada lado
        self.u1, self.u2 = self.mar, self.mar + self.OW
        self.P1 = self.pl(self.u1, 0)
        self.P2 = self.pl(self.u2, 0)
        self.P3 = self.pl(self.u2, self.OD)
        self.P4 = self.pl(self.u1, self.OD)
        self.pent = [self.O, self.B, self.C, self.Dv, self.E]          # perfil visible
        self.area = abs(shoelace(self.pent))
        # zócalo retranqueado ZR en las tres caras vistas
        k0 = float(self.n @ self.M) + self.ZR
        xc, yc = W - self.ZR, -(D - self.ZR)
        self.Bz = V2(xc, 0)
        self.Cz = V2(xc, (k0 - self.n[0] * xc) / self.n[1])
        self.Dz = V2((k0 - self.n[1] * yc) / self.n[0], yc)
        self.Ez = V2(0, yc)
        self.zoc = [self.O, self.Bz, self.Cz, self.Dz, self.Ez]
        self.uz0 = float((self.Dz - self.Dv) @ self.d)     # extremos del zócalo en el alzado
        self.uz1 = float((self.Cz - self.Dv) @ self.d)
        # profundidad del eje del hogar hasta el muro izquierdo (X = 0) y hasta la esquina O
        self.tW = float(-self.M[0] / self.n[0])
        self.yW = float(self.M[1] + self.tW * self.n[1])
        # anclaje oculto (en L) dentro de los muros
        S = self.S
        self.anc = [V2(-S, S), V2(W, S), V2(W, 0), V2(0, 0), V2(0, -D), V2(-S, -D)]

    # puntos en los marcos locales
    def pl(self, u, t):
        """Planta: Dv + u*d + t*n."""
        return self.Dv + u * self.d + t * self.n

    def p3(self, u, t, z):
        p = self.pl(u, t)
        return (float(p[0]), float(p[1]), float(z))

    # volúmenes esperados (fórmulas analíticas, independientes de las mallas)
    def vol_expected(self):
        e = {}
        e["cuerpo"] = self.area * (self.H - self.ZH) - self.OW * self.OH * self.OD
        hQ = self.CX * self.CY / self.L                       # altura del triángulo recortado
        # Q' = esquina de la caja del zócalo; la recta del chaflán se desplaza ZR hacia dentro
        qq = V2(-self.ZR, self.ZR)
        dist = hQ - float(self.n @ qq) + self.ZR              # altura del triángulo recortado del zócalo
        s = dist / hQ
        a_z = (self.W - self.ZR) * (self.D - self.ZR) - 0.5 * self.CX * self.CY * s * s
        e["zocalo"] = a_z * self.ZH
        e["marco"] = (self.OW * self.OH - (self.OW - 2 * self.MF) * (self.OH - 2 * self.MF)) * self.MD
        e["vidrio"] = (self.OW - 2 * self.MF) * (self.OH - 2 * self.MF) * self.VG
        e["hueco"] = self.OW * self.OH * self.OD
        # anclaje: L = (W+S)*S + S*D  (rectángulo superior + banda izquierda) -> área exacta
        e["anclaje"] = ((self.W + self.S) * self.S + self.S * self.D) * self.H
        return e


# ======================================================================================
# 2. UTILIDADES GEOMÉTRICAS 2D
# ======================================================================================
def seg_intersect(p1, p2, p3, p4, eps=1e-9):
    """True si los segmentos p1p2 y p3p4 se cortan (incluye roces)."""
    def orient(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])

    def on_seg(a, b, c):
        return (min(a[0], b[0]) - eps <= c[0] <= max(a[0], b[0]) + eps and
                min(a[1], b[1]) - eps <= c[1] <= max(a[1], b[1]) + eps)
    o1, o2, o3, o4 = orient(p1, p2, p3), orient(p1, p2, p4), orient(p3, p4, p1), orient(p3, p4, p2)
    if ((o1 > eps and o2 < -eps) or (o1 < -eps and o2 > eps)) and ((o3 > eps and o4 < -eps) or (o3 < -eps and o4 > eps)):
        return True
    if abs(o1) <= eps and on_seg(p1, p2, p3): return True
    if abs(o2) <= eps and on_seg(p1, p2, p4): return True
    if abs(o3) <= eps and on_seg(p3, p4, p1): return True
    if abs(o4) <= eps and on_seg(p3, p4, p2): return True
    return False


def polygon_is_simple(pts):
    n = len(pts)
    for i in range(n):
        for j in range(i + 1, n):
            if j == i + 1 or (i == 0 and j == n - 1):
                # lados contiguos: solo deben compartir el vértice
                a, b, c = (pts[i], pts[(i + 1) % n], pts[(i + 2) % n]) if j == i + 1 else (pts[j], pts[(j + 1) % n], pts[(j + 2) % n])
                if abs((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])) < 1e-9:
                    return False   # tres vértices alineados: lado degenerado/solapado
                continue
            if seg_intersect(pts[i], pts[(i + 1) % n], pts[j], pts[(j + 1) % n]):
                return False
    return True


def point_in_polygon(p, poly, tol=1e-6):
    """Dentro o sobre el borde (con tolerancia)."""
    x, y = p[0], p[1]
    n = len(poly)
    inside = False
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        # sobre el borde
        cr = (b[0] - a[0]) * (y - a[1]) - (b[1] - a[1]) * (x - a[0])
        ln = math.hypot(b[0] - a[0], b[1] - a[1])
        if abs(cr) / ln <= tol and min(a[0], b[0]) - tol <= x <= max(a[0], b[0]) + tol and min(a[1], b[1]) - tol <= y <= max(a[1], b[1]) + tol:
            return True
        if (a[1] > y) != (b[1] > y):
            xi = a[0] + (y - a[1]) * (b[0] - a[0]) / (b[1] - a[1])
            if xi > x:
                inside = not inside
    return inside


# ======================================================================================
# 3. MALLAS 3D
# ======================================================================================
def _newell(pts):
    n = np.zeros(3)
    m = len(pts)
    for i in range(m):
        a, b = np.asarray(pts[i], float), np.asarray(pts[(i + 1) % m], float)
        n[0] += (a[1] - b[1]) * (a[2] + b[2])
        n[1] += (a[2] - b[2]) * (a[0] + b[0])
        n[2] += (a[0] - b[0]) * (a[1] + b[1])
    return n


def _ear_clip(pts, normal):
    """Triangula un polígono plano (orden dado) con 'oreja'. Devuelve índices locales de triángulos con el mismo
    sentido que el polígono. Ignora vértices alineados (no genera triángulos degenerados)."""
    P = np.asarray(pts, float)
    k = int(np.argmax(np.abs(normal)))
    ax = [i for i in range(3) if i != k]
    Q = P[:, ax]
    sgn = 1.0 if normal[k] > 0 else -1.0
    # el sentido en el plano proyectado debe coincidir con el signo de la normal
    if k == 1:
        sgn = -sgn          # al proyectar (z, x) la orientación se invierte respecto a (x, z)
    idx = list(range(len(P)))
    tris = []

    def cross(a, b, c):
        return ((Q[b][0] - Q[a][0]) * (Q[c][1] - Q[a][1]) - (Q[b][1] - Q[a][1]) * (Q[c][0] - Q[a][0])) * sgn

    def inside(p, a, b, c):
        d1, d2, d3 = cross(a, b, p), cross(b, c, p), cross(c, a, p)
        return d1 >= -1e-7 and d2 >= -1e-7 and d3 >= -1e-7

    guard = 0
    scale = max(1.0, float(np.ptp(Q)) ** 2)
    while len(idx) > 3 and guard < 10000:
        guard += 1
        found = False
        m = len(idx)
        for i in range(m):
            a, b, c = idx[(i - 1) % m], idx[i], idx[(i + 1) % m]
            if cross(a, b, c) <= 1e-9 * scale:
                continue
            if any(inside(p, a, b, c) for p in idx if p not in (a, b, c)):
                continue
            tris.append((a, b, c))
            del idx[i]
            found = True
            break
        if not found:                      # polígono casi degenerado: recorta el vértice más convexo
            m = len(idx)
            best = max(range(m), key=lambda i: cross(idx[(i - 1) % m], idx[i], idx[(i + 1) % m]))
            a, b, c = idx[(best - 1) % m], idx[best], idx[(best + 1) % m]
            tris.append((a, b, c))
            del idx[best]
    if len(idx) == 3 and cross(*idx) > 1e-9 * scale:
        tris.append(tuple(idx))
    return tris


class Mesh:
    """Malla de polígonos planos con vértices compartidos y normales hacia fuera."""

    def __init__(self, name):
        self.name = name
        self.verts = []
        self._idx = {}
        self.faces = []        # polígonos (lista de índices), sentido antihorario visto desde fuera
        self.tags = []         # etiqueta por cara (p. ej. "hogar" para las 5 caras interiores del vaciado)

    def vid(self, p):
        key = (round(float(p[0]), 5), round(float(p[1]), 5), round(float(p[2]), 5))
        i = self._idx.get(key)
        if i is None:
            i = len(self.verts)
            self._idx[key] = i
            self.verts.append(key)
        return i

    def add(self, pts, outward, tag=""):
        """Añade una cara; invierte el orden si su normal no mira hacia 'outward'."""
        pts = [tuple(map(float, p)) for p in pts]
        nrm = _newell(pts)
        if float(np.dot(nrm, np.asarray(outward, float))) < 0:
            pts = pts[::-1]
        self.faces.append([self.vid(p) for p in pts])
        self.tags.append(tag)

    def prism(self, poly2d, z0, z1):
        """Prisma recto sobre un polígono 2D (cualquier sentido; puede ser cóncavo)."""
        pl = ccw([(float(p[0]), float(p[1])) for p in poly2d])
        n = len(pl)
        for i in range(n):
            a, b = pl[i], pl[(i + 1) % n]
            out = (b[1] - a[1], -(b[0] - a[0]), 0.0)
            self.add([(a[0], a[1], z0), (b[0], b[1], z0), (b[0], b[1], z1), (a[0], a[1], z1)], out)
        self.add([(p[0], p[1], z1) for p in pl], (0, 0, 1))
        self.add([(p[0], p[1], z0) for p in pl], (0, 0, -1))

    # --- derivados ---
    def tris(self):
        """Caras triangulando solo las de más de 4 vértices (AutoCAD admite triángulos y cuadriláteros)."""
        out = []
        V = np.asarray(self.verts)
        for f in self.faces:
            if len(f) <= 4:
                out.append(list(f))
            else:
                pts = V[f]
                for a, b, c in _ear_clip(pts, _newell(pts)):
                    out.append([f[a], f[b], f[c]])
        return out

    def volume(self, faces=None, verts=None):
        V = np.asarray(self.verts if verts is None else verts, float)
        vol = 0.0
        for f in (self.tris() if faces is None else faces):
            for i in range(1, len(f) - 1):
                a, b, c = V[f[0]], V[f[i]], V[f[i + 1]]
                vol += float(np.dot(a, np.cross(b, c))) / 6.0
        return vol


def mesh_stats(faces, verts):
    """Comprobación topológica de una malla leída del DXF. Devuelve dict con
    aristas_no2 (aristas compartidas por != 2 caras), dirigidas_rep (aristas dirigidas repetidas = normales
    incoherentes), caras_degeneradas, volumen con signo."""
    und, dire = {}, {}
    for f in faces:
        m = len(f)
        for i in range(m):
            a, b = f[i], f[(i + 1) % m]
            k = (min(a, b), max(a, b))
            und[k] = und.get(k, 0) + 1
            dire[(a, b)] = dire.get((a, b), 0) + 1
    V = np.asarray(verts, float)
    deg = 0
    vol = 0.0
    for f in faces:
        pts = V[list(f)]
        if np.linalg.norm(_newell(pts)) < 1e-6:
            deg += 1
        for i in range(1, len(f) - 1):
            vol += float(np.dot(V[f[0]], np.cross(V[f[i]], V[f[i + 1]]))) / 6.0
    return dict(aristas=len(und),
                aristas_no2=sum(1 for v in und.values() if v != 2),
                dirigidas_rep=sum(1 for v in dire.values() if v != 1),
                degeneradas=deg, volumen=vol)


def build_meshes(G: Geo):
    """Componentes: zócalo, cuerpo con el hueco real, marco, vidrio y anclaje."""
    z0, z1 = G.ZH, G.H
    OZ, OH, OD = G.OZ, G.OH, G.OD
    zt = OZ + OH
    u1, u2, L = G.u1, G.u2, G.L
    d3 = (float(G.d[0]), float(G.d[1]), 0.0)
    n3 = (float(G.n[0]), float(G.n[1]), 0.0)
    mn3 = tuple(-x for x in n3)
    md3 = tuple(-x for x in d3)

    def Pz(p, z):
        return (float(p[0]), float(p[1]), float(z))

    def F(u, z):                                  # punto sobre la cara del chaflán
        return G.p3(u, 0.0, z)

    # ---------------- cuerpo ----------------
    body = Mesh("CUERPO")
    O, B, C, Dv, E = G.O, G.B, G.C, G.Dv, G.E
    for a, b in ((O, E), (E, Dv), (C, B), (B, O)):                      # caras laterales sin hueco
        out = (float(b[1] - a[1]), float(-(b[0] - a[0])), 0.0)
        body.add([Pz(a, z0), Pz(b, z0), Pz(b, z1), Pz(a, z1)], out)
    # tapas: el lado del chaflán lleva los vértices P1 y P2 (alineados) para que las aristas coincidan con las del hueco
    pent = [Pz(O, 0), Pz(E, 0), Pz(Dv, 0), F(u1, 0), F(u2, 0), Pz(C, 0), Pz(B, 0)]      # antihorario
    body.add([(p[0], p[1], z1) for p in pent], (0, 0, 1))
    body.add([(p[0], p[1], z0) for p in pent], (0, 0, -1))
    # cara del chaflán: cuatro paños alrededor del hueco
    body.add([F(0, z0), F(u1, z0), F(u1, OZ), F(u1, zt), F(u1, z1), F(0, z1)], mn3)
    body.add([F(u2, z0), F(L, z0), F(L, z1), F(u2, z1), F(u2, zt), F(u2, OZ)], mn3)
    body.add([F(u1, z0), F(u2, z0), F(u2, OZ), F(u1, OZ)], mn3)
    body.add([F(u1, zt), F(u2, zt), F(u2, z1), F(u1, z1)], mn3)
    # las 5 caras interiores del vaciado (normales hacia el interior del hueco = hacia fuera del sólido)
    g3 = G.p3
    body.add([g3(u1, 0, OZ), g3(u2, 0, OZ), g3(u2, OD, OZ), g3(u1, OD, OZ)], (0, 0, 1), "hogar")      # fondo inferior
    body.add([g3(u1, 0, zt), g3(u2, 0, zt), g3(u2, OD, zt), g3(u1, OD, zt)], (0, 0, -1), "hogar")     # techo
    body.add([g3(u1, 0, OZ), g3(u1, OD, OZ), g3(u1, OD, zt), g3(u1, 0, zt)], d3, "hogar")             # lateral izquierdo
    body.add([g3(u2, 0, OZ), g3(u2, OD, OZ), g3(u2, OD, zt), g3(u2, 0, zt)], md3, "hogar")            # lateral derecho
    body.add([g3(u1, OD, OZ), g3(u2, OD, OZ), g3(u2, OD, zt), g3(u1, OD, zt)], mn3, "hogar")          # fondo del hogar

    # ---------------- zócalo ----------------
    zoc = Mesh("ZOCALO")
    zoc.prism([tuple(p) for p in G.zoc], 0.0, G.ZH)

    # ---------------- marco (anillo) ----------------
    mar = Mesh("MARCO")
    mf = G.MF
    outer = [(u1, OZ), (u2, OZ), (u2, zt), (u1, zt)]
    inner = [(u1 + mf, OZ + mf), (u2 - mf, OZ + mf), (u2 - mf, zt - mf), (u1 + mf, zt - mf)]
    t0, t1 = 0.0, G.MD
    for i in range(4):
        j = (i + 1) % 4
        quad = [outer[i], outer[j], inner[j], inner[i]]
        mar.add([g3(u, t0, z) for u, z in quad], mn3)               # cara vista
        mar.add([g3(u, t1, z) for u, z in quad], n3)                # cara trasera
    out_dirs = [(0, 0, -1), d3, (0, 0, 1), md3]                      # exterior: abajo, derecha, arriba, izquierda
    in_dirs = [(0, 0, 1), md3, (0, 0, -1), d3]                      # interior del anillo (hacia el hueco libre)
    for i in range(4):
        j = (i + 1) % 4
        a, b = outer[i], outer[j]
        mar.add([g3(a[0], t0, a[1]), g3(b[0], t0, b[1]), g3(b[0], t1, b[1]), g3(a[0], t1, a[1])], out_dirs[i])
        a, b = inner[i], inner[j]
        mar.add([g3(a[0], t0, a[1]), g3(b[0], t0, b[1]), g3(b[0], t1, b[1]), g3(a[0], t1, a[1])], in_dirs[i])

    # ---------------- vidrio ----------------
    gl = Mesh("VIDRIO")
    ta, tb = (G.MD - G.VG) / 2, (G.MD + G.VG) / 2
    ua, ub = u1 + mf, u2 - mf
    za, zb = OZ + mf, zt - mf
    gl.add([g3(ua, ta, za), g3(ub, ta, za), g3(ub, ta, zb), g3(ua, ta, zb)], mn3)
    gl.add([g3(ua, tb, za), g3(ub, tb, za), g3(ub, tb, zb), g3(ua, tb, zb)], n3)
    gl.add([g3(ua, ta, za), g3(ub, ta, za), g3(ub, tb, za), g3(ua, tb, za)], (0, 0, -1))
    gl.add([g3(ua, ta, zb), g3(ub, ta, zb), g3(ub, tb, zb), g3(ua, tb, zb)], (0, 0, 1))
    gl.add([g3(ua, ta, za), g3(ua, tb, za), g3(ua, tb, zb), g3(ua, ta, zb)], md3)
    gl.add([g3(ub, ta, za), g3(ub, tb, za), g3(ub, tb, zb), g3(ub, ta, zb)], d3)

    # ---------------- anclaje (oculto, dentro de los muros) ----------------
    anc = Mesh("ANCLAJE")
    anc.prism([tuple(p) for p in G.anc], 0.0, G.H)
    return dict(zocalo=zoc, cuerpo=body, marco=mar, vidrio=gl, anclaje=anc)


# ======================================================================================
# 4. LIENZOS (un mismo dibujo se emite a DXF, a matplotlib o solo se mide)
# ======================================================================================
EMF = 1.0 / 0.716          # em / altura de mayúscula (Arial)
_W = {**{c: 0.556 for c in "0123456789"}, ",": 0.278, ".": 0.278, " ": 0.278, ":": 0.278, ";": 0.278, "/": 0.278,
      "i": 0.222, "l": 0.222, "j": 0.222, "t": 0.278, "f": 0.278, "r": 0.333, "I": 0.278, "(": 0.333, ")": 0.333,
      "-": 0.333, "=": 0.584, "+": 0.584, "×": 0.584, "±": 0.584, "°": 0.4, "—": 1.0,
      "–": 0.556, "m": 0.833, "w": 0.722, "M": 0.833, "W": 0.944, "·": 0.278, "→": 1.0, "Σ": 0.7}


def tw(s, h):
    """Ancho estimado (mm) de un texto de altura de mayúscula h (Arial)."""
    w = 0.0
    for ch in s:
        if ch in _W:
            w += _W[ch]
        elif ch.isupper():
            w += 0.68
        else:
            w += 0.53
    return w * h * EMF


class BBox:
    def __init__(self):
        self.x0 = self.y0 = 1e30
        self.x1 = self.y1 = -1e30

    def add(self, x, y):
        self.x0, self.x1 = min(self.x0, x), max(self.x1, x)
        self.y0, self.y1 = min(self.y0, y), max(self.y1, y)

    def valid(self):
        return self.x1 >= self.x0

    def __repr__(self):
        return f"BBox({self.x0:.0f},{self.y0:.0f},{self.x1:.0f},{self.y1:.0f})"


# colores (RGB)
BODY_RGB = (228, 224, 216)
ZOC_RGB = (150, 146, 138)
HOGAR_RGB = (58, 58, 60)
MARCO_RGB = (14, 14, 14)
VIDRIO_RGB = (132, 200, 226)
WALL_RGB = (206, 206, 206)
WALL_PAT_RGB = (110, 110, 110)
RED = (200, 40, 40)

LAYERS = {   # nombre: (ACI, grosor 1/100 mm, color matplotlib, grosor pt matplotlib, RGB verdadero de la capa o None)
    "CHM-MURO":    (8, 35, "#555555", 1.1, None),
    "CHM-PERFIL":  (7, 70, "#141414", 2.2, None),
    "CHM-ZOCALO":  (30, 25, "#8a5a2b", 1.0, (138, 90, 43)),
    "CHM-ANCLAJE": (9, 18, "#8c8c8c", 0.9, None),
    "CHM-HOGAR":   (1, 35, "#c0392b", 1.2, None),
    "CHM-MARCO":   (7, 50, "#141414", 1.5, None),
    "CHM-VIDRIO":  (4, 25, "#1b94b8", 1.0, (27, 148, 184)),
    "CHM-EJES":    (1, 18, "#c0392b", 0.8, None),
    "CHM-COTAS":   (3, 18, "#0b6b5d", 0.7, (11, 107, 93)),
    "CHM-TEXTO":   (7, 18, "#141414", 0.5, None),
    "CHM-RAYADOS": (8, 9, "#777777", 0.4, None),
    "CHM-CAJETIN": (7, 50, "#141414", 1.4, None),
}
LT_NAMES = ("DASHED", "CENTER", "DASHDOT")


class Canvas:
    """Interfaz común. Las coordenadas de usuario se desplazan por (ox, oy)."""

    def __init__(self):
        self.ox = 0.0
        self.oy = 0.0
        self.bb = BBox()
        self.boxes = []      # cajas de texto orientadas [(esquinas, texto, etiqueta)]
        self.segs = []       # segmentos de línea [(p0, p1, capa)]
        self.tag = ""

    def T(self, p):
        return (float(p[0]) + self.ox, float(p[1]) + self.oy)

    def line(self, pts, layer, closed=False, ls=None, lw=None, color=None):
        P = [self.T(p) for p in pts]
        for p in P:
            self.bb.add(*p)
        seg = list(zip(P[:-1], P[1:])) + ([(P[-1], P[0])] if closed else [])
        for a, b in seg:
            self.segs.append((a, b, layer, ls))
        self._line(P, layer, closed, ls, lw, color)

    def fill(self, rings, layer, color):
        R = [[self.T(p) for p in r] for r in rings]
        for p in R[0]:
            self.bb.add(*p)
        self._fill(R, layer, color)

    def pattern(self, ring, layer, name, scale, color, angle=0.0):
        R = [self.T(p) for p in ring]
        for p in R:
            self.bb.add(*p)
        self._pattern(R, layer, name, scale, color, angle)

    def arc(self, ctr, r, a0, a1, layer, ls=None, lw=None, color=None):
        ctr = self.T(ctr)
        for a in np.linspace(math.radians(a0), math.radians(a1), 24):
            self.bb.add(ctr[0] + r * math.cos(a), ctr[1] + r * math.sin(a))
        self._arc(ctr, r, a0, a1, layer, ls, lw, color)

    def circle(self, ctr, r, layer, color=None, fillrgb=None):
        ctr = self.T(ctr)
        self.bb.add(ctr[0] - r, ctr[1] - r)
        self.bb.add(ctr[0] + r, ctr[1] + r)
        self._circle(ctr, r, layer, color, fillrgb)

    def text(self, s, p, h, a="bl", rot=0.0, layer="CHM-TEXTO", color=None, tag=""):
        p = self.T(p)
        w = tw(s, h)
        x0 = {"l": 0.0, "c": -w / 2, "r": -w}[a[1]]
        y0 = {"b": 0.0, "m": -h / 2, "t": -h}[a[0]]
        th = math.radians(rot)
        co, si = math.cos(th), math.sin(th)
        cs = []
        for lx, ly in ((x0, y0), (x0 + w, y0), (x0 + w, y0 + h), (x0, y0 + h)):
            q = (p[0] + lx * co - ly * si, p[1] + lx * si + ly * co)
            cs.append(q)
            self.bb.add(*q)
        self.boxes.append((cs, s, tag or s))
        self._text(s, p, h, a, rot, layer, color)

    # --- implementaciones ---
    def _line(self, *a): pass
    def _fill(self, *a): pass
    def _pattern(self, *a): pass
    def _arc(self, *a): pass
    def _circle(self, *a): pass
    def _text(self, *a): pass


class MeasureCanvas(Canvas):
    pass


def _rgb_to_aci_or_rgb(color):
    """Devuelve ('aci', n) o ('rgb', (r,g,b)) o None."""
    if color is None:
        return None
    if isinstance(color, int):
        return ("aci", color)
    return ("rgb", tuple(int(v) for v in color))


class DxfCanvas(Canvas):
    _TA = {("b", "l"): TA.BOTTOM_LEFT, ("b", "c"): TA.BOTTOM_CENTER, ("b", "r"): TA.BOTTOM_RIGHT,
           ("m", "l"): TA.MIDDLE_LEFT, ("m", "c"): TA.MIDDLE_CENTER, ("m", "r"): TA.MIDDLE_RIGHT,
           ("t", "l"): TA.TOP_LEFT, ("t", "c"): TA.TOP_CENTER, ("t", "r"): TA.TOP_RIGHT}

    def __init__(self, doc):
        super().__init__()
        self.doc = doc
        self.msp = doc.modelspace()

    def _style(self, e, ls, lw, color):
        if ls:
            e.dxf.linetype = ls
        if lw:
            e.dxf.lineweight = int(lw)
        col = _rgb_to_aci_or_rgb(color)
        if col:
            if col[0] == "aci":
                e.dxf.color = col[1]
            else:
                e.rgb = col[1]

    def _line(self, P, layer, closed, ls, lw, color):
        e = self.msp.add_lwpolyline(P, close=closed, dxfattribs={"layer": layer})
        self._style(e, ls, lw, color)

    def _fill(self, R, layer, color):
        h = self.msp.add_hatch(dxfattribs={"layer": layer})
        h.set_solid_fill(color=7, rgb=ezdxf.colors.RGB(*color))
        h.paths.add_polyline_path(R[0], is_closed=True, flags=ezdxf.const.BOUNDARY_PATH_EXTERNAL)
        for r in R[1:]:
            h.paths.add_polyline_path(r, is_closed=True, flags=ezdxf.const.BOUNDARY_PATH_OUTERMOST)

    def _pattern(self, R, layer, name, scale, color, angle):
        col = _rgb_to_aci_or_rgb(color)
        h = self.msp.add_hatch(color=col[1] if col and col[0] == "aci" else 8, dxfattribs={"layer": layer})
        h.set_pattern_fill(name, scale=scale, angle=angle)
        if col and col[0] == "rgb":
            h.rgb = col[1]
        h.paths.add_polyline_path(R, is_closed=True)

    def _arc(self, ctr, r, a0, a1, layer, ls, lw, color):
        e = self.msp.add_arc(ctr, r, a0, a1, dxfattribs={"layer": layer})
        self._style(e, ls, lw, color)

    def _circle(self, ctr, r, layer, color, fillrgb):
        if fillrgb is not None:
            hh = self.msp.add_hatch(dxfattribs={"layer": layer})
            hh.set_solid_fill(color=7, rgb=ezdxf.colors.RGB(*fillrgb))
            hh.paths.add_edge_path().add_arc(ctr, r, 0, 360)
        e = self.msp.add_circle(ctr, r, dxfattribs={"layer": layer})
        self._style(e, None, None, color)

    def _text(self, s, p, h, a, rot, layer, color):
        t = self.msp.add_text(s, height=h, dxfattribs={"layer": layer, "rotation": rot})
        t.set_placement(p, align=self._TA[(a[0], a[1])])
        col = _rgb_to_aci_or_rgb(color)
        if col:
            if col[0] == "aci":
                t.dxf.color = col[1]
            else:
                t.rgb = col[1]


_LS_MPL = {"DASHED": (0, (5.0, 2.2)), "CENTER": (0, (9.0, 2.0, 2.0, 2.0)), "DASHDOT": (0, (6.0, 2.0, 1.5, 2.0))}
_HATCH_MPL = {"ANSI31": "////", "ANSI37": "xxxx", "DOTS": "....", "ANSI32": "\\\\\\\\"}


class MplCanvas(Canvas):
    """Dibuja en un Axes de matplotlib. 'ptmm' = puntos por mm de datos (para tamaños de texto)."""

    def __init__(self, ax, ptmm, lw_scale=1.0):
        super().__init__()
        self.ax = ax
        self.ptmm = ptmm
        self.k = 0
        self.lws = lw_scale

    def _z(self):
        self.k += 1
        return 1.0 + self.k * 1e-4

    @staticmethod
    def _c(rgb):
        return tuple(v / 255.0 for v in rgb)

    def _lcolor(self, layer, color):
        if color is None:
            return LAYERS[layer][2]
        if isinstance(color, int):
            return {1: "#c0392b", 3: "#0b6b5d", 4: "#1b94b8", 5: "#2a4fb0", 7: "#141414", 8: "#777777"}.get(color, "#141414")
        return self._c(color)

    def _line(self, P, layer, closed, ls, lw, color):
        xs = [p[0] for p in P] + ([P[0][0]] if closed else [])
        ys = [p[1] for p in P] + ([P[0][1]] if closed else [])
        w = (LAYERS[layer][3] if lw is None else LAYERS[layer][3] * lw / max(LAYERS[layer][1], 1)) * self.lws
        self.ax.plot(xs, ys, color=self._lcolor(layer, color), lw=w, ls=_LS_MPL.get(ls, "-"),
                     solid_capstyle="butt", dash_capstyle="butt", zorder=self._z())

    def _path(self, R):
        verts, codes = [], []
        for i, r in enumerate(R):
            rr = list(r)
            a = shoelace(rr)
            if (i == 0 and a < 0) or (i > 0 and a > 0):
                rr = rr[::-1]
            verts += rr + [rr[0]]
            codes += [MPath.MOVETO] + [MPath.LINETO] * (len(rr) - 1) + [MPath.CLOSEPOLY]
        return MPath(verts, codes)

    def _fill(self, R, layer, color):
        self.ax.add_patch(PathPatch(self._path(R), fc=self._c(color), ec="none", lw=0, zorder=self._z()))

    def _pattern(self, R, layer, name, scale, color, angle):
        col = self._lcolor(layer, color)
        self.ax.add_patch(PathPatch(self._path([R]), fc="none", ec=col, hatch=_HATCH_MPL.get(name, "////"),
                                    lw=0, zorder=self._z()))

    def _arc(self, ctr, r, a0, a1, layer, ls, lw, color):
        t = np.radians(np.linspace(a0, a1, 60))
        self._line(list(zip(ctr[0] + r * np.cos(t), ctr[1] + r * np.sin(t))), layer, False, ls, lw, color)

    def _circle(self, ctr, r, layer, color, fillrgb):
        self.ax.add_patch(MCircle(ctr, r, fc=self._c(fillrgb) if fillrgb else "none", ec=self._lcolor(layer, color),
                                  lw=LAYERS[layer][3] * self.lws, zorder=self._z()))

    def _text(self, s, p, h, a, rot, layer, color):
        ha = {"l": "left", "c": "center", "r": "right"}[a[1]]
        va = {"b": "bottom", "m": "center", "t": "top"}[a[0]]
        col = self._lcolor(layer, color)
        self.ax.text(p[0], p[1], s, fontsize=h * self.ptmm * EMF, ha=ha, va=va, rotation=rot,
                     rotation_mode="anchor", color=col, zorder=900, family=FONT_FAMILY)


FONT_FAMILY = ["Liberation Sans", "Arial", "DejaVu Sans"]


# ======================================================================================
# 5. ELEMENTOS DE DIBUJO COMUNES (cotas, zigzag, flechas)
# ======================================================================================
def dim(c, p0, p1, q0, q1, label, h, *, above=True, out=None, ext=(True, True), s0=None, s1=None,
        tk=None, gap=None, over=None, layer="CHM-COTAS", tag=""):
    """Cota lineal con trazos oblicuos. p0,p1 = puntos medidos; q0,q1 = extremos de la línea de cota."""
    p0, p1, q0, q1 = (np.asarray(v, float) for v in (p0, p1, q0, q1))
    tk = 0.42 * h if tk is None else tk
    gap = 0.3 * h if gap is None else gap
    over = 0.45 * h if over is None else over
    v = q1 - q0
    Ld = float(np.hypot(*v))
    vh = v / Ld
    for p, q, sp, use in ((p0, q0, s0, ext[0]), (p1, q1, s1, ext[1])):
        if not use:
            continue
        a = np.asarray(sp if sp is not None else p, float)
        dv = q - a
        dl = float(np.hypot(*dv))
        if dl < 1e-9:
            continue
        dh = dv / dl
        c.line([a + dh * min(gap, dl * 0.5), q + dh * over], layer)
    c.line([q0, q1], layer)
    nl = np.array([-vh[1], vh[0]])
    tv = (vh + nl) / math.sqrt(2.0)
    for q in (q0, q1):
        c.line([q - tv * tk, q + tv * tk], layer, lw=35)
    ang = math.degrees(math.atan2(v[1], v[0]))
    if ang > 90 + 1e-6:
        ang -= 180
    elif ang <= -90 + 1e-6:
        ang += 180
    th = math.radians(ang)
    up = np.array([-math.sin(th), math.cos(th)])
    w = tw(label, h)
    mid = (q0 + q1) / 2
    if out is None:
        ctr = mid
    elif out == "a":
        ctr = q0 - vh * (tk + 0.45 * h + w / 2)
    else:
        ctr = q1 + vh * (tk + 0.45 * h + w / 2)
    off = 0.28 * h
    pos = ctr + (up * off if above else -up * off)
    c.text(label, pos, h, "bc" if above else "tc", ang, layer, tag=tag or ("dim " + label))


def dim_h(c, x0, x1, y, yfrom0, yfrom1, label, h, **kw):
    """Cota horizontal a cota y; las líneas de referencia salen de yfrom0/yfrom1."""
    return dim(c, (x0, yfrom0), (x1, yfrom1), (x0, y), (x1, y), label, h, **kw)


def dim_v(c, y0, y1, x, xfrom0, xfrom1, label, h, **kw):
    return dim(c, (xfrom0, y0), (xfrom1, y1), (x, y0), (x, y1), label, h, **kw)


def zigzag(c, p0, p1, amp, n=3, layer="CHM-MURO"):
    p0, p1 = np.asarray(p0, float), np.asarray(p1, float)
    v = p1 - p0
    L = float(np.hypot(*v))
    u = v / L
    nn = np.array([-u[1], u[0]])
    seg = L / (2 * n + 2)
    pts = [p0, p0 + u * seg]
    for i in range(n):
        a = seg * (2 + 2 * i)
        pts.append(p0 + u * a + nn * amp)
        pts.append(p0 + u * (a + seg) - nn * amp)
    pts += [p1 - u * seg, p1]
    c.line(pts, layer)


def arrow_head(c, tip, direction, size, layer, color=None):
    d = np.asarray(direction, float)
    d = d / np.hypot(*d)
    nn = np.array([-d[1], d[0]])
    tip = np.asarray(tip, float)
    pts = [tip, tip - d * size + nn * size * 0.3, tip - d * size - nn * size * 0.3]
    c.fill([pts], layer, color if color is not None else (30, 30, 30))


def leader(c, pt_text, pt_tip, layer="CHM-TEXTO", r=0.0):
    c.line([pt_text, pt_tip], layer)
    if r > 0:
        c.circle(pt_tip, r, layer, fillrgb=(20, 20, 20))


# ======================================================================================
# 6. VISTAS (se dibujan sobre cualquier Canvas; g = factor gráfico, h = 40*g = altura de texto en mm)
# ======================================================================================
AX_X_RGB = (200, 40, 40)
AX_Y_RGB = (40, 140, 60)
GRAY_RGB = (140, 140, 140)


def draw_plan(c, G, g):
    h = 40.0 * g
    W, D, T = G.W, G.D, T_MURO
    off1 = 3.8 * h
    XR = W + off1 + 3.4 * h
    YB = -D - off1 - 2.4 * h
    O, B, C, Dv, E, Q = G.O, G.B, G.C, G.Dv, G.E, G.Q

    # ---- muros (hachura simbólica) ----
    wall = [V2(-T, T), V2(XR, T), V2(XR, 0), V2(0, 0), V2(0, YB), V2(-T, YB)]
    c.fill([wall], "CHM-RAYADOS", WALL_RGB)
    c.pattern(wall, "CHM-RAYADOS", "ANSI31", 14, WALL_PAT_RGB)
    c.line([V2(XR, T), V2(-T, T), V2(-T, YB)], "CHM-MURO")
    c.line([V2(XR, 0), V2(0, 0), V2(0, YB)], "CHM-MURO")
    zigzag(c, V2(XR, T), V2(XR, 0), 0.3 * h)
    zigzag(c, V2(-T, YB), V2(0, YB), 0.3 * h)

    # ---- cuerpo cortado (perfil visible) ----
    c.fill([[O, B, C, Dv, E]], "CHM-RAYADOS", BODY_RGB)
    # cara real del muro izquierdo (inclinada 2,39 grados): la cuña queda absorbida por el cuerpo
    wedge = [O, V2(DESV_MM, -D), E]
    c.fill([wedge], "CHM-MURO", (232, 120, 96))
    c.line([O, V2(DESV_MM, -D)], "CHM-MURO", ls="DASHED", color=RED, lw=25)
    # esquina virtual Q y catetos CX, CY (auxiliares)
    c.line([C, Q, Dv], "CHM-EJES", ls="DASHED", lw=13, color=GRAY_RGB)
    # zócalo retranqueado y anclaje (discontinuos)
    c.line(G.zoc, "CHM-ZOCALO", closed=True, ls="DASHED")
    c.line(G.anc, "CHM-ANCLAJE", closed=True, ls="DASHED")
    # contorno visible (trazo grueso)
    c.line([O, B, C, Dv, E], "CHM-PERFIL", closed=True)
    # hueco P1-P4 (bajo el plano de corte)
    c.line([G.P1, G.P2, G.P3, G.P4], "CHM-HOGAR", closed=True, ls="DASHED")
    # marco (dos montantes de 20 x 40) y vidrio (10) como símbolos
    mf, md = G.MF, G.MD
    c.fill([[G.pl(G.u1, 0), G.pl(G.u1 + mf, 0), G.pl(G.u1 + mf, md), G.pl(G.u1, md)]], "CHM-MARCO", MARCO_RGB)
    c.fill([[G.pl(G.u2 - mf, 0), G.pl(G.u2, 0), G.pl(G.u2, md), G.pl(G.u2 - mf, md)]], "CHM-MARCO", MARCO_RGB)
    ta, tb = (md - G.VG) / 2, (md + G.VG) / 2
    gl = [G.pl(G.u1 + mf, ta), G.pl(G.u2 - mf, ta), G.pl(G.u2 - mf, tb), G.pl(G.u1 + mf, tb)]
    c.fill([gl], "CHM-VIDRIO", VIDRIO_RGB)
    c.line(gl, "CHM-VIDRIO", closed=True)
    # eje del hogar (= traza de la sección A-A) y su rótulo
    a_out = 400.0
    c.line([G.M - G.n * a_out, G.M + G.n * (G.OD + 0.6 * h)], "CHM-EJES", ls="CENTER")
    lab = "Eje del hogar"
    hl = min(h, 0.82 * (a_out - 0.9 * h) / tw(lab, 1.0))
    ang_e = math.degrees(math.atan2(G.n[1], G.n[0])) - 180      # sentido legible (hacia la derecha-abajo)
    c.text(lab, G.M - G.n * (a_out * 0.52) + G.d * (0.32 * hl), hl, "bc", ang_e, "CHM-TEXTO", color=RED, tag="eje")
    # etiqueta del hogar dentro del hueco, paralela a la cara
    c.text("Hogar 850×450", G.pl((G.u1 + G.u2) / 2 - 0.2 * G.OW, G.OD * 0.5), h, "mc", G.ang, "CHM-TEXTO",
           color=RED, tag="hogar")

    # ---- ejes X / Y del origen (planos de referencia) ----
    xa0, xa1 = -T - 0.9 * off1, XR + 2.0 * h
    c.line([V2(xa0, 0), V2(xa1, 0)], "CHM-EJES", ls="CENTER", color=AX_X_RGB)
    arrow_head(c, V2(xa1 + 1.2 * h, 0), (1, 0), 1.2 * h, "CHM-EJES", AX_X_RGB)
    c.line([V2(xa1, 0), V2(xa1 + 0.4 * h, 0)], "CHM-EJES", color=AX_X_RGB)
    c.text("X", V2(xa1 + 1.6 * h, 0), 1.1 * h, "ml", 0, "CHM-TEXTO", color=AX_X_RGB, tag="X")
    ya1 = T + off1 + 2.4 * h
    c.line([V2(0, YB - 0.8 * h), V2(0, ya1)], "CHM-EJES", ls="CENTER", color=AX_Y_RGB)
    arrow_head(c, V2(0, ya1 + 1.2 * h), (0, 1), 1.2 * h, "CHM-EJES", AX_Y_RGB)
    c.text("Y", V2(0, ya1 + 1.5 * h), 1.1 * h, "bc", 0, "CHM-TEXTO", color=AX_Y_RGB, tag="Y")
    c.circle(O, 0.32 * h, "CHM-EJES", color=(30, 30, 30), fillrgb=(255, 255, 255))
    c.text("O (0, 0)", V2(0.75 * h, -0.55 * h), h, "tl", 0, "CHM-TEXTO", tag="O")

    # ---- cotas exteriores ----
    dim_h(c, 0, W, T + off1, 0, 0, "1380", h)
    dim_v(c, 0, -D, -T - off1, 0, 0, "1420", h)
    yb = -D - off1
    dim_h(c, 0, Dv[0], yb, -D, -D, fmt(Dv[0]), h)                    # frente recto 660
    dim_h(c, Dv[0], W, yb, -D, -D, fmt(G.CX), h)                     # CX 720
    xr = W + off1
    dim_v(c, 0, C[1], xr, W, W, fmt(-C[1]), h)                       # lado recto 500
    dim_v(c, C[1], -D, xr, W, W, fmt(G.CY), h)                       # CY 920
    # desvío del muro izquierdo: 59 mm
    y59 = -D - 1.9 * h
    dim(c, V2(0, -D), V2(DESV_MM, -D), V2(0, y59), V2(DESV_MM, y59), "59 (2,39°)", h, out="b", tk=0.22 * h,
        tag="desvio")
    # retranqueo del zócalo 25 (igual en las tres caras vistas): se acota sobre el frente
    xz = 0.22 * W
    dim(c, V2(xz, -D), V2(xz, -D + G.ZR), V2(xz, -D), V2(xz, -D + G.ZR), fmt(G.ZR), h, ext=(False, False), out="b",
        tk=0.22 * h, tag="ZR")
    # ángulo del chaflán sobre la horizontal (en Dv)
    ra = 420.0
    c.arc(Dv, ra, 0.0, G.ang, "CHM-COTAS")
    for a in (0.0, G.ang):
        v = np.array([math.cos(math.radians(a)), math.sin(math.radians(a))])
        c.line([Dv + v * (ra - 0.4 * h), Dv + v * (ra + 0.5 * h)], "CHM-COTAS")
    am = math.radians(G.ang / 2)
    c.text(fmt(G.ang, 2) + "°", Dv + (ra + 0.65 * h) * np.array([math.cos(am), math.sin(am)]), h, "ml", 0,
           "CHM-COTAS", tag="angulo")

    # ---- cotas sobre el chaflán (dentro del cuerpo, medidas sobre la cara) ----
    k1 = G.OD + 1.7 * h
    k2 = k1 + 2.9 * h
    for ua, ub, lab in ((0.0, G.u1, fmt(G.mar)), (G.u1, G.u2, fmt(G.OW)), (G.u2, G.L, fmt(G.mar))):
        s0 = G.pl(ua, G.OD) if ua > 0 else None
        s1 = G.pl(ub, G.OD) if ub < G.L else None
        dim(c, G.pl(ua, 0), G.pl(ub, 0), G.pl(ua, k1), G.pl(ub, k1), lab, h, s0=s0, s1=s1,
            tag="chaflan " + lab)
    dim(c, G.Dv, G.C, G.pl(0, k2), G.pl(G.L, k2), fmt(G.L, 2), h, tag="chaflan total")


def draw_elev(c, G, g):
    h = 40.0 * g
    L, H, ZH, OZ, OH = G.L, G.H, G.ZH, G.OZ, G.OH
    zt = OZ + OH
    off1, off2 = 3.8 * h, 7.4 * h
    u1, u2, mf = G.u1, G.u2, G.MF
    # suelo
    gb = 1.1 * h
    band = [V2(-3 * h, -gb), V2(L + 3 * h, -gb), V2(L + 3 * h, 0), V2(-3 * h, 0)]
    c.pattern(band, "CHM-RAYADOS", "ANSI31", 10, WALL_PAT_RGB)
    # cuerpo
    c.fill([[V2(0, ZH), V2(L, ZH), V2(L, H), V2(0, H)]], "CHM-RAYADOS", BODY_RGB)
    # zócalo (cara retranqueada)
    zr = [V2(G.uz0, 0), V2(G.uz1, 0), V2(G.uz1, ZH), V2(G.uz0, ZH)]
    c.fill([zr], "CHM-ZOCALO", ZOC_RGB)
    c.line(zr, "CHM-ZOCALO", closed=True)
    c.line([V2(0, ZH), V2(L, ZH), V2(L, H), V2(0, H)], "CHM-PERFIL", closed=True)
    c.line([V2(-3 * h, 0), V2(L + 3 * h, 0)], "CHM-PERFIL")
    # hueco: interior oscuro, marco, vidrio
    outer = [V2(u1, OZ), V2(u2, OZ), V2(u2, zt), V2(u1, zt)]
    inner = [V2(u1 + mf, OZ + mf), V2(u2 - mf, OZ + mf), V2(u2 - mf, zt - mf), V2(u1 + mf, zt - mf)]
    c.fill([inner], "CHM-HOGAR", HOGAR_RGB)
    c.fill([outer, inner], "CHM-MARCO", MARCO_RGB)
    c.line(outer, "CHM-HOGAR", closed=True)
    c.line(inner, "CHM-VIDRIO", closed=True)
    gw, gh = u2 - u1 - 2 * mf, OH - 2 * mf
    for sx in (0.16, 0.16 + 0.07):
        xa = u1 + mf + sx * gw
        c.line([V2(xa, OZ + mf), V2(xa + 0.32 * gh, zt - mf)], "CHM-VIDRIO", lw=18)

    # ---- cotas ----
    # izquierda: 400 | 600 | 1600 y total 2600
    xl1, xl2 = -off1, -off2
    dim_v(c, 0, OZ, xl1, 0, u1, "400", h)
    dim_v(c, OZ, zt, xl1, u1, u1, "600", h)
    dim_v(c, zt, H, xl1, u1, 0, "1600", h)
    dim_v(c, 0, H, xl2, 0, 0, "2600", h)
    # derecha: zócalo 60 | cuerpo 2540
    xr = L + off1
    dim_v(c, 0, ZH, xr, L, L, "60", h, out="a", tk=0.22 * h)
    dim_v(c, ZH, H, xr, L, L, fmt(H - ZH), h)
    # inferior: 159 | 850 | 159 y 1168,25
    yb1, yb2 = -off1, -off2
    dim_h(c, 0, u1, yb1, ZH, OZ, fmt(G.mar), h)
    dim_h(c, u1, u2, yb1, OZ, OZ, fmt(G.OW), h)
    dim_h(c, u2, L, yb1, OZ, ZH, fmt(G.mar), h)
    dim_h(c, 0, L, yb2, ZH, ZH, fmt(L, 2), h)
    # marco 20 (esquina superior izquierda del hueco)
    yd = zt + 2.2 * h
    dim(c, V2(u1, zt), V2(u1 + mf, zt), V2(u1, yd), V2(u1 + mf, yd), fmt(mf), h, out="a", tk=0.2 * h, tag="MF")
    # rótulos con guía
    yl = zt + 3.7 * h
    xm = u1 + 0.30 * G.OW
    c.text("Marco 20\u00d740", V2(xm, yl), h, "bc", 0, tag="l_marco")
    leader(c, V2(xm, yl - 0.25 * h), V2(xm, zt - mf / 2))
    xv = u1 + 0.72 * G.OW
    c.text("Vidrio 10", V2(xv, yl + 2.0 * h), h, "bc", 0, tag="l_vidrio")
    leader(c, V2(xv, yl + 1.75 * h), V2(xv, zt - mf - 0.2 * gh))
    c.text("Junta de sombra", V2(L / 2, OZ - 2.2 * h), h, "bc", 0, tag="l_junta1")
    c.text("Z\u00f3calo 60, retr. 25", V2(L / 2, OZ - 3.6 * h), h, "bc", 0, tag="l_junta2")
    leader(c, V2(L / 2, OZ - 3.8 * h), V2(L / 2, ZH * 0.5))


def draw_sect(c, G, g, detail=True):
    """Sección vertical por el eje del hogar (plano perpendicular a la cara que pasa por M). Horizontal = profundidad t."""
    h = 40.0 * g
    H, ZH, ZR, OZ, OH, OD = G.H, G.ZH, G.ZR, G.OZ, G.OH, G.OD
    zt = OZ + OH
    off1, off2 = 3.8 * h, 7.4 * h
    tW = G.tW
    tR = tW + T_MURO / abs(G.n[0])                        # cara exterior del muro izquierdo en el plano de corte
    Hw = H + 3 * h
    # suelo
    gb = 1.1 * h
    x_end = tR + 3 * h
    band = [V2(-3 * h, -gb), V2(x_end, -gb), V2(x_end, 0), V2(-3 * h, 0)]
    c.pattern(band, "CHM-RAYADOS", "ANSI31", 10, WALL_PAT_RGB)
    # muro izquierdo cortado
    wall = [V2(tW, 0), V2(tR, 0), V2(tR, Hw), V2(tW, Hw)]
    c.fill([wall], "CHM-RAYADOS", WALL_RGB)
    c.pattern(wall, "CHM-RAYADOS", "ANSI31", 14, WALL_PAT_RGB)
    c.line([V2(tW, 0), V2(tW, Hw)], "CHM-MURO")
    c.line([V2(tR, 0), V2(tR, Hw)], "CHM-MURO")
    zigzag(c, V2(tW, Hw), V2(tR, Hw), 0.3 * h, layer="CHM-MURO")
    # plano de la esquina O (dashed)
    c.line([V2(G.dO, 0), V2(G.dO, H + 0.4 * h)], "CHM-EJES", ls="DASHED", lw=13, color=GRAY_RGB)
    # cuerpo (con trama de corte)
    body = [V2(0, ZH), V2(tW, ZH), V2(tW, H), V2(0, H), V2(0, zt), V2(OD, zt), V2(OD, OZ), V2(0, OZ)]
    c.fill([body], "CHM-RAYADOS", BODY_RGB)
    c.pattern(body, "CHM-RAYADOS", "ANSI37", 9, (150, 146, 138))
    # zócalo retranqueado
    zoc = [V2(ZR, 0), V2(tW, 0), V2(tW, ZH), V2(ZR, ZH)]
    c.fill([zoc], "CHM-ZOCALO", ZOC_RGB)
    c.line(zoc, "CHM-ZOCALO", closed=True)
    c.line(body, "CHM-PERFIL", closed=True)
    c.line([V2(-3 * h, 0), V2(x_end, 0)], "CHM-PERFIL")
    # interior del hogar, marco y vidrio
    cav = [V2(G.MD, OZ + G.MF), V2(OD, OZ), V2(OD, zt), V2(G.MD, zt - G.MF)]
    c.fill([[V2(0, OZ), V2(OD, OZ), V2(OD, zt), V2(0, zt)]], "CHM-HOGAR", HOGAR_RGB)
    c.line([V2(0, OZ), V2(OD, OZ), V2(OD, zt), V2(0, zt)], "CHM-HOGAR", closed=True)
    mf, md = G.MF, G.MD
    for z0 in (OZ, zt - mf):
        r = [V2(0, z0), V2(md, z0), V2(md, z0 + mf), V2(0, z0 + mf)]
        c.fill([r], "CHM-MARCO", MARCO_RGB)
        c.line(r, "CHM-MARCO", closed=True)
    ta, tb = (md - G.VG) / 2, (md + G.VG) / 2
    gl = [V2(ta, OZ + mf), V2(tb, OZ + mf), V2(tb, zt - mf), V2(ta, zt - mf)]
    c.fill([gl], "CHM-VIDRIO", VIDRIO_RGB)
    c.line(gl, "CHM-VIDRIO", closed=True)
    c.text("HOGAR", V2(OD * 0.5 + md * 0.45, (OZ + zt) / 2), h, "mc", 90, "CHM-TEXTO", color=(235, 235, 235), tag="s_hogar")
    c.text("MURO IZQ.", V2((tW + tR) / 2, H * 0.5), h, "mc", 90, "CHM-TEXTO", color=(70, 70, 70), tag="s_muro")

    # ---- cotas ----
    xl1, xl2 = -off1, -off2
    dim_v(c, 0, OZ, xl1, 0, 0, "400", h)
    dim_v(c, OZ, zt, xl1, 0, 0, "600", h)
    dim_v(c, zt, H, xl1, 0, 0, "1600", h)
    dim_v(c, 0, H, xl2, 0, 0, "2600", h)
    xr = tR + off1
    dim_v(c, 0, ZH, xr, tR, tR, "60", h, out="a", tk=0.22 * h)
    dim_v(c, ZH, H, xr, tR, tR, fmt(H - ZH), h)
    # profundidad del hogar 450 (sobre el hueco)
    yd = zt + 2.4 * h
    dim_h(c, 0, OD, yd, zt, zt, fmt(OD), h)
    # profundidades totales
    yt1, yt2 = H + off1, H + off2
    dim_h(c, 0, tW, yt1, H, H, fmt(tW, 1) + " (hasta el muro izq.)", h, tag="prof eje")
    dim_h(c, 0, G.dO, yt2, H, H, fmt(G.dO, 1) + " (hasta la esquina O)", h, tag="prof O")
    # retranqueo del zócalo (25) bajo el suelo
    yb = -off1
    dim_h(c, 0, ZR, yb, ZH, 0, fmt(ZR), h, out="a", tk=0.22 * h, tag="ZR sec")
    # marca del detalle A
    ra = 0.0
    if detail:
        cx, cz = G.MD / 2, OZ + mf / 2
        c.circle(V2(cx, cz), 0.9 * h, "CHM-COTAS", color=(11, 107, 93))
        c.text("A", V2(cx + 1.1 * h, cz - 1.9 * h), 1.1 * h, "bl", 0, "CHM-COTAS", tag="marcaA")
        draw_detail(c, G, g, tR + off1 + 7.5 * h, OZ - 3 * h)


def draw_detail(c, G, g, x0, y0, s=10.0):
    """Detalle A: marco y vidrio en el borde inferior del hueco (ampliado s veces; las cotas muestran valores reales)."""
    h = 40.0 * g
    OZ, mf, md, vg = G.OZ, G.MF, G.MD, G.VG
    zt_win = OZ + 8.0 * mf
    def m(t, z):
        return V2(x0 + s * t, y0 + s * (z - (OZ - 1.6 * mf)))
    # cuerpo bajo el hueco (trama) y borde del suelo del hogar
    body = [m(0, OZ - 1.6 * mf), m(5.5 * mf, OZ - 1.6 * mf), m(5.5 * mf, OZ), m(0, OZ)]
    c.fill([body], "CHM-RAYADOS", BODY_RGB)
    c.pattern(body, "CHM-RAYADOS", "ANSI37", 16, (150, 146, 138))
    c.line([m(0, OZ - 1.6 * mf), m(0, OZ), m(md, OZ)], "CHM-PERFIL")
    c.line([m(md, OZ), m(5.5 * mf, OZ)], "CHM-HOGAR")
    # marco (montante inferior)
    bar = [m(0, OZ), m(md, OZ), m(md, OZ + mf), m(0, OZ + mf)]
    c.fill([bar], "CHM-MARCO", MARCO_RGB)
    c.line(bar, "CHM-MARCO", closed=True)
    # vidrio
    ta, tb = (md - vg) / 2, (md + vg) / 2
    gl = [m(ta, OZ + mf), m(tb, OZ + mf), m(tb, zt_win), m(ta, zt_win)]
    c.fill([gl], "CHM-VIDRIO", VIDRIO_RGB)
    c.line(gl, "CHM-VIDRIO", closed=True)
    zigzag(c, m(ta - 3, zt_win), m(tb + 3, zt_win), 0.25 * h, n=2, layer="CHM-VIDRIO")
    # cotas del detalle (valores reales)
    yd1 = m(0, zt_win)[1] + 2.6 * h
    yd2 = yd1 + 2.6 * h
    def X(t): return m(t, 0)[0]
    ytop = m(0, zt_win)[1]
    ybar = m(0, OZ + mf)[1]
    for (ta_, tb_, lab) in ((0, ta, "15"), (ta, tb, "10"), (tb, md, "15")):
        dim(c, V2(X(ta_), ybar), V2(X(tb_), ybar), V2(X(ta_), yd1), V2(X(tb_), yd1), lab, h, tk=0.3 * h,
            s0=V2(X(ta_), ybar if ta_ not in (ta, tb) else ytop), s1=V2(X(tb_), ybar if tb_ not in (ta, tb) else ytop),
            tag="det " + lab)
    dim(c, V2(X(0), ybar), V2(X(md), ybar), V2(X(0), yd2), V2(X(md), yd2), "40", h, tk=0.3 * h, tag="det 40")
    xv = X(0) - 3.2 * h
    dim(c, V2(X(0), m(0, OZ)[1]), V2(X(0), ybar), V2(xv, m(0, OZ)[1]), V2(xv, ybar), "20", h, tk=0.3 * h, tag="det 20")
    c.text("DETALLE A — marco y vidrio", V2(x0 + s * md / 2, y0 - 3.2 * h - s * 1.6 * mf * 0.0), 1.05 * h, "bc", 0,
           "CHM-TEXTO", tag="det titulo")
    c.text("ampliado ×10 (cotas reales)", V2(x0 + s * md / 2, y0 - 4.8 * h - 0.0), 0.9 * h, "bc", 0, "CHM-TEXTO",
           tag="det esc")


# ======================================================================================
# 7. RENDER DE COMPROBACIÓN DEL DXF (ezdxf + matplotlib)
# ======================================================================================
def render_dxf_png(dxf_path, png_path, region=None, width_in=16.0, dpi=130):
    """Dibuja el modelspace del DXF con ezdxf+matplotlib. region=(x0,y0,x1,y1) para ampliar una zona."""
    from ezdxf.addons.drawing import RenderContext, Frontend
    from ezdxf.addons.drawing.matplotlib import MatplotlibBackend
    from ezdxf.addons.drawing.config import Configuration, BackgroundPolicy, ColorPolicy
    doc = ezdxf.readfile(dxf_path)
    msp = doc.modelspace()
    ext = ezbbox.extents(msp)
    if region is None:
        region = (ext.extmin.x, ext.extmin.y, ext.extmax.x, ext.extmax.y)
    x0, y0, x1, y1 = region
    mx = 0.02 * max(x1 - x0, y1 - y0)
    fig = plt.figure(figsize=(width_in, width_in * (y1 - y0 + 2 * mx) / (x1 - x0 + 2 * mx)))
    ax = fig.add_axes([0, 0, 1, 1])
    cfg = Configuration(background_policy=BackgroundPolicy.WHITE, color_policy=ColorPolicy.COLOR,
                        lineweight_scaling=1.0, min_lineweight=0.3)
    Frontend(RenderContext(doc), MatplotlibBackend(ax), config=cfg).draw_layout(msp, finalize=True)
    fig.set_size_inches(width_in, width_in * (y1 - y0 + 2 * mx) / (x1 - x0 + 2 * mx))   # finalize() lo redimensiona
    ax.set_xlim(x0 - mx, x1 + mx)
    ax.set_ylim(y0 - mx, y1 + mx)
    ax.set_aspect("equal", adjustable="box")
    fig.savefig(png_path, dpi=dpi, facecolor="white")
    plt.close(fig)


# ======================================================================================
# 8. DXF 2D: PLANTILLA DE CALCO (planta + alzado + sección en una hoja, mm, 1:1)
# ======================================================================================
G_DXF = 1.25               # factor gráfico del DXF: texto de 50 mm = 2,5 mm a escala 1:20
VIEW_GAP = 900.0           # separación entre vistas (>= 600 exigido)


def new_dxf(units_mm=True):
    doc = ezdxf.new("R2013", setup=True)
    doc.units = 4
    doc.header["$MEASUREMENT"] = 1
    doc.header["$LTSCALE"] = 25
    doc.header["$INSUNITS"] = 4
    doc.styles.get("Standard").dxf.font = "arial.ttf"
    for name, (aci, lw, _, _, rgb) in LAYERS.items():
        ly = doc.layers.add(name, color=aci, lineweight=lw)
        if rgb:
            ly.rgb = rgb
    return doc


def _obb_overlap(A, B):
    """Solape de dos rectángulos orientados (teorema del eje de separación), con 2 mm de tolerancia."""
    def axes(P):
        out = []
        for i in range(2):
            e = (P[i + 1][0] - P[i][0], P[i + 1][1] - P[i][1])
            n = math.hypot(*e)
            out.append((-e[1] / n, e[0] / n))
        return out
    for ax_ in axes(A) + axes(B):
        pa = [p[0] * ax_[0] + p[1] * ax_[1] for p in A]
        pb = [p[0] * ax_[0] + p[1] * ax_[1] for p in B]
        if max(pa) <= min(pb) + 2.0 or max(pb) <= min(pa) + 2.0:
            return False
    return True


def text_overlaps(c):
    """Pares de textos que se solapan y cruces de textos con líneas de geometría (informativo)."""
    pairs = []
    B = c.boxes
    for i in range(len(B)):
        for j in range(i + 1, len(B)):
            if _obb_overlap(B[i][0], B[j][0]):
                pairs.append((B[i][2], B[j][2]))
    return pairs


def text_line_hits(c, layers=("CHM-PERFIL", "CHM-HOGAR", "CHM-ZOCALO", "CHM-COTAS", "CHM-MARCO", "CHM-VIDRIO", "CHM-EJES")):
    """Textos cruzados por segmentos de línea (excluye la propia línea de cota sobre la que se apoya el texto)."""
    hits = []
    for cs, s, tag in c.boxes:
        # caja reducida un 8 % por cada lado para ignorar roces
        cx = sum(p[0] for p in cs) / 4
        cy = sum(p[1] for p in cs) / 4
        sh = [(cx + (p[0] - cx) * 0.9, cy + (p[1] - cy) * 0.82) for p in cs]
        for a, b, layer, ls in c.segs:
            if layer not in layers:
                continue
            # intersección segmento - rectángulo orientado
            if any(seg_intersect(a, b, sh[i], sh[(i + 1) % 4]) for i in range(4)) or point_in_polygon(a, sh) or point_in_polygon(b, sh):
                hits.append((tag, layer))
                break
    return hits


def draw_legend(c, x, y, items, h, col_w):
    """Leyenda con muestras de línea/relleno. items = [(clase, capa, ls, color, texto)]"""
    c.text("LEYENDA", V2(x, y), 1.15 * h, "bl", 0, "CHM-TEXTO", tag="LEYENDA")
    rows = (len(items) + 1) // 2
    for i, (kind, layer, ls, color, label) in enumerate(items):
        col, row = divmod(i, rows)
        xx = x + col * col_w
        yy = y - 2.4 * h - row * 2.0 * h
        if kind == "line":
            c.line([V2(xx, yy + 0.3 * h), V2(xx + 5 * h, yy + 0.3 * h)], layer, ls=ls, color=color)
        elif kind == "fill":
            c.fill([[V2(xx, yy), V2(xx + 5 * h, yy), V2(xx + 5 * h, yy + 0.7 * h), V2(xx, yy + 0.7 * h)]], layer, color)
            c.line([V2(xx, yy), V2(xx + 5 * h, yy), V2(xx + 5 * h, yy + 0.7 * h), V2(xx, yy + 0.7 * h)], "CHM-PERFIL",
                   closed=True, lw=13)
        elif kind == "hatch":
            r = [V2(xx, yy - 0.1 * h), V2(xx + 5 * h, yy - 0.1 * h), V2(xx + 5 * h, yy + 0.8 * h), V2(xx, yy + 0.8 * h)]
            c.fill([r], "CHM-RAYADOS", WALL_RGB)
            c.pattern(r, "CHM-RAYADOS", "ANSI31", 8, WALL_PAT_RGB)
        c.text(label, V2(xx + 6 * h, yy), h * 0.95, "bl", 0, "CHM-TEXTO", tag="leg " + label[:12])
    return y - 2.4 * h - rows * 2.0 * h


NOTAS_DXF = [
    "1. Cotas en mm. Origen O = esquina interior (caras interiores de ambos muros). +X a la",
    "    derecha, +Y hacia el muro de fondo; el cuerpo ocupa X \u2265 0, Y \u2264 0. Z = 0 en el suelo.",
    "2. Desv\u00edo de 2,39\u00b0 del muro izquierdo (59 mm en 1420): la cara real entra en la sala y",
    "    el cuerpo ortogonal la solapa por detr\u00e1s (cu\u00f1a roja). El anclaje oculto S = 100 cubre",
    "    adem\u00e1s el caso contrario; no queda hueco visible.",
    "3. Chafl\u00e1n por catetos CX = 720 y CY = 920: longitud 1168,25 y 51,95\u00b0. Hueco centrado.",
    "4. Secci\u00f3n A\u2013A: corta por M, perpendicular a la cara; llega al muro izquierdo a 1295,2.",
    "    La profundidad m\u00e1xima del cuerpo hasta la esquina O (perpendicular a la cara) es 1394,9.",
    "5. Planta cortada a 1200: hogar (400\u20131000), z\u00f3calo y anclaje quedan bajo el corte (discontinuos).",
]

LEYENDA_ITEMS = [
    ("line", "CHM-PERFIL", None, None, "Perfil visible del cuerpo (pentágono cortado a 1200)"),
    ("line", "CHM-ZOCALO", "DASHED", None, "Zócalo retranqueado 25, bajo el cuerpo"),
    ("line", "CHM-ANCLAJE", "DASHED", None, "Anclaje oculto S = 100, dentro de los muros"),
    ("line", "CHM-HOGAR", "DASHED", None, "Hueco del hogar P1–P4, bajo el plano de corte"),
    ("line", "CHM-EJES", "CENTER", None, "Eje del hogar (traza de la sección A–A)"),
    ("fill", "CHM-MARCO", None, MARCO_RGB, "Marco de acero negro 20 × 40"),
    ("fill", "CHM-VIDRIO", None, VIDRIO_RGB, "Vidrio 10 (centrado en la profundidad del marco)"),
    ("line", "CHM-MURO", "DASHED", RED, "Cara real del muro izquierdo (inclinada 2,39°)"),
    ("hatch", None, None, None, "Muro (hachura simbólica)"),
    ("fill", "CHM-RAYADOS", None, (232, 120, 96), "Cuña de desvío (59 mm) absorbida por el solape"),
]

VIEW_TITLES = [
    ("PLANTA", "corte horizontal a 1200 mm sobre el nivel (Ref. Level); el hogar (400–1000) queda bajo el corte"),
    ("ALZADO DE LA CARA DIAGONAL", "visto de frente, perpendicular al chaflán; u de Dv a C, z hacia arriba"),
    ("SECCIÓN A–A POR EL EJE DEL HOGAR", "perpendicular a la cara y a través de M; la sala queda a la izquierda"),
]


def build_plantilla(G, path):
    g = G_DXF
    h = 40.0 * g
    doc = new_dxf()
    c = DxfCanvas(doc)
    fns = (draw_plan, draw_elev, draw_sect)
    meas = []
    for fn in fns:
        m = MeasureCanvas()
        fn(m, G, g)
        meas.append(m.bb)
    info = dict(views=[], overlaps=[], hits=[])
    x_cur = 0.0
    for i, (fn, bb) in enumerate(zip(fns, meas)):
        c.ox, c.oy = x_cur - bb.x0, -bb.y0
        c.bb, c.boxes, c.segs = BBox(), [], []
        fn(c, G, g)
        vb = BBox()
        vb.x0, vb.y0, vb.x1, vb.y1 = c.bb.x0, c.bb.y0, c.bb.x1, c.bb.y1
        # título de la vista (debajo)
        ttl, sub = VIEW_TITLES[i]
        xc = (vb.x0 + vb.x1) / 2
        c.ox = c.oy = 0.0
        c.text(ttl, V2(vb.x0, vb.y0 - 5.0 * h), 1.9 * h, "bl", 0, "CHM-TEXTO", tag="titulo")
        c.text(sub, V2(vb.x0, vb.y0 - 7.4 * h), 0.85 * h, "bl", 0, "CHM-TEXTO", tag="subtitulo")
        wsub = tw(sub, 0.85 * h)
        vb.add(vb.x0 + wsub, vb.y0 - 7.4 * h)
        info["views"].append(dict(name=ttl, bbox=(vb.x0, vb.y0, vb.x1, vb.y1)))
        info["overlaps"] += [(ttl,) + p for p in text_overlaps(c)]
        info["hits"] += [(ttl,) + p for p in text_line_hits(c)]
        x_cur = max(vb.x1, x_cur - bb.x0 + bb.x1) + VIEW_GAP
    x_min = info["views"][0]["bbox"][0]
    x_max = info["views"][-1]["bbox"][2]
    y_min = min(v["bbox"][1] for v in info["views"])
    # ---- leyenda y notas ----
    c.ox = c.oy = 0.0
    c.bb, c.boxes, c.segs = BBox(), [], []
    ys = y_min - 5.0 * h
    ystart = ys - 4.0 * h
    ylg = draw_legend(c, x_min, ystart, LEYENDA_ITEMS, h, col_w=3150.0)
    xn = x_min + 6500.0
    c.text("NOTAS", V2(xn, ystart), 1.15 * h, "bl", 0, "CHM-TEXTO", tag="NOTAS")
    yy = ystart - 2.4 * h
    for ln in NOTAS_DXF:
        c.text(ln, V2(xn, yy), 0.95 * h, "bl", 0, "CHM-TEXTO", tag="nota")
        yy -= 1.8 * h
    info["overlaps"] += [("leyenda/notas",) + p for p in text_overlaps(c)]
    ytb = min(ylg, yy) - 3.0 * h
    # ---- cajetín ----
    Hc = 9.0 * h
    xr = x_max
    xs = xr - 3900.0
    c.line([V2(x_min, ytb - Hc), V2(xr, ytb - Hc), V2(xr, ytb), V2(x_min, ytb)], "CHM-CAJETIN", closed=True)
    c.line([V2(xs, ytb - Hc), V2(xs, ytb)], "CHM-CAJETIN")
    ht = min(2.2 * h, 0.94 * (xs - x_min - 2 * h) / tw(TITULO, 1.0))
    c.text(TITULO, V2(x_min + h, ytb - 3.0 * h), ht, "bl", 0, "CHM-TEXTO", tag="cajetin titulo")
    c.text("Planta, alzado de la cara diagonal y sección por el eje del hogar — familia: Equipamiento especializado"
           " (plantilla Modelo genérico métrico)", V2(x_min + h, ytb - 5.2 * h), 0.95 * h, "bl", 0, "CHM-TEXTO", tag="cajetin sub")
    c.text(AVISO, V2(x_min + h, ytb - 7.4 * h), 1.0 * h, "bl", 0, "CHM-TEXTO", color=RED, tag="cajetin aviso")
    c.text("ESCALA 1:20", V2(xs + h, ytb - 3.0 * h), 2.0 * h, "bl", 0, "CHM-TEXTO", tag="cajetin escala")
    c.text("Unidades: mm — dibujo a escala real 1:1", V2(xs + h, ytb - 5.2 * h), 0.95 * h, "bl", 0, "CHM-TEXTO", tag="cajetin uni")
    c.text("No se ha probado en Revit", V2(xs + h, ytb - 7.4 * h), 0.95 * h, "bl", 0, "CHM-TEXTO", tag="cajetin rev")
    info["overlaps"] += [("cajetin",) + p for p in text_overlaps(c)]
    info["bbox"] = (x_min, ytb - Hc, xr, max(v["bbox"][3] for v in info["views"]))
    doc.saveas(path)
    return info


# ======================================================================================
# 9. DXF 3D DE REFERENCIA (entidades MESH, una capa por componente)
# ======================================================================================
LAYERS_3D = {   # clave: (capa, ACI, RGB, descripción)
    "zocalo":  ("CHM3D-ZOCALO", 8, (96, 96, 100)),
    "cuerpo":  ("CHM3D-CUERPO", 9, (214, 210, 202)),
    "marco":   ("CHM3D-MARCO", 250, (45, 45, 48)),
    "vidrio":  ("CHM3D-VIDRIO", 4, (132, 200, 226)),
    "anclaje": ("CHM3D-ANCLAJE", 30, (190, 140, 90)),
}


def build_3d(meshes, path):
    doc = ezdxf.new("R2013", setup=True)
    doc.units = 4
    doc.header["$MEASUREMENT"] = 1
    doc.header["$INSUNITS"] = 4
    msp = doc.modelspace()
    for key, (lname, aci, rgb) in LAYERS_3D.items():
        ly = doc.layers.add(lname, color=aci)
        ly.rgb = rgb
        if key == "vidrio":
            try:
                ly.transparency = 0.45
            except Exception:
                pass
    for key, m in meshes.items():
        lname = LAYERS_3D[key][0]
        e = msp.add_mesh(dxfattribs={"layer": lname})
        e.dxf.subdivision_levels = 0
        with e.edit_data() as md:
            md.vertices = [tuple(v) for v in m.verts]
            md.faces = m.tris()
    ezzoom.extents(msp, factor=1.1)
    doc.saveas(path)
