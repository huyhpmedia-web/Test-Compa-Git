import sys
sys.path.insert(0, "/tmp/claude-0/-home-user-Test-Compa-Git/b7d788c3-cd16-57ba-98fb-70cb388fdafd/scratchpad")
from e_lib import *
import numpy as np

ET = S + "/e_tex/"


def M(name, a=None, r=None, n=None, color=(0.5, 0.5, 0.5, 1), rv=0.5, metal=0.0):
    return mat_pbr(name, albedo=(ET + a if a else None), rough=(ET + r if r else None), normal=(ET + n if n else None), color=color, rough_val=rv, metal=metal)


def solid(name, color, rv=0.5, metal=0.0):
    return mat_pbr(name, color=color, rough_val=rv, metal=metal)


def brass(): return M("brass", "brass_a.png", "metal_r.png", None, rv=0.35, metal=1.0)
def chrome(): return M("chrome", "chrome_a.png", "metal_r.png", None, rv=0.3, metal=1.0)
def rust(): return M("rust", "rust_a.png", "rust_r.png", "rust_n.png", rv=0.7, metal=0.6)
def wood(): return M("wood", "wood_a.png", "wood_r.png", "wood_n.png", rv=0.7)


def verts_np(o):
    me = o.data
    return np.array([(o.matrix_world @ v.co)[:] for v in me.vertices], dtype=np.float64)


def pca_align(objs, flip_bow=True):
    """longest axis -> +X (blade/far end +X, wide 'bow' at -X), thinnest -> Z."""
    allv = np.vstack([verts_np(o) for o in objs])
    c = allv.mean(axis=0)
    u, s, vt = np.linalg.svd(allv - c, full_matrices=False)
    e1, e2, e3 = vt[0], vt[1], vt[2]
    if np.dot(np.cross(e1, e2), e3) < 0:
        e3 = -e3
    p1 = (allv - c) @ e1
    p2 = np.abs((allv - c) @ e2)
    lo = p1 < np.percentile(p1, 25)
    hi = p1 > np.percentile(p1, 75)
    if flip_bow and p2[hi].mean() > p2[lo].mean():
        e1, e2 = -e1, -e2
    R = np.array([e1, e2, e3])  # rows
    m = Matrix([[R[i][j] for j in range(3)] + [0] for i in range(3)] + [[0, 0, 0, 1]])
    for o in objs:
        o.matrix_world = m @ Matrix.Translation(-Vector(c)) @ o.matrix_world
    sel(objs)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def std(id_, objs, longest, rotate=(0, 0, 0), tri=8000):
    objs = [o for o in objs if o.name in bpy.data.objects]
    if any(rotate):
        rot(objs, rotate)
    fit_max(objs, longest)
    center(objs)
    export(id_, objs, tri)


def tag_obj(name, tex, w, h, t, loc, rz=0, grommet=True):
    m = M(name + "_m", tex, rv=0.8)
    o = box(name, w, h, t, loc, m)
    planar_uv(o, w, h)
    # front/back faces use full UV from calc_uvs
    parts = [o]
    if grommet:
        g = torus(name + "_g", w * 0.07, w * 0.02, (loc[0], loc[1] + h * 0.38, loc[2]), brass(), rotx=0)
        box_uv(g, 0.02)
        parts.append(g)
    j = join(parts, name)
    j.rotation_euler = (0, 0, math.radians(rz))
    sel([j]); bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return j


def lathe(name, profile, seg=24, mat=None):
    bm = bmesh.new()
    pts = [bm.verts.new((r, 0, z)) for r, z in profile]
    for a, b in zip(pts[:-1], pts[1:]):
        bm.edges.new((a, b))
    bmesh.ops.spin(bm, geom=list(bm.verts) + list(bm.edges), axis=(0, 0, 1), cent=(0, 0, 0), angle=2 * math.pi, steps=seg, use_merge=True)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = new_obj(name, bm)
    if mat:
        o.data.materials.append(mat)
    shade_smooth(o)
    return o


def make_key_aligned(src, length):
    ms = import_glb(src)
    k = join(ms, "key")
    pca_align([k])
    fit_max([k], length)
    return k


# ---------------------------------------------------------------- builders
def b_ammo_9mm():
    ms = import_glb("e_ammo_9mm")
    std("ammo_9mm", ms, 0.115, rotate=(180, 0, 90))


