"""Character specifications + per-character assembly (clothes, hair, materials)."""
import os
import numpy as np
import mh_lib as mh
import bl_common as bc
import bpy

def A(*p):
    return os.path.join(mh.ASSETS, *p)

SPECS = {
 "elias": dict(name="elias", file="elias.glb", gender=1.0, age=38, muscle=0.55, weight=0.42, height_m=1.82,
               details=[]),
}

def assemble(cb, spec):
    n = spec["name"]
    # skin
    skin_dir = A("skins", "middleage_caucasian_male")
    skin = cb.mat_from_mhmat(n + "_skin", os.path.join(skin_dir, "middleage_caucasian_male.mhmat"),
                             color=(1.0, 0.95, 0.9, 1), rough=0.6, max_size=2048, use_normal=False)
    suit = cb.build_proxy("suit", A("clothes/male_casualsuit03/male_casualsuit03.mhclo"),
                          cb.mat_from_mhmat(n + "_suit", A("clothes/male_casualsuit03/male_casualsuit03.mhmat")))
    shoes = cb.build_proxy("shoes", A("clothes/shoes03/shoes03.mhclo"),
                           cb.mat_from_mhmat(n + "_shoes", A("clothes/shoes03/shoes03.mhmat")))
    dv = set(suit[1].delete_verts) | set(shoes[1].delete_verts)
    body = cb.build_body(sorted(dv))
    body.data.materials.append(skin)
    eyes = cb.build_proxy("eyes", A("eyes/high-poly/high-poly.mhclo"),
                          cb.mat_from_mhmat(n + "_eyes", A("eyes/high-poly/high-poly.mhmat")) if False else
                          bc.make_material(n + "_eyes", base=bc.tex_image(os.path.join(mh.MH_DATA, "eyes/materials/brown_eye.png")), rough=0.15),
                          bone="head")
    hair = cb.build_proxy("hair", A("hair/short02/short02.mhclo"),
                          cb.mat_from_mhmat(n + "_hair", A("hair/short02/short02.mhmat"), alpha=True, color=(0.35,0.3,0.28,1)))
