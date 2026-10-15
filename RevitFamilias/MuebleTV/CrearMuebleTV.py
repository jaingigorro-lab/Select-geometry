# -*- coding: utf-8 -*-
"""Crea una familia parametrica de mueble para television (Revit).

Ejecutar con pyRevit o RevitPythonShell con un documento de familia abierto,
creado a partir de la plantilla "Mobiliario metrico.rft" / "Metric Furniture.rft"
(o "Modelo generico metrico.rft"; el script cambia la categoria a Mobiliario).

Geometria (vista frontal):

    +-------------------------------------------------------+  <- Tapa
    |            |  |                  |  |                 |
    |  Puerta    |  |   Nicho abierto  |  |   Puerta        |
    |  izquierda |  |------------------|  |   derecha       |  <- Estantes
    |            |  |                  |  |                 |
    +--+------------------------------------------------+---+  <- Fondo
       |                    Zocalo                      |
    ---+------------------------------------------------+---

Origen de la familia: centro de la cara trasera, a nivel de suelo (se coloca
contra un muro sin desplazamientos). El frente del mueble mira hacia -Y.
"""
from __future__ import print_function

import clr
clr.AddReference('RevitAPI')
from Autodesk.Revit.DB import (
    BuiltInCategory, BuiltInParameter, Category, Color, CurveArray,
    CurveArrArray, FilteredElementCollector, Line, Material, Options, Plane,
    ReferenceArray, ReferencePlane, SketchPlane, Transaction, UV, ViewPlan,
    ViewSection, ViewType, XYZ,
)

try:
    from Autodesk.Revit.DB import GroupTypeId, SpecTypeId  # Revit 2022+
    API_FORGE = True
except ImportError:
    from Autodesk.Revit.DB import BuiltInParameterGroup, ParameterType
    API_FORGE = False

doc = __revit__.ActiveUIDocument.Document  # noqa: F821 (lo inyecta pyRevit/RPS)
fc = doc.FamilyCreate
fm = doc.FamilyManager

MM = 1.0 / 304.8  # mm -> pies (unidades internas de Revit)

# ---------------------------------------------------------------------------
# Parametros de la familia: (nombre, tipo, valor por defecto)
# Longitudes en mm. Todos son parametros de tipo.
# ---------------------------------------------------------------------------
PARAMETROS = [
    ('Ancho', 'len', 1800),
    ('Alto', 'len', 500),
    ('Profundidad', 'len', 450),
    ('Espesor', 'len', 18),             # tableros y puertas
    ('Espesor_Trasera', 'len', 6),
    ('Altura_Zocalo', 'len', 80),
    ('Retranqueo_Zocalo', 'len', 40),
    ('Ancho_Nicho', 'len', 700),        # hueco central abierto (interior)
    ('Altura_Estante', 'len', 180),     # desde la cara superior del fondo
    ('Mostrar_Puertas', 'bool', 1),
    ('Mostrar_Estantes_Laterales', 'bool', 1),
    ('Material_Cuerpo', 'mat', None),
    ('Material_Puertas', 'mat', None),
]

MATERIALES = {
    'Material_Cuerpo': ('MuebleTV - Roble', (196, 160, 112)),
    'Material_Puertas': ('MuebleTV - Lacado blanco', (240, 240, 236)),
}

TIPO_PRINCIPAL = 'MuebleTV 1800'
TIPOS_EXTRA = [
    ('MuebleTV 1400', {'Ancho': 1400, 'Ancho_Nicho': 560}),
    ('MuebleTV 2200', {'Ancho': 2200, 'Ancho_Nicho': 900}),
    ('MuebleTV 2400 alto', {'Ancho': 2400, 'Ancho_Nicho': 1000, 'Alto': 600,
                            'Altura_Estante': 220}),
]

VAL = dict((n, v) for n, k, v in PARAMETROS if k == 'len')


# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------
def buscar_vistas():
    plan = None
    for v in FilteredElementCollector(doc).OfClass(ViewPlan):
        if not v.IsTemplate and v.ViewType == ViewType.FloorPlan:
            plan = v
            break
    frontal = None
    for v in FilteredElementCollector(doc).OfClass(ViewSection):
        if v.IsTemplate or v.ViewType != ViewType.Elevation:
            continue
        d = v.ViewDirection
        if abs(d.Y) > 0.99:
            # El alzado frontal mira hacia +Y (su ViewDirection apunta a -Y).
            if frontal is None or d.Y < 0:
                frontal = v
    if plan is None or frontal is None:
        raise Exception('No se encontro la vista de planta o el alzado frontal '
                        'en la plantilla de familia.')
    return plan, frontal


def parametro(nombre):
    for p in fm.Parameters:
        if p.Definition.Name == nombre:
            return p
    return None


def crear_parametro(nombre, clase):
    if API_FORGE:
        grupo = {'len': GroupTypeId.Geometry, 'bool': GroupTypeId.Visibility,
                 'mat': GroupTypeId.Materials}[clase]
        spec = {'len': SpecTypeId.Length, 'bool': SpecTypeId.Boolean.YesNo,
                'mat': SpecTypeId.Reference.Material}[clase]
    else:
        grupo = {'len': BuiltInParameterGroup.PG_GEOMETRY,
                 'bool': BuiltInParameterGroup.PG_VISIBILITY,
                 'mat': BuiltInParameterGroup.PG_MATERIALS}[clase]
        spec = {'len': ParameterType.Length, 'bool': ParameterType.YesNo,
                'mat': ParameterType.Material}[clase]
    return fm.AddParameter(nombre, grupo, spec, False)


def material(nombre, rgb):
    for m in FilteredElementCollector(doc).OfClass(Material):
        if m.Name == nombre:
            return m.Id
    mid = Material.Create(doc, nombre)
    doc.GetElement(mid).Color = Color(rgb[0], rgb[1], rgb[2])
    return mid


class Plano(object):
    """Plano de referencia con su eje ('x', 'y', 'z') y posicion en mm."""

    def __init__(self, nombre, eje, pos):
        self.nombre, self.eje, self.pos = nombre, eje, pos
        p = pos * MM
        e = 2000 * MM
        if eje == 'x':
            self.rp = fc.NewReferencePlane(XYZ(p, -e, 0), XYZ(p, e, 0),
                                           XYZ.BasisZ, V_PLAN)
        elif eje == 'y':
            self.rp = fc.NewReferencePlane(XYZ(-e, p, 0), XYZ(e, p, 0),
                                           XYZ.BasisZ, V_PLAN)
        else:
            self.rp = fc.NewReferencePlane(XYZ(-e, 0, p), XYZ(e, 0, p),
                                           XYZ.BasisY, V_FRONTAL)
        self.rp.Name = nombre

    def ref(self):
        return self.rp.GetReference()


_n_cotas = {'x': 0, 'y': 0, 'z': 0}


def acotar(planos, nombre_param=None, iguales=False):
    eje = planos[0].eje
    n = _n_cotas[eje]
    _n_cotas[eje] += 1
    a = min(p.pos for p in planos) * MM
    b = max(p.pos for p in planos) * MM
    off = (250 + 120 * n) * MM
    lado = (VAL['Ancho'] / 2.0) * MM + off
    if eje == 'x':
        linea, vista = Line.CreateBound(XYZ(a, off, 0), XYZ(b, off, 0)), V_PLAN
    elif eje == 'y':
        linea, vista = Line.CreateBound(XYZ(lado, a, 0), XYZ(lado, b, 0)), V_PLAN
    else:
        linea, vista = Line.CreateBound(XYZ(-lado, 0, a), XYZ(-lado, 0, b)), V_FRONTAL
    ra = ReferenceArray()
    for p in planos:
        ra.Append(p.ref())
    cota = fc.NewDimension(vista, linea, ra)
    if nombre_param:
        cota.FamilyLabel = parametro(nombre_param)
    if iguales:
        cota.AreSegmentsEqual = True
    return cota


def raiz(nombre, eje):
    p = Plano(nombre, eje, 0.0)
    p.rp.Pinned = True
    return p


def hijo(nombre, padre, signo, nombre_param):
    """Plano desplazado del padre una distancia = parametro (cota etiquetada)."""
    p = Plano(nombre, padre.eje, padre.pos + signo * VAL[nombre_param])
    acotar([padre, p], nombre_param)
    return p