def b_ammo_shell():
    ms = import_glb("e_ammo_shell")
    std("ammo_shell", ms, 0.14)


def b_ammo_44():
    ms = import_glb("e_ammo_44")
    std("ammo_44", ms, 0.12)


def b_ammo_grenade():
    ms = import_glb("e_ammo_flare", keep=lambda o: ("Red" in o.name or "Green" in o.name))
    std("ammo_grenade", ms, 0.12)


def b_powder():
    ms = import_glb("e_powder")
    base = [o for o in ms if "Base" in o.name][0]
    mn, mx = bbox([base])
    c = (mn + mx) * 0.5
    r = (mx.x - mn.x) * 0.5 * 1.012
    lab = cyl("label", r, (mx.z - mn.z) * 0.52, 48, (c.x, c.y, c.z - 0.006), "Z", mat=M("plabel", "powder_label.png", rv=0.75))
    j = join(ms + [lab], "tin")
    fit_max([j], 0.14)
    center([j])
    export("powder", [j], 6000)


def b_flare():
    ms = import_glb("e_flare")
    std("flare", ms, 0.38, rotate=(0, 0, 90))


def b_gel():
    ms = import_glb("e_gel")
    std("gel", ms, 0.085)


def b_adrenaline():
    ms = import_glb("e_adrenaline")
    std("adrenaline", ms, 0.095)


def b_gel_mix():
    ms = import_glb("e_gel_mix")
    std("gel_mix", ms, 0.16)


def b_spray():
    ms = import_glb("e_spray")
    std("spray", ms, 0.24)


def b_pouch():
    ms = import_glb("e_pouch", keep=lambda o: o.name in ("Object_3", "Object_4", "Object_5"))
    std("pouch", ms, 0.26)


def b_radio():
    ms = import_glb("e_radio")
    std("radio", ms, 0.22, rotate=(90, 0, 0))


def b_control_key():
    ms = import_glb("e_keytag", keep=lambda o: "KeyTag" not in o.name)
    k = join(ms, "kr")
    # tag replaces the original; place below the ring
    mn, mx = bbox([k])
    tg = tag_obj("tag", "tag_control.png", 0.036, 0.058, 0.0016, ((mn.x + mx.x) / 2, mn.y - 0.022, 0.0), 0)
    std("control_key", [k, tg], 0.115)


def b_school_key():
    ring = join(import_glb("e_ring"), "ring")
    decimate(ring, 1800)
    fit_max([ring], 0.034)
    center([ring])
    ring.location = (0, 0, 0)
    parts = [ring]
    R = 0.0165
    for i, ang in enumerate([-40, 8, 52]):
        k = make_key_aligned("e_key9", 0.062 - i * 0.004)
        a = math.radians(ang)
        mn, mx = bbox([k])
        # bow end at -X; slide so bow centre sits on the ring rim, then rotate about origin
        k.location = (R + 0.004 + (mx.x - mn.x) * 0.5 - 0.01, 0, 0.0015 * (i - 1))
        sel([k]); bpy.ops.object.transform_apply(location=True)
        e = Euler((0, 0, a))
        k.matrix_world = e.to_matrix().to_4x4() @ k.matrix_world
        sel([k]); bpy.ops.object.transform_apply(location=True, rotation=True)
        parts.append(k)
    tg = tag_obj("tag", "tag_school.png", 0.03, 0.05, 0.0016, (-0.032, -0.012, 0.0), 25)
    parts.append(tg)
    std("school_key", parts, 0.12)


def b_valve_handle():
    ms = import_glb("e_valve")
    std("valve_handle", ms, 0.24)


