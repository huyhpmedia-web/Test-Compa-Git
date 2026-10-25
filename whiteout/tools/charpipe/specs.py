"""Character specifications + per-character assembly (clothes, hair, materials)."""
import os, math
import numpy as np
import mh_lib as mh
import bl_common as bc
import paint as pt
import bpy

def A(*p):
    return os.path.join(mh.ASSETS, *p)

TEX = os.path.join(mh.CACHE, "work", "tex")

SPECS = {
 "elias": dict(name="elias", file="elias.glb", gender=1.0, age=38, muscle=0.55, weight=0.40,
               height_slider=0.5, height_m=1.82, skin="middleage_caucasian_male",
               details=[("head", "head-age", 0.55, "decr", "incr"), ("head", "head-rectangular", 0.45),
                        ("chin", "chin-prominent", 0.35, "decr", "incr"), ("chin", "chin-width", 0.25, "decr", "incr"),
                        ("cheek", "l-cheek-bones", 0.3, "decr", "incr"), ("cheek", "r-cheek-bones", 0.3, "decr", "incr"),
                        ("cheek", "l-cheek-volume", -0.35, "decr", "incr"), ("cheek", "r-cheek-volume", -0.35, "decr", "incr"),
                        ("eyes", "l-eye-bag", 0.6, "decr", "incr"), ("eyes", "r-eye-bag", 0.6, "decr", "incr"),
                        ("eyes", "l-eye-height1", -0.25, "decr", "incr"), ("eyes", "r-eye-height1", -0.25, "decr", "incr"),
                        ("eyebrows", "eyebrows-trans", -0.4, "down", "up"),
                        ("nose", "nose-hump", 0.35, "decr", "incr"), ("nose", "nose-width1", 0.1, "decr", "incr"),
                        ("mouth", "mouth-angles", -0.35, "down", "up"), ("mouth", "mouth-laugh-lines", 0.5, "in", "out"),
                        ("mouth", "mouth-lowerlip-volume", -0.3, "decr", "incr"),
                        ("neck", "neck-scale-horiz", 0.3, "decr", "incr"),
                        ("forehead", "forehead-temple", 0.3, "decr", "incr"),
                        ("torso", "torso-vshape", 0.4, "decr", "incr")]),
}

SPECS.update({
 "june": dict(name="june", file="june.glb", builder="build_june", gender=0.0, age=15, muscle=0.35, weight=0.42, height_m=1.60,
              skin="young_caucasian_female", stubble=0.0, weather=0.4,
              details=[("head", "head-age", -0.3, "decr", "incr"), ("eyes", "l-eye-scale", 0.3, "decr", "incr"), ("eyes", "r-eye-scale", 0.3, "decr", "incr"),
                       ("nose", "nose-scale-vert", -0.2, "decr", "incr"), ("mouth", "mouth-lowerlip-volume", 0.2, "decr", "incr")]),
 "ruth": dict(name="ruth", file="ruth.glb", builder="build_ruth", gender=0.0, age=68, muscle=0.3, weight=0.58, height_m=1.62,
              skin="old_caucasian_female", stubble=0.0, weather=0.6,
              details=[("head", "head-age", 0.5, "decr", "incr"), ("eyes", "l-eye-bag", 0.4, "decr", "incr"), ("eyes", "r-eye-bag", 0.4, "decr", "incr"),
                       ("mouth", "mouth-angles", -0.3, "down", "up"), ("neck", "neck-double", 0.3, "decr", "incr")]),
})

def _z(name, outfit, gender, age, color, color2=None, seed=1, skin=None, hair=None, hair_tint=(0.3, 0.3, 0.32), height=1.76, weight=0.5, muscle=0.45,
       pallor=(0.70, 0.80, 0.90), gore_cloth=None, gore_skin=None, **kw):
    d = dict(name=name, file=name + ".glb", builder="zombies.build_zombie", outfit=outfit, gender=gender, age=age, muscle=muscle, weight=weight,
             height_m=height, skin=skin or ("middleage_caucasian_male" if gender > 0.5 else "middleage_caucasian_female"), color=color,
             color2=color2 or (0.12, 0.15, 0.22), seed=seed, hair=hair, hair_tint=hair_tint, pallor=pallor, details=[("head", "head-age", 0.3, "decr", "incr")])
    if gore_cloth: d["gore_cloth"] = gore_cloth
    if gore_skin: d["gore_skin"] = gore_skin
    d.update(kw)
    SPECS[name] = d

_z("rimebound_parka_m", "parka", 1.0, 44, (0.10, 0.2, 0.17), (0.12, 0.12, 0.14), 11, hair="hair/short03", hair_tint=(0.4, 0.4, 0.42), height=1.80, weight=0.55,
   gore_cloth=dict(mouth=0.9, soak=0.7, wounds=2, torn=1, splat=0.4, frost=0.5), gore_skin=dict(mouth=0.9, wounds=2, splat=0.3, frost=0.4))
_z("rimebound_jacket_m", "jacket", 1.0, 56, (0.25, 0.23, 0.14), (0.2, 0.2, 0.22), 12, hair=None, height=1.74, weight=0.6, pants=(0.18, 0.18, 0.2),
   gore_cloth=dict(mouth=0.6, soak=0.4, wounds=3, torn=2, splat=0.3, frost=0.4), gore_skin=dict(mouth=0.6, wounds=3, splat=0.2, frost=0.5),
   boots=("shoes04", (0.1, 0.09, 0.08), 0.1))
_z("rimebound_parka_f", "parka", 0.0, 37, (0.38, 0.1, 0.11), (0.2, 0.2, 0.24), 13, hair="hair/long01", hair_tint=(0.15, 0.13, 0.13), height=1.68, weight=0.45,
   gore_cloth=dict(mouth=1.0, soak=0.8, wounds=1, torn=1, splat=0.5, frost=0.45), gore_skin=dict(mouth=1.0, wounds=1, splat=0.4, frost=0.4), pants=(0.12, 0.13, 0.2))