def caja(xs, ys, zs, param_mat, param_vis=None):
    """Extrusion rectangular con sus 6 caras bloqueadas a planos de referencia.

    xs, ys, zs: pares (plano_min, plano_max).
    """
    x0, x1 = xs[0].pos * MM, xs[1].pos * MM
    y0, y1 = ys[0].pos * MM, ys[1].pos * MM
    z0, z1 = zs[0].pos * MM, zs[1].pos * MM

    pts = [XYZ(x0, y0, z0), XYZ(x1, y0, z0), XYZ(x1, y1, z0), XYZ(x0, y1, z0)]
    lazo = CurveArray()
    for i in range(4):
        lazo.Append(Line.CreateBound(pts[i], pts[(i + 1) % 4]))
    perfil = CurveArrArray()
    perfil.Append(lazo)
    sp = SketchPlane.Create(doc, Plane.CreateByNormalAndOrigin(XYZ.BasisZ,
                                                               XYZ(0, 0, z0)))
    ext = fc.NewExtrusion(True, perfil, sp, z1 - z0)
    doc.Regenerate()

    opts = Options()
    opts.ComputeReferences = True
    for obj in ext.get_Geometry(opts):
        caras = getattr(obj, 'Faces', None)
        if caras is None or caras.Size == 0:
            continue
        for cara in caras:
            n = cara.ComputeNormal(UV(0.5, 0.5))
            if abs(n.X) > 0.99:
                plano, vista = xs[1 if n.X > 0 else 0], V_PLAN
            elif abs(n.Y) > 0.99:
                plano, vista = ys[1 if n.Y > 0 else 0], V_PLAN
            elif abs(n.Z) > 0.99:
                plano, vista = zs[1 if n.Z > 0 else 0], V_FRONTAL
            else:
                continue
            al = fc.NewAlignment(vista, plano.ref(), cara.Reference)
            al.IsLocked = True

    fm.AssociateElementParameterToFamilyParameter(
        ext.get_Parameter(BuiltInParameter.MATERIAL_ID_PARAM),
        parametro(param_mat))
    if param_vis:
        fm.AssociateElementParameterToFamilyParameter(
            ext.get_Parameter(BuiltInParameter.IS_VISIBLE_PARAM),
            parametro(param_vis))
    return ext