def b_gym_key():
    k = make_key_aligned("e_key9", 0.05)
    k.location = (0.03, -0.03, 0.0)
    sel([k]); bpy.ops.object.transform_apply(location=True)
    ch = M("whistle", "chrome_a.png", "metal_r.png", None, color=(0.9, 0.9, 0.92, 1), rv=0.4, metal=0.6)
    body = cyl("w_body", 0.0125, 0.040, 28, (-0.03, 0.03, 0.0125), "X", mat=ch)
    mp = box("w_mouth", 0.034, 0.0145, 0.0085, (-0.0585, 0.03, 0.0095), ch, bevel=0.0012)
    cap = sphere("w_cap", 0.0125, (-0.010, 0.03, 0.0125), ch, 20, 12)
    ring_w = torus("w_ring", 0.0065, 0.0016, (-0.004, 0.03, 0.0125), ch, rotx=90)
    for o in (body, mp, cap, ring_w):
        box_uv(o, 0.05)
    nyl = solid("nylon", (0.8, 0.28, 0.06, 1), 0.7)
    pts = [(-0.004, 0.03, 0.0022), (0.04, 0.075, 0.0022), (0.095, 0.08, 0.0022), (0.125, 0.03, 0.0022), (0.105, -0.025, 0.0022), (0.06, -0.035, 0.0022), (0.035, -0.03, 0.0022)]
    cord = curve_tube("cord", pts, 0.0021, nyl, res=10, bevel_res=3)
    kr = torus("k_ring", 0.0095, 0.0014, (0.012, -0.03, 0.0016), chrome(), rotx=0)
    box_uv(kr, 0.05)
    std("gym_key", [k, body, mp, cap, ring_w, cord, kr], 0.17)


def b_church_key():
    k = make_key_aligned("e_church", 0.125)
    mn, mx = bbox([k])
    nyl = solid("string", (0.75, 0.7, 0.55, 1), 0.9)
    loop = torus("loop", 0.009, 0.0009, (mn.x + 0.014, 0, 0.0), nyl, rotx=0)
    tg = tag_obj("tag", "tag_church.png", 0.028, 0.044, 0.0012, (mn.x - 0.008, -0.02, -0.003), 80, grommet=False)
    std("church_key", [k, loop, tg], 0.15)


def b_rosary():
    ms = import_glb("e_rosary")
    std("rosary", ms, 0.16, tri=8000)


def b_badge_meridian():
    ct = M("card", "card_badge.png", rv=0.35)
    card = box("card", 0.0856, 0.054, 0.0009, (0, 0, 0), ct)
    planar_uv(card, 0.0856, 0.054)
    web = M("web", "webbing_a.png", rv=0.9)
    strap = box("strap", 0.014, 0.075, 0.0016, (0.0, 0.0675, 0.0012), web)
    clip = box("clip", 0.02, 0.014, 0.0035, (0.0, 0.0145 + 0.054 / 2 + 0.002, 0.002), chrome(), bevel=0.001)
    box_uv(clip, 0.05)
    slot = torus("clip_loop", 0.006, 0.0012, (0.0, 0.0145 + 0.054 / 2 + 0.012, 0.002), chrome())
    box_uv(slot, 0.05)
    std("badge_meridian", [card, strap, clip, slot], 0.15)


def b_pipeline_card():
    ct = M("card", "card_pipeline.png", rv=0.35)
    card = box("card", 0.0856, 0.054, 0.0009, (0, 0, 0), ct)
    planar_uv(card, 0.0856, 0.054)
    std("pipeline_card", [card], 0.0856)


def b_coolant_key():
    k = make_key_aligned("e_key9", 0.075)
    # red rubber bow cover
    red = solid("rubber_red", (0.55, 0.035, 0.03, 1), 0.5)
    k.data.materials.append(red)
    mn, mx = bbox([k])
    cut = mn.x + (mx.x - mn.x) * 0.42
    me = k.data
    for p in me.polygons:
        cx = (k.matrix_world @ p.center).x
        if cx < cut:
            p.material_index = len(me.materials) - 1
    std("coolant_key", [k], 0.075)


def b_lamp_battery():
    ms = import_glb("e_battery")
    std("lamp_battery", ms, 0.15)


def b_dynamite():
    ms = import_glb("e_dyn")
    std("dynamite", ms, 0.2)