_z("rimebound_flannel_m", "flannel", 1.0, 34, (0.52, 0.15, 0.12), (0.14, 0.16, 0.22), 14, hair="hair/short04", hair_tint=(0.18, 0.15, 0.13), height=1.78, weight=0.5,
   gore_cloth=dict(mouth=0.8, soak=0.9, wounds=2, torn=2, splat=0.5, frost=0.35), gore_skin=dict(mouth=0.8, wounds=2, splat=0.4, frost=0.3), boots=("shoes04", (0.12, 0.1, 0.08), 0.1))
_z("rimebound_tee_m", "tee_m", 1.0, 66, (0.62, 0.63, 0.64), (0.18, 0.2, 0.26), 15, hair=None, height=1.72, weight=0.4, pallor=(0.78, 0.84, 0.9),
   gore_cloth=dict(mouth=0.7, soak=1.0, wounds=2, torn=2, splat=0.6, frost=0.3), gore_skin=dict(mouth=0.7, wounds=2, splat=0.5, frost=0.3), boots=("shoes06", (0.3, 0.3, 0.32), 0.1))
_z("rimebound_tee_f", "tee_f", 0.0, 29, (0.28, 0.33, 0.42), (0.12, 0.14, 0.2), 16, hair="hair/bob01", hair_tint=(0.16, 0.12, 0.1), height=1.64, weight=0.42,
   gore_cloth=dict(mouth=0.9, soak=0.8, wounds=2, torn=1, splat=0.5, frost=0.3), gore_skin=dict(mouth=0.9, wounds=2, splat=0.4, frost=0.3), boots=("shoes06", (0.25, 0.25, 0.28), 0.1))
_z("rimebound_nurse", "nurse", 0.0, 41, (0.62, 0.7, 0.72), (0.55, 0.62, 0.64), 17, hair="hair/bob02", hair_tint=(0.3, 0.22, 0.17), height=1.66, weight=0.45,
   gore_cloth=dict(mouth=1.0, soak=1.0, wounds=3, torn=2, splat=0.6, frost=0.3), gore_skin=dict(mouth=1.0, wounds=2, splat=0.4, frost=0.3), boots=("shoes05", (0.62, 0.64, 0.66), 0.1))
_z("rimebound_miner", "miner", 1.0, 52, (0.13, 0.16, 0.22), (0.38, 0.1, 0.08), 18, hair="hair/short04", hair_tint=(0.2, 0.18, 0.16), height=1.78, weight=0.6, muscle=0.6,
   gloves=(0.3, 0.27, 0.22), gore_cloth=dict(mouth=0.7, soak=0.5, wounds=3, torn=2, splat=0.4, frost=0.5), gore_skin=dict(mouth=0.7, wounds=3, splat=0.3, frost=0.5),
   boots=("shoes02", (0.08, 0.07, 0.06), 0.2))
_z("rimebound_cop", "cop", 1.0, 40, (0.07, 0.1, 0.2), (0.1, 0.1, 0.12), 19, hair="hair/short03", hair_tint=(0.15, 0.13, 0.12), height=1.82, weight=0.55, muscle=0.55, pants=(0.07, 0.09, 0.16),
   gore_cloth=dict(mouth=0.8, soak=0.6, wounds=2, torn=2, splat=0.4, frost=0.5), gore_skin=dict(mouth=0.8, wounds=2, splat=0.3, frost=0.4))
_z("rimebound_patient", "patient", 1.0, 58, (0.55, 0.68, 0.72), (0.5, 0.62, 0.68), 20, hair="hair/short03", hair_tint=(0.5, 0.5, 0.52), height=1.72, weight=0.5, pallor=(0.8, 0.86, 0.92),
   gore_cloth=dict(mouth=0.9, soak=1.0, wounds=2, torn=2, splat=0.6, frost=0.2), gore_skin=dict(mouth=0.9, wounds=2, splat=0.5, frost=0.2), boots=None)

SPECIAL_DETAILS_HUSK = [("torso", "torso-scale-horiz", 0.9, "decr", "incr"), ("torso", "torso-scale-depth", 0.6, "decr", "incr"), ("neck", "neck-scale-horiz", 0.9, "decr", "incr"),
                        ("torso", "torso-vshape", 0.9, "decr", "incr"), ("head", "head-square", 0.6), ("armslegs", "l-upperarm-muscle", 1.0, "decr", "incr"), ("armslegs", "r-upperarm-muscle", 1.0, "decr", "incr"),
                        ("armslegs", "l-upperarm-fat", 0.6, "decr", "incr"), ("armslegs", "r-upperarm-fat", 0.6, "decr", "incr"), ("armslegs", "l-upperleg-muscle", 0.8, "decr", "incr"), ("armslegs", "r-upperleg-muscle", 0.8, "decr", "incr")]
_z("husk", "tee_m", 1.0, 40, (0.2, 0.2, 0.22), (0.14, 0.15, 0.2), 31, hair=None, height=2.0, weight=0.8, muscle=1.0, details=SPECIAL_DETAILS_HUSK,
   gore_cloth=dict(mouth=0.7, soak=0.7, wounds=2, torn=3, splat=0.4, frost=0.7), gore_skin=dict(mouth=0.6, wounds=2, splat=0.3, frost=0.8), boots=("shoes02", (0.07, 0.06, 0.05), 0.2),
   pallor=(0.65, 0.78, 0.92), body_dec=0.45)
_z("siren", "dress", 0.0, 33, (0.34, 0.34, 0.38), (0.28, 0.28, 0.32), 32, hair="hair/long01", hair_tint=(0.07, 0.07, 0.08), height=1.9, weight=0.0, muscle=0.0,
   open_mouth=True, pallor=(0.86, 0.9, 0.95), boots=None, height_slider=0.9,
   details=[("chin", "chin-jaw-drop", 1.0, "decr", "incr"), ("mouth", "mouth-scale-vert", 1.0, "decr", "incr"), ("mouth", "mouth-lowerlip-height", 1.0, "decr", "incr"),
            ("head", "head-age", 0.5, "decr", "incr"), ("eyes", "l-eye-bag", 1.0, "decr", "incr"), ("eyes", "r-eye-bag", 1.0, "decr", "incr"), ("cheek", "l-cheek-volume", -1.0, "decr", "incr"), ("cheek", "r-cheek-volume", -1.0, "decr", "incr")],
   gore_cloth=dict(mouth=1.0, soak=1.0, wounds=1, torn=1, splat=0.2, frost=0.5), gore_skin=dict(mouth=1.0, wounds=1, splat=0.2, frost=0.6))
