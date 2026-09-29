#!/usr/bin/env python3
"""Escribe la propuesta de la planta segunda en DXF (en cm y en m)."""
import math
import os
import sys

import ezdxf
from ezdxf import units

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import planta2 as P

DET = {"color": 8, "lineweight": 13}


def emit(space, it, lines, S, dx=0.0, dy=0.0):
    a = {"layer": "0"}
    if it.style == "det":
        a.update(DET)

    def pt(p):
        return ((p[0] + dx) * S, (p[1] + dy) * S)
    if it.kind == "dash":
        runs = lines if lines is not None else [it.path()]
        for run in runs:
            for p0, p1 in P.dashes(run):
                space.add_line(pt(p0), pt(p1), dxfattribs=a)
        return
    if lines is not None:
        for run in lines:
            space.add_lwpolyline([pt(p) for p in run], format="xy", close=False, dxfattribs=a)
        return
    if it.kind == "pl":
        space.add_lwpolyline([pt(p) + (0.0, 0.0, p[2] if len(p) > 2 else 0.0) for p in it.geom],
                             format="xyseb", close=it.closed, dxfattribs=a)
    elif it.kind == "circle":
        space.add_circle(pt(it.geom[:2]), it.geom[2] * S, dxfattribs=a)
    elif it.kind == "line":
        space.add_line(pt(it.geom[0]), pt(it.geom[1]), dxfattribs=a)
    else:
        raise ValueError(it.kind)


def write(path, S):
    """S = unidades de dibujo por cm (1 = cm, 0.01 = m)."""
    doc = ezdxf.new("R2013", setup=True)
    doc.units = units.CM if S == 1 else units.M
    doc.header["$INSUNITS"] = 5 if S == 1 else 6
    doc.header["$MEASUREMENT"] = 1
    doc.header["$LWDISPLAY"] = 1
    doc.set_wipeout_variables(frame=0)
    doc.styles.add("PS", font="arial.ttf")
    for name, col in P.CAPAS.items():
        doc.layers.add(name, color=col)
    doc.layers.get("PS-REF-PLANO").freeze()
    ds = doc.dimstyles.new("PS")
    for k, v in dict(dimtxt=7.0, dimasz=2.5, dimexe=2.5, dimexo=2.0, dimgap=1.5, dimdli=8.0,
                     dimcen=0.0).items():
        ds.set_dxf_attrib(k, v * S)
    for k, v in dict(dimdec=0 if S == 1 else 2, dimtad=1, dimtih=0, dimtoh=0, dimclrd=1, dimclre=1,
                     dimclrt=1, dimzin=8 if S == 1 else 0, dimdsep=ord(","), dimtfill=1).items():
        ds.set_dxf_attrib(k, v)
    ds.set_dxf_attrib("dimtxsty", "PS")
    ds.set_arrows(blk=ezdxf.ARROWS.architectural_tick)

    B = P.bloques()
    for name, b in B.items():
        blk = doc.blocks.new(name=name, base_point=(0, 0, 0))
        if b["wipeout"]:
            blk.add_wipeout([(x * S, y * S) for x, y in b["wipeout"]], dxfattribs={"layer": "0"})
        for it, lines in P.procesar(sorted(b["items"], key=lambda i: i.z)):
            emit(blk, it, lines, S)

    msp = doc.modelspace()
    bx, by = P.REF_BASE
    # plano de referencia del usuario (capa congelada): solo para comprobar el encaje
    for poly in P.ref_plano():
        msp.add_lwpolyline([((x - bx) * S, (y - by) * S) for x, y in poly], close=True,
                           dxfattribs={"layer": "PS-REF-PLANO"})
    for l in P.ref_escalera():
        msp.add_lwpolyline([((x - bx) * S, (y - by) * S) for x, y in l], dxfattribs={"layer": "PS-REF-PLANO"})
    msp.add_lwpolyline([((x - bx) * S, (y - by) * S) for x, y in P.ref_pilar()], close=True,
                       dxfattribs={"layer": "PS-REF-PLANO"})
    # piezas
    for name, x, y, rot, layer in P.INSERCIONES:
        msp.add_blockref(name, ((x - bx) * S, (y - by) * S), dxfattribs={"layer": layer, "rotation": rot})
    for x, y, h, txt, layer in P.TEXTOS:
        msp.add_mtext(txt, dxfattribs={"insert": ((x - bx) * S, (y - by) * S), "char_height": h * S,
                                      "attachment_point": 5, "layer": layer, "style": "PS"}) \
            .set_bg_color("canvas", scale=1.25)          # mascara de fondo: se lee sobre la alfombra
    for p0, p1, layer in P.LIDERES:                   # directriz con punto en la barandilla
        msp.add_leader([((p1[0] - bx) * S, (p1[1] - by) * S), ((p0[0] - bx) * S, (p0[1] - by) * S)],
                       dimstyle="PS", override={"dimldrblk": ezdxf.ARROWS.dot_small, "dimasz": 4.0 * S,
                                                "dimclrd": 256},
                       dxfattribs={"layer": layer, "has_arrowhead": 1})
    for p1, p2, base, ang, txt in P.COTAS:
        d = msp.add_linear_dim(base=((base[0] - bx) * S, (base[1] - by) * S),
                               p1=((p1[0] - bx) * S, (p1[1] - by) * S), p2=((p2[0] - bx) * S, (p2[1] - by) * S),
                               angle=ang, text=txt, dimstyle="PS", dxfattribs={"layer": "PS-COTAS"})
        d.render()
    auditor = doc.audit()
    doc.saveas(path)
    return doc, auditor


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else P.SALIDA
    for S, suf in ((1.0, "cm"), (0.01, "m")):
        path = os.path.join(out, "Planta2_sala_estar_zona_juego_%s.dxf" % suf)
        doc, aud = write(path, S)
        d2 = ezdxf.readfile(path)
        print("%s  %d bytes  audit errors %d fixes %d  msp %d  bloques %d" % (
            os.path.basename(path), os.path.getsize(path), len(aud.errors), len(aud.fixes),
            len(d2.modelspace()), len([b for b in d2.blocks if b.name.startswith("PS_")])))