# ---- fully procedural kitbashes
def b_hot_stick():
    fg = M("fiberglass", "fiberglass_a.png", "metal_r.png", None, rv=0.35)
    L = 1.8
    tube = cyl("tube", 0.0135, L, 24, (0, 0, 0), "X", mat=fg)
    box_uv(tube, 0.2)
    black = solid("grip", (0.05, 0.05, 0.05, 1), 0.85)
    grip = cyl("grip", 0.0155, 0.32, 24, (-L / 2 + 0.2, 0, 0), "X", mat=black)
    bands = []
    for i, x in enumerate([-0.05, 0.05, 0.4, 0.8]):
        b = cyl("band%d" % i, 0.0142, 0.03, 24, (x, 0, 0), "X", mat=solid("tape", (0.85, 0.1, 0.06, 1), 0.6))
        bands.append(b)
    # fitting: brass ferrule + universal hook head
    fe = cyl("ferr", 0.0175, 0.06, 24, (L / 2 + 0.02, 0, 0), "X", mat=brass())
    box_uv(fe, 0.08)
    arm = cyl("arm", 0.008, 0.07, 16, (L / 2 + 0.085, 0, 0), "X", mat=brass())
    hook = torus("hook", 0.028, 0.0075, (L / 2 + 0.112, 0.0, 0.028), brass(), rotx=90, maj=40, mnr=10)
    # keep 3/4 of the ring (cut a gap with a box boolean)
    gap = box("gap", 0.04, 0.08, 0.03, (L / 2 + 0.112, 0.0, 0.056))
    sel([hook])
    m = hook.modifiers.new("b", "BOOLEAN"); m.object = gap; m.operation = "DIFFERENCE"
    bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.data.objects.remove(gap, do_unlink=True)
    cap = sphere("endcap", 0.0155, (-L / 2 - 0.004, 0, 0), black, 16, 10)
    for o in (arm, hook):
        box_uv(o, 0.08)
    box_uv(grip, 0.2)
    std("hot_stick", [tube, grip, fe, arm, hook, cap] + bands, 1.9, tri=6000)


def b_fuse_60a():
    lab = M("fuse_tube", "fuse_label.png", rv=0.6)
    tube = cyl("tube", 0.0155, 0.095, 32, (0, 0, 0), "X", mat=lab)
    br = brass()
    parts = [tube]
    for s in (-1, 1):
        cap = cyl("cap%d" % s, 0.0165, 0.016, 32, (s * 0.0555, 0, 0), "X", mat=br)
        blade = box("blade%d" % s, 0.034, 0.016, 0.0035, (s * 0.0785, 0, 0), br, bevel=0.0008)
        # hole in blade
        h = cyl("hole", 0.0035, 0.01, 16, (s * 0.088, 0, 0), "Y")
        sel([blade]); m = blade.modifiers.new("b", "BOOLEAN"); m.object = h; m.operation = "DIFFERENCE"
        bpy.ops.object.modifier_apply(modifier=m.name)
        bpy.data.objects.remove(h, do_unlink=True)
        box_uv(cap, 0.04); box_uv(blade, 0.04)
        parts += [cap, blade]
    # tube lying: Z up already
    std("fuse_60a", parts, 0.15, tri=4000)


def b_bell_rope():
    wd = wood()
    prof = [(0.0, 0.0), (0.010, 0.0), (0.018, 0.012), (0.0235, 0.04), (0.0225, 0.075), (0.016, 0.105), (0.0095, 0.122), (0.007, 0.135), (0.0, 0.137)]
    grip = lathe("grip", prof, 28, wd)
    box_uv(grip, 0.1)
    rs = rust()
    # eye bolt at top + chain links hanging up (+Z)
    parts = [grip]
    z = 0.140 + 0.016
    for i in range(6):
        ln = torus("link%d" % i, 0.0105, 0.003, (0, 0, 0), rs, maj=24, mnr=8)
        ln.scale = (1.0, 1.6, 1.0)
        sel([ln]); bpy.ops.object.transform_apply(scale=True)
        ln.rotation_euler = (math.radians(90), 0, math.radians(90 if i % 2 else 0))
        ln.location = (0, 0, z)
        sel([ln]); bpy.ops.object.transform_apply(location=True, rotation=True)
        box_uv(ln, 0.05)
        parts.append(ln)
        z += 0.0225
    std("bell_rope", parts, 0.30, rotate=(0, 90, 0), tri=6000)