_z("burster", "tee_m", 1.0, 48, (0.42, 0.44, 0.46), (0.16, 0.18, 0.24), 33, hair=None, height=1.75, weight=1.0, muscle=0.2,
   details=[("stomach", "stomach-pregnant", 1.0, "decr", "incr"), ("torso", "torso-scale-horiz", 0.7, "decr", "incr"), ("torso", "torso-scale-depth", 0.9, "decr", "incr"),
            ("hip", "hip-scale-horiz", 0.8, "decr", "incr"), ("neck", "neck-double", 1.0, "decr", "incr"), ("head", "head-fat", 1.0, "decr", "incr"), ("cheek", "l-cheek-volume", 1.0, "decr", "incr"),
            ("cheek", "r-cheek-volume", 1.0, "decr", "incr"), ("armslegs", "l-upperarm-fat", 1.0, "decr", "incr"), ("armslegs", "r-upperarm-fat", 1.0, "decr", "incr"),
            ("armslegs", "l-upperleg-fat", 1.0, "decr", "incr"), ("armslegs", "r-upperleg-fat", 1.0, "decr", "incr"), ("buttocks", "buttocks-volume", 1.0, "decr", "incr")], boots=("shoes06", (0.2, 0.2, 0.22), 0.1),
   gore_cloth=dict(mouth=0.5, soak=0.4, wounds=2, torn=3, splat=0.4, frost=0.6), gore_skin=dict(mouth=0.5, wounds=1, splat=0.3, frost=0.7), pallor=(0.72, 0.82, 0.9), body_dec=0.5)
_z("hanger", "flannel", 1.0, 36, (0.22, 0.24, 0.3), (0.14, 0.15, 0.2), 34, hair="hair/long01", hair_tint=(0.1, 0.1, 0.1), height=2.1, weight=0.0, muscle=0.1,
   height_slider=1.0, boots=None, gore_cloth=dict(mouth=0.8, soak=0.8, wounds=2, torn=3, splat=0.5, frost=0.5), gore_skin=dict(mouth=0.8, wounds=2, splat=0.4, frost=0.5),
   pallor=(0.74, 0.84, 0.92))
_z("foreman", "jacket", 1.0, 58, (0.42, 0.18, 0.06), (0.2, 0.2, 0.22), 35, hair=None, height=1.95, weight=0.45, muscle=0.6, extras=["foreman_hat"], pants=(0.2, 0.2, 0.2),
   gloves=(0.1, 0.09, 0.07), boots=("shoes02", (0.07, 0.06, 0.05), 0.22), gore_cloth=dict(mouth=0.6, soak=0.5, wounds=3, torn=2, splat=0.4, frost=0.7),
   gore_skin=dict(mouth=0.6, wounds=3, splat=0.3, frost=0.8), pallor=(0.66, 0.74, 0.84))
# clean NPC bodies
_z("imogen", "jacket", 0.0, 45, (0.3, 0.32, 0.22), (0.2, 0.2, 0.22), 41, hair="hair/ponytail01", hair_tint=(0.35, 0.2, 0.12), height=1.7, weight=0.45, clean=True,
   gore_cloth=dict(), gore_skin=dict(), pants=(0.15, 0.17, 0.22), pallor=(1, 1, 1), boots=("shoes02", (0.2, 0.14, 0.09), 0.2), skin="middleage_caucasian_female")
_z("caretaker", "flannel", 1.0, 62, (0.35, 0.36, 0.38), (0.2, 0.2, 0.24), 42, hair="hair/short03", hair_tint=(0.65, 0.65, 0.68), height=1.74, weight=0.55, clean=True,
   gore_cloth=dict(), gore_skin=dict(), pallor=(1, 1, 1), boots=("shoes04", (0.13, 0.1, 0.08), 0.1), skin="old_caucasian_male")

ORANGE = np.array([0.93, 0.34, 0.035])
BLACK = np.array([0.045, 0.047, 0.05])
SILVER = np.array([0.62, 0.64, 0.67])