# ---------------------------------------------------------------------------
# Construccion
# ---------------------------------------------------------------------------
def construir():
    # Categoria Mobiliario (por si se parte de Modelo generico).
    try:
        cat = Category.GetCategory(doc, BuiltInCategory.OST_Furniture)
        if doc.OwnerFamily.FamilyCategory.Id != cat.Id:
            doc.OwnerFamily.FamilyCategory = cat
    except Exception as ex:
        print('Aviso: no se pudo asignar la categoria Mobiliario: {}'.format(ex))

    # Tipo principal y parametros.
    if fm.CurrentType is None:
        fm.NewType(TIPO_PRINCIPAL)
    else:
        fm.RenameCurrentType(TIPO_PRINCIPAL)
    tipo_principal = fm.CurrentType

    for nombre, clase, defecto in PARAMETROS:
        p = crear_parametro(nombre, clase)
        if clase == 'len':
            fm.Set(p, defecto * MM)
        elif clase == 'bool':
            fm.Set(p, int(defecto))
        else:
            nm, rgb = MATERIALES[nombre]
            fm.Set(p, material(nm, rgb))

    # --- Planos de referencia (arbol: cada plano cuelga de un unico padre) ---
    C = raiz('MTV Centro', 'x')
    B = raiz('MTV Trasera', 'y')
    Z0 = raiz('MTV Suelo', 'z')

    L = Plano('MTV Izquierda', 'x', -VAL['Ancho'] / 2.0)
    R = Plano('MTV Derecha', 'x', VAL['Ancho'] / 2.0)
    acotar([L, R], 'Ancho')
    acotar([L, C, R], iguales=True)
    Li = hijo('MTV Lateral izq. interior', L, +1, 'Espesor')
    Ri = hijo('MTV Lateral der. interior', R, -1, 'Espesor')

    NLi = Plano('MTV Nicho izq.', 'x', -VAL['Ancho_Nicho'] / 2.0)
    NRi = Plano('MTV Nicho der.', 'x', VAL['Ancho_Nicho'] / 2.0)
    acotar([NLi, NRi], 'Ancho_Nicho')
    acotar([NLi, C, NRi], iguales=True)
    DLo = hijo('MTV Divisor izq.', NLi, -1, 'Espesor')
    DRo = hijo('MTV Divisor der.', NRi, +1, 'Espesor')

    F = hijo('MTV Frente', B, -1, 'Profundidad')
    Bi = hijo('MTV Trasera interior', B, -1, 'Espesor_Trasera')
    Fp = hijo('MTV Puertas interior', F, +1, 'Espesor')
    Fz = hijo('MTV Zocalo frente', F, +1, 'Retranqueo_Zocalo')

    Zt = hijo('MTV Superior', Z0, +1, 'Alto')
    Ztb = hijo('MTV Tapa inferior', Zt, -1, 'Espesor')
    Zz = hijo('MTV Zocalo superior', Z0, +1, 'Altura_Zocalo')
    Zb = hijo('MTV Fondo superior', Zz, +1, 'Espesor')
    Zs = hijo('MTV Estante inferior', Zb, +1, 'Altura_Estante')
    Zs2 = hijo('MTV Estante superior', Zs, +1, 'Espesor')
    doc.Regenerate()

    # --- Piezas ---
    cuerpo, puertas = 'Material_Cuerpo', 'Material_Puertas'
    caja((L, Li), (F, B), (Z0, Zt), cuerpo)            # lateral izquierdo
    caja((Ri, R), (F, B), (Z0, Zt), cuerpo)            # lateral derecho
    caja((Li, Ri), (F, B), (Ztb, Zt), cuerpo)          # tapa
    caja((Li, Ri), (F, Bi), (Zz, Zb), cuerpo)          # fondo (base)
    caja((Li, Ri), (Bi, B), (Zz, Ztb), cuerpo)         # trasera
    caja((Li, Ri), (Fz, B), (Z0, Zz), cuerpo)          # zocalo retranqueado
    caja((DLo, NLi), (F, Bi), (Zb, Ztb), cuerpo)       # divisor izquierdo
    caja((NRi, DRo), (F, Bi), (Zb, Ztb), cuerpo)       # divisor derecho
    caja((NLi, NRi), (F, Bi), (Zs, Zs2), cuerpo)       # estante del nicho
    caja((Li, DLo), (Fp, Bi), (Zs, Zs2), cuerpo, 'Mostrar_Estantes_Laterales')
    caja((DRo, Ri), (Fp, Bi), (Zs, Zs2), cuerpo, 'Mostrar_Estantes_Laterales')
    caja((Li, DLo), (F, Fp), (Zb, Ztb), puertas, 'Mostrar_Puertas')
    caja((DRo, Ri), (F, Fp), (Zb, Ztb), puertas, 'Mostrar_Puertas')
    doc.Regenerate()

    # --- Tipos adicionales (sirven tambien de prueba de flexion) ---
    for nombre, valores in TIPOS_EXTRA:
        fm.CurrentType = tipo_principal
        fm.NewType(nombre)
        for k, v in valores.items():
            fm.Set(parametro(k), v * MM)
        doc.Regenerate()
    fm.CurrentType = tipo_principal
    doc.Regenerate()


def main():
    if not doc.IsFamilyDocument:
        print('Abre primero un documento de familia (Archivo > Nuevo > Familia, '
              'plantilla "Mobiliario metrico.rft").')
        return
    existentes = set(rp.Name for rp in
                     FilteredElementCollector(doc).OfClass(ReferencePlane))
    if any(n.startswith('MTV ') for n in existentes) or parametro('Ancho_Nicho'):
        print('Esta familia ya contiene el mueble TV. Usa una familia nueva.')
        return

    global V_PLAN, V_FRONTAL
    V_PLAN, V_FRONTAL = buscar_vistas()

    t = Transaction(doc, 'Crear mueble TV')
    t.Start()
    try:
        construir()
        t.Commit()
    except Exception:
        t.RollBack()
        raise
    print('Mueble TV creado. Tipos: {}, {}.'.format(
        TIPO_PRINCIPAL, ', '.join(n for n, _ in TIPOS_EXTRA)))
    print('Guarda la familia como MuebleTV.rfa y cargala en el proyecto.')


main()