def b_hoist_lever():
    rs = rust()
    hub = cyl("hub", 0.034, 0.05, 32, (0, 0, 0.0), "Z", mat=rs)
    boss = cyl("boss", 0.022, 0.085, 24, (0, 0, 0.0), "Z", mat=rs)
    # arm: tapered bar
    bm = bmesh.new()
    L = 0.42
    pts = [(0.02, -0.016, -0.007), (L, -0.010, -0.007), (L, 0.010, -0.007), (0.02, 0.016, -0.007)]
    top = [(x, y, 0.007) for x, y, z in pts]
    vs = [bm.verts.new(p) for p in pts] + [bm.verts.new(p) for p in top]
    bm.faces.new(vs[0:4][::-1]); bm.faces.new(vs[4:8])
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((vs[i], vs[j], vs[4 + j], vs[4 + i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=0.0015, segments=2, affect="EDGES")
    arm = new_obj("arm", bm)
    arm.data.materials.append(rs)
    knob = sphere("knob", 0.03, (L + 0.025, 0, 0), rs, 28, 18)
    neck = cyl("neck", 0.011, 0.04, 16, (L + 0.003, 0, 0), "X", mat=rs)
    pawl = box("pawl", 0.05, 0.012, 0.02, (0.01, -0.045, -0.02), rs, bevel=0.002)
    pin = cyl("pin", 0.009, 0.1, 16, (0, 0, 0), "Z", mat=rs)
    for o in (hub, boss, arm, knob, neck, pawl, pin):
        box_uv(o, 0.16)
        shade_smooth(o) if o in (knob, hub, boss, pin, neck) else None
    std("hoist_lever", [hub, boss, arm, knob, neck, pawl, pin], 0.46, tri=6000)


def b_tom_tag():
    br = brass()
    disc = cyl("disc", 0.0205, 0.0024, 48, (0, 0, 0), "Z", mat=br)
    hole = cyl("hole", 0.0032, 0.01, 20, (0, 0.0145, 0), "Z")
    sel([disc]); m = disc.modifiers.new("b", "BOOLEAN"); m.object = hole; m.operation = "DIFFERENCE"
    bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.data.objects.remove(hole, do_unlink=True)
    rim = torus("rim", 0.0205, 0.0013, (0, 0, 0), br, rotx=0, maj=48, mnr=8)
    parts = [disc, rim]

    def text(body, size, y, ext=0.0004):
        cu = bpy.data.curves.new("t", "FONT")
        cu.body = body
        cu.size = size
        cu.extrude = ext
        cu.align_x = "CENTER"
        cu.align_y = "CENTER"
        o = bpy.data.objects.new("t", cu)
        bpy.context.scene.collection.objects.link(o)
        o.location = (0, y, 0.0012)
        sel([o]); bpy.ops.object.convert(target="MESH")
        o = bpy.context.view_layer.objects.active
        o.data.materials.append(br)
        return o
    parts.append(text("114", 0.0105, -0.0005))
    parts.append(text("T. KADE", 0.0035, -0.0125))
    parts.append(text("NORTHLINE", 0.0028, 0.0095))
    ring = torus("sring", 0.0065, 0.0009, (0, 0.0225, 0), chrome(), rotx=90)
    parts.append(ring)
    for o in parts:
        box_uv(o, 0.04)
    std("tom_tag", parts, 0.06, tri=5000)


ALL = {
    "ammo_9mm": b_ammo_9mm, "ammo_shell": b_ammo_shell, "ammo_44": b_ammo_44, "ammo_grenade": b_ammo_grenade,
    "powder": b_powder, "flare": b_flare, "gel": b_gel, "adrenaline": b_adrenaline, "gel_mix": b_gel_mix, "spray": b_spray,
    "pouch": b_pouch, "radio": b_radio, "hot_stick": b_hot_stick, "control_key": b_control_key, "fuse_60a": b_fuse_60a,
    "school_key": b_school_key, "valve_handle": b_valve_handle, "gym_key": b_gym_key, "church_key": b_church_key,
    "bell_rope": b_bell_rope, "rosary": b_rosary, "badge_meridian": b_badge_meridian, "coolant_key": b_coolant_key,
    "pipeline_card": b_pipeline_card, "lamp_battery": b_lamp_battery, "hoist_lever": b_hoist_lever, "dynamite": b_dynamite,
    "tom_tag": b_tom_tag,
}

if __name__ == "__main__":
    names = sys.argv[sys.argv.index("--") + 1:]
    if names == ["all"]:
        names = list(ALL)
    for n in names:
        try:
            clear()
            ALL[n]()
        except Exception as e:
            import traceback
            print("FAIL", n, repr(e))
            traceback.print_exc()