def ensure(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    return path


def jtex(name, arr, quality=90):
    p = ensure(os.path.join(TEX, name))
    pt.save_img(arr, p, quality)
    return p


def make_pbr(name, base_path, normal_path=None, mr_path=None, rough=0.85, metal=0.0, alpha=False, max_size=None,
             color=(1, 1, 1, 1), spec=0.35):
    """Principled material; mr_path: texture with G=roughness B=metal (glTF layout)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bs.outputs["BSDF"], out.inputs["Surface"])
    bs.inputs["Roughness"].default_value = rough
    bs.inputs["Metallic"].default_value = metal
    try: bs.inputs["Specular IOR Level"].default_value = spec
    except KeyError: pass
    bs.inputs["Base Color"].default_value = color
    if base_path:
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = bc.tex_image(base_path, "sRGB", max_size)
        nt.links.new(t.outputs["Color"], bs.inputs["Base Color"])
        if alpha:
            nt.links.new(t.outputs["Alpha"], bs.inputs["Alpha"])
    if normal_path:
        t = nt.nodes.new("ShaderNodeTexImage"); t.image = bc.tex_image(normal_path, "Non-Color", max_size)
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(t.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bs.inputs["Normal"])
    if mr_path:
        t = nt.nodes.new("ShaderNodeTexImage"); t.image = bc.tex_image(mr_path, "Non-Color", max_size)
        sp = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(t.outputs["Color"], sp.inputs["Color"])
        nt.links.new(sp.outputs["Green"], bs.inputs["Roughness"])
        nt.links.new(sp.outputs["Blue"], bs.inputs["Metallic"])
    return m


def solid_mat(name, color, rough=0.8, metal=0.0):
    """color given in sRGB (0..1)"""
    c = [float(v) ** 2.2 for v in color[:3]] + [1.0]
    return make_pbr(name, None, rough=rough, metal=metal, color=tuple(c))


# ------------------------------------------------------------------ skin
def paint_skin(cb, skin_name, details, stubble=1.0, weather=1.0, tint=(0.97, 0.90, 0.85)):
    """Bake stubble/weathering into a copy of the MakeHuman skin texture."""
    size = 2048
    base = pt.load_rgb(A("skins", skin_name, [f for f in os.listdir(A("skins", skin_name)) if f.endswith(".png")][0]), size)
    H = cb.H
    pos = cb.conv(H.v[:mh.N_BODY])
    tris = pt.tri_list(H.body_faces)
    nrm = pt.vertex_normals(pos, [f[0] for f in H.body_faces])
    r = pt.rasterize(tris, H.uv, {"pos": pos, "nrm": nrm}, size)
    p = r["pos"]; x, y, z = p[:, 0], p[:, 1], p[:, 2]
    eye_z = cb.conv(H.joint("joint-l-eye"))[2]
    mouth_z = eye_z - 0.066
    chin_z = eye_z - 0.108
    head = (z > chin_z - 0.07)
    fwd = np.clip((-(y) - 0.045) / 0.03, 0, 1)          # front of face
    ax = np.abs(x)
    px_, py_ = r["x"], r["y"]
    rgb = base[py_, px_].copy()
    n1 = pt.hash_noise(px_, py_, 1); n2 = pt.hash_noise(px_ // 2, py_ // 2, 7)
    # ---- stubble (jaw, chin, upper lip, cheeks, neck)
    low = pt.smoothstep(mouth_z + 0.040, mouth_z + 0.005, z)           # fade up the cheek
    below = pt.smoothstep(chin_z - 0.095, chin_z - 0.035, z)           # fade down the neck
    side = pt.smoothstep(0.105, 0.075, ax)
    lips = 1 - pt.smoothstep(0.0, 1.0, np.clip(1 - (np.abs(z - (mouth_z - 0.002)) / 0.011) , 0, 1)) * pt.smoothstep(0.034, 0.026, ax)
    lips = 1.0 - np.clip(1.2 - np.sqrt((np.abs(z - (mouth_z - 0.002)) / 0.013) ** 2 + (ax / 0.034) ** 2), 0, 1)
    nostril = pt.smoothstep(mouth_z + 0.022, mouth_z + 0.012, z) * 0 + 1
    w = low * below * side * fwd * lips
    w = w * (0.75 + 0.25 * n2)
    speck = (n1 > 0.52).astype(np.float32)
    dark = np.array([0.20, 0.15, 0.12])
    shadow = 0.34 * w * stubble                                       # smooth 5 o'clock shadow
    rgb = rgb * (1 - shadow[:, None]) + (rgb * dark) * shadow[:, None] * 0.0
    rgb = rgb * (1 - 0.5 * stubble * (w * speck)[:, None]) + dark * (0.5 * stubble * (w * speck))[:, None]
    # ---- weathering: ruddy cheeks / nose, eye bags, forehead lines
    flush = np.exp(-(((ax - 0.055) / 0.035) ** 2 + ((z - (eye_z - 0.04)) / 0.03) ** 2)) * fwd
    nose = np.exp(-(((x) / 0.02) ** 2 + ((z - (eye_z - 0.038)) / 0.02) ** 2)) * fwd
    ruddy = np.array([1.0, 0.80, 0.76])
    k = np.clip((0.55 * flush + 0.5 * nose) * weather, 0, 0.6)[:, None]
    rgb = rgb * (1 - k) + rgb * ruddy * k
    bag = np.exp(-(((ax - 0.032) / 0.026) ** 2 + ((z - (eye_z - 0.017)) / 0.008) ** 2)) * fwd
    rgb = rgb * (1 - 0.18 * weather * bag[:, None]) + rgb * np.array([0.85, 0.75, 0.85]) * 0.18 * weather * bag[:, None]
    for off in (0.036, 0.052, 0.068):
        line = np.exp(-(((z - (eye_z + off + 0.006 * np.sin(x * 90))) / 0.0016) ** 2)) * pt.smoothstep(0.075, 0.05, ax) * fwd
        rgb = rgb * (1 - 0.10 * weather * line[:, None])
    # tone: slightly deeper / less pale
    rgb = rgb * np.array(tint)
    cov = np.zeros((size, size), dtype=bool); cov[py_, px_] = True
    out = base.copy() * np.array(tint)
    out[py_, px_] = np.clip(rgb, 0, 1)
    out = pt.dilate(out, cov, 6)
    return jtex(f"{cb.name}_skin.jpg", out, 92)


# ------------------------------------------------------------------ jacket
def jacket_texture(cb, label, P, pos, comp, jacket_ids, size=2048, orig=None):
    """hi-vis orange/black quilted jacket texture + metallic-roughness map (silver reflective bands)."""
    H = cb.H
    Wd = P.skin_weights(cb.Wfull)
    names = cb.bones
    def wsum(*bn):
        return sum(Wd[:, names.index(b)] for b in bn if b in names)[:, None]
    attrs = {"pos": pos, "w_arm": wsum("upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "hand_l", "hand_r"),
             "w_fore": wsum("lowerarm_l", "lowerarm_r", "hand_l", "hand_r"),
             "w_clav": wsum("clavicle_l", "clavicle_r")}
    tris = [t for t in pt.tri_list(P.faces) if comp[t[0]] in jacket_ids]
    r = pt.rasterize(tris, P.uv, attrs, size)
    p = r["pos"]; x, y, z = p[:, 0], p[:, 1], p[:, 2]
    ax = np.abs(x)
    S = cb.conv(H.joint("joint-l-shoulder")); E = cb.conv(H.joint("joint-l-elbow")); Wr = cb.conv(H.joint("joint-l-hand"))
    q = np.stack([ax, y, z], axis=1)
    def seg(a, b):
        ab = b - a; t = np.clip(((q - a) @ ab) / (ab @ ab), 0, 1)
        d = np.linalg.norm(q - (a + t[:, None] * ab), axis=1)
        return t, d
    t1, d1 = seg(S, E); t2, d2 = seg(E, Wr)
    l1 = np.linalg.norm(E - S); l2 = np.linalg.norm(Wr - E)
    use1 = d1 <= d2
    s = np.where(use1, t1 * l1, l1 + t2 * l2)          # distance along arm from shoulder
    arm_len = l1 + l2
    arm = (r["w_arm"][:, 0] > 0.5)
    chest_z = cb.conv(H.joint("joint-spine-2"))[2]
    waist_z = cb.conv(H.joint("joint-spine-4"))[2]
    neck_z = cb.conv(H.joint("joint-neck"))[2]
    px_, py_ = r["x"], r["y"]
    # luminance detail from the original suit texture (stitching, wear)
    o = orig[py_, px_]
    lum = (o * np.array([0.3, 0.59, 0.11])).sum(1)
    lum = np.clip(lum / max(np.median(lum), 1e-3), 0.6, 1.4)
    lum = 0.55 + 0.45 * lum
    # ---- region masks
    hem_z = float(p[:, 2].min() + 0.0) if False else waist_z - 0.22
    black = np.zeros(len(p), dtype=np.float32)
    torso = ~arm
    black += torso * pt.smoothstep(neck_z - 0.075, neck_z - 0.045, z)                    # collar / yoke
    black += torso * pt.smoothstep(waist_z - 0.075, waist_z - 0.105, z)                  # hem panel
    black += torso * pt.smoothstep(0.155, 0.185, ax) * (z < chest_z + 0.17)              # side panels
    black += arm * pt.smoothstep(arm_len - 0.17, arm_len - 0.15, s)                       # forearm cuffs
    black += arm * (1 - pt.smoothstep(0.03, 0.06, s)) * 0.0
    black += arm * pt.smoothstep(neck_z - 0.085, neck_z - 0.06, z) * (s < 0.10)           # shoulder cap
    black = np.clip(black, 0, 1)
    # reflective silver bands
    def band(c, wd, v):
        return pt.smoothstep(c - wd, c - wd + 0.004, v) * (1 - pt.smoothstep(c + wd - 0.004, c + wd, v))
    silver = torso * np.maximum(band(chest_z - 0.02, 0.026, z), band(waist_z - 0.01, 0.026, z))
    silver += arm * np.maximum(band(0.20, 0.02, s), band(0.43, 0.02, s)) * (s < arm_len - 0.01)
    # vertical shoulder-to-hem straps (front and back)
    strap = torso * (1 - pt.smoothstep(0.016, 0.02, np.abs(ax - 0.085))) * (z > waist_z - 0.07) * (z < neck_z - 0.04) * (y > S[1] + 0.02)
    silver = np.clip(silver + strap, 0, 1)
    # ---- quilting baffles: horizontal seams on torso, rings on sleeves
    per_t = 0.082; per_a = 0.075
    u = np.where(arm, s / per_a, z / per_t)
    fr = u - np.floor(u)
    seam = np.exp(-(((fr - 0.0) if True else 0) ** 2) / 0.0012) + np.exp(-((fr - 1.0) ** 2) / 0.0012)
    puff = 0.78 + 0.22 * np.sin(np.pi * fr) ** 0.6
    # ---- compose
    col = ORANGE[None] * (1 - black[:, None]) + BLACK[None] * black[:, None]
    col = col * puff[:, None] * lum[:, None]
    col = col * (1 - 0.55 * np.clip(seam, 0, 1)[:, None] * (1 - silver[:, None]))
    # dirt: darker low on the jacket, around elbows, noise
    n = pt.hash_noise(px_ // 3, py_ // 3, 3)
    dirt = np.clip(0.25 * pt.smoothstep(waist_z + 0.1, waist_z - 0.2, z) + 0.12 * n, 0, 0.4)
    col = col * (1 - dirt[:, None]) + np.array([0.14, 0.11, 0.09]) * dirt[:, None] * 0.5
    sv = SILVER[None] * (0.82 + 0.18 * lum[:, None])
    col = col * (1 - silver[:, None]) + sv * silver[:, None]
    # metallic-roughness (G rough, B metal)
    mr = np.zeros((len(p), 3), dtype=np.float32)
    mr[:, 0] = 1.0
    mr[:, 1] = 0.82 * (1 - silver) + 0.30 * silver
    mr[:, 2] = 0.0 * (1 - silver) + 0.55 * silver
    cov = np.zeros((size, size), dtype=bool); cov[py_, px_] = True
    img = np.zeros((size, size, 3), dtype=np.float32); img[py_, px_] = np.clip(col, 0, 1)
    img = pt.dilate(img, cov, 8)
    mrimg = np.zeros((size, size, 3), dtype=np.float32); mrimg[..., 0] = 1; mrimg[..., 1] = 0.85
    mrimg[py_, px_] = mr; mrimg = pt.dilate(mrimg, cov, 8)
    return jtex(f"{cb.name}_{label}_diffuse.jpg", img, 90), jtex(f"{cb.name}_{label}_mr.jpg", mrimg, 92)


def recolor_texture(cb, label, P, pos, comp, ids, color, size, orig, contrast=0.5, gain=1.0):
    """simple tint of an existing diffuse: luminance detail * colour."""
    tris = [t for t in pt.tri_list(P.faces) if comp[t[0]] in ids]
    r = pt.rasterize(tris, P.uv, {"pos": pos}, size)
    px_, py_ = r["x"], r["y"]
    o = orig[py_, px_]
    lum = (o * np.array([0.3, 0.59, 0.11])).sum(1)
    med = max(float(np.median(lum)), 1e-3)
    lum = (1 - contrast) + contrast * np.clip(lum / med, 0.3, 2.0)
    col = np.array(color)[None] * lum[:, None] * gain
    cov = np.zeros((size, size), dtype=bool); cov[py_, px_] = True
    img = np.zeros((size, size, 3), dtype=np.float32); img[py_, px_] = np.clip(col, 0, 1)
    img = pt.dilate(img, cov, 8)
    return jtex(f"{cb.name}_{label}_diffuse.jpg", img, 90)


def normals_jpg(cb, label, src, size):
    im = pt.load_rgb(src, size)
    return jtex(f"{cb.name}_{label}_normal.jpg", im, 92)


def hair_png(cb, label, src, size=1024, tint=None):
    from PIL import Image
    im = Image.open(src).convert("RGBA").resize((size, size), Image.LANCZOS)
    if tint is not None:
        a = np.asarray(im, dtype=np.float32) / 255.0
        a[..., :3] = np.clip(a[..., :3] * np.array(tint)[None, None, :], 0, 1)
        im = Image.fromarray((a * 255 + 0.5).astype(np.uint8))
    p = ensure(os.path.join(TEX, f"{cb.name}_{label}.png")); im.save(p); return p


def eye_image(name, iris=(0.55, 0.36, 0.22), strength=1.0, size=512):
    """MakeHuman eye atlas with the (reddish) iris re-coloured; sclera kept."""
    from PIL import Image
    eim = np.asarray(Image.open(os.path.join(mh.MH_DATA, "eyes/materials/brown_eye.png")).convert("RGB").resize((size, size)), dtype=np.float32) / 255.0
    lum = (eim * np.array([0.3, 0.59, 0.11])).sum(2, keepdims=True)
    sat = (eim.max(2, keepdims=True) - eim.min(2, keepdims=True))
    mask = np.clip(sat * 3.5, 0, 1) * strength
    iris_col = lum * 2.0 * np.array(iris)[None, None, :]
    out = eim * (1 - mask) + iris_col * mask
    out = out * 0.92
    return jtex(name, np.clip(out, 0, 1), 92)


def messy(pos, faces, amp=0.008, seed=1):
    n = pt.vertex_normals(pos, [f[0] for f in faces])
    p = pos * 40.0 + seed
    noise = (np.sin(p[:, 0] * 1.7 + np.cos(p[:, 1] * 2.3)) + np.sin(p[:, 1] * 1.3 + p[:, 2] * 2.1) + np.cos(p[:, 2] * 1.9 + p[:, 0] * 0.7)) / 3.0
    return pos + n * (noise * amp)[:, None]


def inflate(pos, faces, amount):
    n = pt.vertex_normals(pos, [f[0] for f in faces])
    return pos + n * amount


# ------------------------------------------------------------------ helpers: body-derived geometry
def body_surface_patch(cb, vmask, offset, W=True):
    """Copy of the (full) morphed body faces whose verts are all in vmask, offset along normals."""
    H = cb.H
    pos = cb.conv(H.v[:mh.N_BODY])
    nrm = pt.vertex_normals(pos, [f[0] for f in H.body_faces])
    sub, fv, ft, remap, used = cb.sub_mesh(pos, H.body_faces, vmask)
    sub = sub + nrm[used] * offset
    return sub, fv, ft, used


def ring_outline(pos_sel, center_xy, nbins=48):
    """outer radius per angular bin for points -> (angles, radii)"""
    d = pos_sel[:, :2] - center_xy
    ang = np.arctan2(d[:, 1], d[:, 0]); rad = np.hypot(d[:, 0], d[:, 1])
    bins = ((ang + np.pi) / (2 * np.pi) * nbins).astype(int) % nbins
    r = np.zeros(nbins)
    for b in range(nbins):
        m = bins == b
        r[b] = rad[m].max() if m.any() else np.nan
    idx = np.arange(nbins); ok = ~np.isnan(r)
    r = np.interp(idx, idx[ok], r[ok], period=nbins)
    return (np.arange(nbins) + 0.5) / nbins * 2 * np.pi - np.pi, r


def box_mesh(center, size, rot_z=0.0):
    sx, sy, sz = [s / 2 for s in size]
    v = np.array([[-sx, -sy, -sz], [sx, -sy, -sz], [sx, sy, -sz], [-sx, sy, -sz],
                  [-sx, -sy, sz], [sx, -sy, sz], [sx, sy, sz], [-sx, sy, sz]])
    c, s_ = math.cos(rot_z), math.sin(rot_z)
    R = np.array([[c, -s_, 0], [s_, c, 0], [0, 0, 1]])
    v = v @ R.T + np.array(center)
    f = [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
    return v, f


def merge_meshes(parts):
    V, F = [], []; off = 0
    for v, f in parts:
        V.append(v); F += [[i + off for i in fc] for fc in f]; off += len(v)
    return np.concatenate(V), F


# ------------------------------------------------------------------ ELIAS
def assemble(cb, spec):
    if spec.get("builder"):
        import importlib
        mod, fn = spec["builder"].split(".") if "." in spec["builder"] else ("chars2", spec["builder"])
        return getattr(importlib.import_module(mod), fn)(cb, spec)
    n = spec["name"]
    H = cb.H
    skin_png = paint_skin(cb, spec["skin"], spec["details"], spec.get("stubble", 1.0), spec.get("weather", 1.0), spec.get("skin_tint", (0.97, 0.90, 0.85)))
    skin_mat = make_pbr(n + "_skin", skin_png, rough=0.58, spec=0.4)

    # ---------- suit proxy (casualsuit05): jacket / liner / trousers
    SUIT = A("clothes/male_casualsuit05/male_casualsuit05.mhclo")
    P = mh.Proxy(SUIT)
    pos = cb.conv(P.fit(H.v, H.base_v))
    comp = cb.components(P)
    ncomp = comp.max() + 1
    zmin = [pos[comp == c][:, 2].min() for c in range(ncomp)]
    sizes = [int((comp == c).sum()) for c in range(ncomp)]
    trousers = [c for c in range(ncomp) if zmin[c] < 0.3 and pos[comp == c][:, 2].max() < 1.2 and sizes[c] > 500]
    big = max((c for c in range(ncomp) if c not in trousers), key=lambda c: sizes[c])
    jacket_ids = {big}
    liner_ids = {c for c in range(ncomp) if c not in trousers and c != big}
    print("suit comps", sizes, "trousers", trousers, "jacket", big)
    orig = pt.load_rgb(A("clothes/male_casualsuit05/male_casualsuit05_diffuse.png"), 2048)
    nrm_src = A("clothes/male_casualsuit05/male_casualsuit05_normal.png")
    nrm_jpg = normals_jpg(cb, "suit", nrm_src, 1024)
    jd, jmr = jacket_texture(cb, "jacket", P, pos, comp, jacket_ids, 2048, orig)
    jmat = make_pbr(n + "_jacket", jd, nrm_jpg, jmr, rough=0.8)
    td = recolor_texture(cb, "trousers", P, pos, comp, set(trousers), (0.115, 0.125, 0.145), 1024, pt.load_rgb(A("clothes/male_casualsuit05/male_casualsuit05_diffuse.png"), 1024), contrast=0.35)
    tmat = make_pbr(n + "_trousers", td, nrm_jpg, rough=0.9)
    lmat = solid_mat(n + "_liner", (0.16, 0.16, 0.17), 0.9)

    # puff the jacket (insulated): inflate + baffle displacement
    npos = pos.copy()
    nrm = pt.vertex_normals(pos, [f[0] for f in P.faces])
    jm = np.isin(comp, list(jacket_ids))
    S_z = cb.conv(H.joint("joint-spine-4"))[2]
    puff = 0.012 + 0.006 * np.sin(2 * math.pi * pos[:, 2] / 0.082)
    npos[jm] = pos[jm] + nrm[jm] * puff[jm][:, None]
    boot_top = 0.24
    for ids, label, mat, ppos in ((jacket_ids, "jacket", jmat, npos), (liner_ids, "liner", lmat, pos), (set(trousers), "trousers", tmat, pos)):
        mask = np.isin(comp, list(ids))
        if label == "trousers":
            mask = mask & (pos[:, 2] > boot_top - 0.02)
        sub, fv, ft, remap, used = cb.sub_mesh(ppos, P.faces, mask)
        Wd = P.skin_weights(cb.Wfull)[used]
        cb.add_mesh(label, sub, fv, ft, P.uv, W=Wd, mat=mat)
    del_verts = set(P.delete_verts)

    # ---------- boots (shoes02 recoloured, enlarged) + shaft
    SH = A("clothes/shoes02/shoes02.mhclo")
    Ps = mh.Proxy(SH)
    spos = cb.conv(Ps.fit(H.v, H.base_v))
    for side in (1, -1):
        m = (spos[:, 0] * side) > 0
        c = np.array([spos[m][:, 0].mean(), spos[m][:, 1].mean(), 0.0])
        spos[m] = c + (spos[m] - c) * np.array([1.12, 1.10, 1.25])
    sn = pt.vertex_normals(spos, [f[0] for f in Ps.faces])
    spos = spos + sn * 0.006
    so = pt.load_rgb(A("clothes/shoes02/shoes02_diffuse.png"), 1024)
    sd = recolor_texture(cb, "boots", Ps, spos, np.zeros(len(spos), dtype=np.int64), {0}, (0.075, 0.062, 0.05), 1024, so, contrast=0.55)
    bmat = make_pbr(n + "_boots", sd, rough=0.7)
    bo = cb.add_mesh("boots", spos, [f[0] for f in Ps.faces], [f[1] for f in Ps.faces], Ps.uv, W=Ps.skin_weights(cb.Wfull), mat=bmat)
    cb.decimate(bo, 0.6)
    del_verts |= set(Ps.delete_verts)
    bpos = cb.conv(H.v[:mh.N_BODY])
    shaft_mask = (bpos[:, 2] > 0.045) & (bpos[:, 2] < 0.26) & (np.abs(bpos[:, 0]) > 0.05)
    sp, sfv, sft, used = body_surface_patch(cb, shaft_mask, 0.016)
    cb.add_mesh("boot_shaft", sp, sfv, None, None, W=cb.W[used], mat=solid_mat(n + "_bootshaft", (0.11, 0.095, 0.08), 0.65))
    ring_mask = (bpos[:, 2] > 0.19) & (bpos[:, 2] < 0.28) & (np.abs(bpos[:, 0]) > 0.05)
    rp, rfv, rft, rused = body_surface_patch(cb, ring_mask, 0.026)
    cb.add_mesh("boot_cuff", rp, rfv, None, None, W=cb.W[rused], mat=solid_mat(n + "_bootcuff", (0.13, 0.12, 0.11), 0.8))
    below = set(np.where(bpos[:, 2] < 0.28)[0].tolist())
    del_verts |= below

    # ---------- gloves from the hand region of the body
    hand_names = [b for b in cb.bones if any(k in b for k in ("hand_", "thumb", "index", "middle", "ring", "pinky"))]
    hi = [cb.bones.index(b) for b in hand_names]
    hw = cb.W[:, hi].sum(1)
    gmask = hw > 0.3
    lw = cb.W[:, [cb.bones.index("lowerarm_l"), cb.bones.index("lowerarm_r")]].sum(1)
    wristL = cb.conv(H.joint("joint-l-hand")); wristR = wristL * np.array([-1, 1, 1])
    near = (np.minimum(np.linalg.norm(bpos - wristL, axis=1), np.linalg.norm(bpos - wristR, axis=1)) < 0.075) & (lw > 0.3)
    gmask = gmask | near
    gp, gfv, gft, gused = body_surface_patch(cb, gmask, 0.005)
    gl = solid_mat(n + "_gloves", (0.42, 0.33, 0.22), 0.75)
    go = cb.add_mesh("gloves", gp, gfv, None, None, W=cb.W[gused], mat=gl)
    cb.decimate(go, 0.36)
    del_verts |= set(np.where(gmask)[0].tolist())

    # ---------- tool belt (over the jacket hem)
    belt_z = S_z - 0.075
    jsel = pos[jm]
    zsel = jsel[(np.abs(jsel[:, 2] - belt_z) < 0.03)]
    cxy = np.array([0.0, float(zsel[:, 1].mean())])
    ang, rad = ring_outline(zsel + 0, cxy, 48)
    rad = rad + 0.012
    nb = len(ang)
    ringv = []
    for zz in (belt_z - 0.028, belt_z + 0.028):
        for a, r_ in zip(ang, rad):
            ringv.append([cxy[0] + math.cos(a) * r_, cxy[1] + math.sin(a) * r_, zz])
    ringv = np.array(ringv)
    rf = []
    for i in range(nb):
        j = (i + 1) % nb
        rf.append([i, j, nb + j, nb + i])
    belt_outer = ringv
    belt_inner = ringv.copy(); belt_inner[:, :2] = cxy + (belt_inner[:, :2] - cxy) * 0.985
    bv, bf = merge_meshes([(belt_outer, rf), (belt_inner, [f[::-1] for f in rf])])
    belt_parts = [(bv, bf)]
    def at_angle(a_deg, extra):
        a = math.radians(a_deg)
        k = int(((a + math.pi) / (2 * math.pi)) * nb) % nb
        r_ = rad[k] + extra
        return np.array([cxy[0] + math.cos(a) * r_, cxy[1] + math.sin(a) * r_]), a
    pouch_parts = []
    for a_deg, size, zc in ((-20, (0.05, 0.11, 0.14), belt_z - 0.07), (200, (0.05, 0.11, 0.14), belt_z - 0.07),
                            (-100, (0.12, 0.05, 0.1), belt_z - 0.02), (90, (0.16, 0.06, 0.12), belt_z - 0.01),
                            (160, (0.04, 0.05, 0.28), belt_z - 0.14)):
        xy, a = at_angle(a_deg, size[1] / 2 + 0.005)
        pouch_parts.append(box_mesh([xy[0], xy[1], zc], size, rot_z=a + math.pi / 2))
    hv, hf = box_mesh([at_angle(165, 0.03)[0][0], at_angle(165, 0.03)[0][1], belt_z - 0.20], (0.03, 0.03, 0.34), rot_z=0.0)
    pouch_parts.append((hv, hf))
    belt_mat = solid_mat(n + "_belt", (0.12, 0.1, 0.09), 0.6)
    pv, pf = merge_meshes(belt_parts)
    cb.add_mesh("belt", pv, pf, bone="pelvis", mat=belt_mat, smooth=False)
    pv, pf = merge_meshes(pouch_parts)
    po = cb.add_mesh("pouches", pv, pf, bone="pelvis", mat=solid_mat(n + "_pouch", (0.33, 0.2, 0.12), 0.55), smooth=True)
    bev = po.modifiers.new("bev", 'BEVEL'); bev.width = 0.012; bev.segments = 2; bev.limit_method = 'NONE'
    bpy.context.view_layer.objects.active = po
    bpy.ops.object.modifier_move_to_index(modifier="bev", index=0)
    bpy.ops.object.modifier_apply(modifier="bev")

    # ---------- body (head, neck + whatever is not covered)
    body = cb.build_body(sorted(del_verts))
    body.data.materials.append(skin_mat)
    cb.decimate(body, 0.8)

    # ---------- eyes / brows / lashes / hair
    eye_jpg = eye_image(n + "_eye.jpg", spec.get("iris", (0.50, 0.33, 0.2)))
    emat = make_pbr(n + "_eyes", eye_jpg, rough=0.12, spec=0.8)
    P_e = mh.Proxy(A("eyes/low-poly/low-poly.mhclo"))
    epos = cb.conv(P_e.fit(H.v, H.base_v))
    ob = cb.add_mesh("eyes", epos, [f[0] for f in P_e.faces], [f[1] for f in P_e.faces], P_e.uv, bone="head", mat=emat)
    sub = ob.modifiers.new("sub", 'SUBSURF'); sub.levels = 1; sub.render_levels = 1
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_move_to_index(modifier="sub", index=0)
    bpy.ops.object.modifier_apply(modifier="sub")
    for nm, d, col, mat_alpha in (("brows", "eyebrows/eyebrow001/eyebrow001", (0.09, 0.07, 0.06), True),
                                   ("lashes", "eyelashes/eyelashes01/eyelashes01", (0.05, 0.04, 0.04), True)):
        Pp = mh.Proxy(A(d + ".mhclo"))
        tex = [f for f in os.listdir(os.path.dirname(A(d))) if f.endswith(".png")][0]
        png = os.path.join(os.path.dirname(A(d)), tex)
        m = make_pbr(n + "_" + nm, hair_png(cb, nm, png, 512, tint=spec.get("brow_tint", (0.45, 0.4, 0.38)) if nm == "brows" else (0.5, 0.45, 0.45)), rough=0.8, alpha=True)
        pp = cb.conv(Pp.fit(H.v, H.base_v))
        cb.add_mesh(nm, pp, [f[0] for f in Pp.faces], [f[1] for f in Pp.faces], Pp.uv, bone="head", mat=m)
    Ph = mh.Proxy(A("hair/short02/short02.mhclo"))
    hm = make_pbr(n + "_hair", hair_png(cb, "hair", A("hair/short02/short02_diffuse.png"), 1024, tint=spec.get("hair_tint", (0.2, 0.17, 0.15))), rough=0.7, alpha=True)
    hp = messy(cb.conv(Ph.fit(H.v, H.base_v)), Ph.faces, 0.007)
    cb.add_mesh("hair", hp, [f[0] for f in Ph.faces], [f[1] for f in Ph.faces], Ph.uv, W=Ph.skin_weights(cb.Wfull), mat=hm)
