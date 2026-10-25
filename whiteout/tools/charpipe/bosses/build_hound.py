"""RIME HOUND: frozen sled dog / wolf, modelled from scratch (Skin-modifier tubes + subsurf + displacement), rigged with
a custom distance-weighted armature.  -> assets/enemies/hound.glb   (~9k tris)
Armature 'HoundRig' bones (driven by actors/models/hound_model.gd): pelvis, spine, neck, neck2, head, jaw,
tail1..3, fl_sh/fl_kn/fl_pw, fr_*, hl_*, hr_* ;  rest pose = standing, facing glTF +Z (Blender -Y).
All original work (CC0): no third-party mesh is used."""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bosslib import *
from common import *

reset()
M = std_mats()
rng = random.Random(404)


def g(x, y, z):
    """model-space (x right, y up, z forward) -> Blender (x, -z, y); squashed/shortened to husky proportions"""
    y = y * 0.87
    if z > 0.45:
        z = 0.45 + (z - 0.45) * 0.78
    return Vector((x, -z, y))


# ----------------------------------------------------------------------------- materials
fur_tex = os.path.join(CACHE, "tex", "hound_fur.jpg")
if not os.path.exists(fur_tex):
    n1 = texgen.fbm(512, 3, 5, 6)
    n2 = texgen.fbm(512, 8, 3, 64)
    # streaky fur: stretch noise along one axis
    from PIL import Image
    st = np.asarray(Image.fromarray((n2 * 255).astype(np.uint8)).resize((512, 64), Image.BICUBIC).resize((512, 512), Image.BICUBIC), np.float32) / 255
    a = 0.35 + 0.45 * n1[..., None] + 0.2 * st[..., None]
    base = np.concatenate([a * 0.95, a, a * 1.05], axis=2)
    texgen.save(np.clip(base, 0, 1), fur_tex)
fur = make_mat("fur", tex=fur_tex, rough=0.9, spec=0.25)
fur_cards = make_mat("fur_tuft", color=(0.7, 0.72, 0.78, 1), rough=0.95, spec=0.2)
raw = make_mat("blood_flesh", color=(0.4, 0.04, 0.05, 1), rough=0.1, spec=0.9, coat=1.0, coat_rough=0.05)
bone_m = M["bone"]
gum = make_mat("blood_gum", color=(0.18, 0.02, 0.03, 1), rough=0.2, spec=0.7, coat=0.8)
eye_m = make_mat("glow_eye", color=(0.3, 0.7, 0.8, 1), rough=0.3, emission=(0.5, 0.95, 1.0, 1), emit=6.0)
nose_m = make_mat("nose", color=(0.03, 0.02, 0.03, 1), rough=0.3, spec=0.8)

# ----------------------------------------------------------------------------- skeleton graph (model space)
# (name, (x,y,z), (rx, ry))
SPINE = [
    ("rump", (0, 0.60, -0.50), (0.075, 0.08)),
    ("pelvis", (0, 0.63, -0.38), (0.095, 0.10)),
    ("loin", (0, 0.62, -0.12), (0.085, 0.095)),
    ("ribs", (0, 0.63, 0.14), (0.105, 0.125)),
    ("chest", (0, 0.65, 0.34), (0.105, 0.135)),
    ("neckb", (0, 0.70, 0.50), (0.08, 0.10)),
    ("neckm", (0, 0.77, 0.64), (0.065, 0.078)),
    ("skull", (0, 0.83, 0.77), (0.062, 0.07)),
    ("brow", (0, 0.83, 0.86), (0.055, 0.058)),
    ("muzzle1", (0, 0.805, 0.95), (0.04, 0.042)),
    ("muzzle2", (0, 0.79, 1.04), (0.034, 0.036)),
    ("nose", (0, 0.785, 1.115), (0.026, 0.028)),
]


RS_DEF = 1.12
RS = {"skull": 1.4, "brow": 1.4, "muzzle1": 1.35, "muzzle2": 1.35, "nose": 1.3, "neckb": 1.3, "neckm": 1.3, "ribs": 1.15, "chest": 1.25, "pelvis": 1.15,
      "j0": 1.3, "j1": 1.3, "j2": 1.3, "j3": 1.3}


def build_skin(name, chains, subs=2, extra_edges=()):
    """chains: list of lists of (name,pos,(rx,ry)); vertices shared by name.  Returns object (skin+subsurf applied)."""
    bm = bmesh.new()
    skin = bm.verts.layers.skin.verify()
    vmap = {}
    for ch in chains:
        prev = None
        for (nm, p, r) in ch:
            if nm not in vmap:
                v = bm.verts.new(g(*p))
                v[skin].radius = (r[0] * RS.get(nm, RS_DEF), r[1] * RS.get(nm, RS_DEF))
                vmap[nm] = v
            v = vmap[nm]
            if prev is not None and prev is not v:
                try:
                    bm.edges.new((prev, v))
                except ValueError:
                    pass
            prev = v
    bm.verts.ensure_lookup_table()
    # root: first spine vertex
    vmap[chains[0][0][0]][skin].use_root = True
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    md = ob.modifiers.new("skin", 'SKIN')
    md.use_smooth_shade = True
    md.branch_smoothing = 0.8
    sub = ob.modifiers.new("sub", 'SUBSURF')
    sub.levels = subs
    sub.render_levels = subs
    select_only(ob)
    bpy.ops.object.modifier_apply(modifier="skin")
    bpy.ops.object.modifier_apply(modifier="sub")
    return ob


def legs_chain(prefix, side, sh, el, wr, pw, radii):
    return [(f"{prefix}{side}_{n}", (side * p[0], p[1], p[2]), r) for n, p, r in zip(("sh", "el", "wr", "pw"), (sh, el, wr, pw), radii)]


# front legs (anchor to the chest vertex), hind legs (anchor to the pelvis vertex)
body_chains = [SPINE]
for sd in (-1, 1):
    # front: shoulder blade -> elbow -> wrist -> paw
    ch = [("chest", None, None)]
    fl = [(f"f{sd}_sh", (sd * 0.115, 0.56, 0.36), (0.065, 0.075)),
          (f"f{sd}_el", (sd * 0.125, 0.34, 0.33), (0.045, 0.05)),
          (f"f{sd}_wr", (sd * 0.115, 0.14, 0.39), (0.032, 0.036)),
          (f"f{sd}_pw", (sd * 0.115, 0.035, 0.45), (0.042, 0.032))]
    body_chains.append([SPINE[4]] + fl)
    hl = [(f"h{sd}_hp", (sd * 0.11, 0.54, -0.40), (0.085, 0.095)),
          (f"h{sd}_kn", (sd * 0.13, 0.38, -0.27), (0.052, 0.062)),
          (f"h{sd}_hk", (sd * 0.115, 0.21, -0.50), (0.034, 0.04)),
          (f"h{sd}_pw", (sd * 0.115, 0.035, -0.43), (0.042, 0.032))]
    body_chains.append([SPINE[1]] + hl)
# tail
TAIL = [SPINE[0], ("t1", (0, 0.68, -0.66), (0.034, 0.04)), ("t2", (0, 0.78, -0.84), (0.05, 0.055)), ("t3", (0, 0.76, -1.0), (0.058, 0.06)),
        ("t4", (0, 0.66, -1.12), (0.03, 0.03))]
body_chains.append(TAIL)
body = build_skin("hound_body", [c for c in body_chains], subs=2)
print("body tris", tri_count(body))

# lower jaw (own object, own bone)
JAW = [("j0", (0, 0.775, 0.80), (0.036, 0.022)), ("j1", (0, 0.752, 0.90), (0.03, 0.02)), ("j2", (0, 0.745, 1.0), (0.026, 0.018)), ("j3", (0, 0.745, 1.075), (0.018, 0.014))]
jaw = build_skin("hound_jaw", [JAW], subs=2)

# ----------------------------------------------------------------------------- skin the meshes to bones
BONES = {
    # name: (head, tail, parent)
    "pelvis": ((0, 0.62, -0.42), (0, 0.63, -0.15), None),
    "spine": ((0, 0.63, -0.15), (0, 0.66, 0.42), "pelvis"),
    "neck": ((0, 0.68, 0.46), (0, 0.78, 0.66), "spine"),
    "neck2": ((0, 0.78, 0.66), (0, 0.83, 0.78), "neck"),
    "head": ((0, 0.83, 0.78), (0, 0.8, 1.1), "neck2"),
    "jaw": ((0, 0.775, 0.80), (0, 0.745, 1.075), "head"),
    "tail1": ((0, 0.62, -0.50), (0, 0.72, -0.76), "pelvis"),
    "tail2": ((0, 0.72, -0.76), (0, 0.78, -0.95), "tail1"),
    "tail3": ((0, 0.78, -0.95), (0, 0.66, -1.14), "tail2"),
}
for pre, par, anchors in (("f", "spine", ((0.115, 0.56, 0.36), (0.125, 0.34, 0.33), (0.115, 0.14, 0.39), (0.115, 0.035, 0.45))),
                          ("h", "pelvis", ((0.11, 0.54, -0.40), (0.13, 0.38, -0.27), (0.115, 0.21, -0.50), (0.115, 0.035, -0.43)))):
    for sd, sdn in ((-1, "l"), (1, "r")):
        names = (f"{pre}{sdn}_sh", f"{pre}{sdn}_kn", f"{pre}{sdn}_pw")
        pts = [(sd * a[0], a[1], a[2]) for a in anchors]
        BONES[names[0]] = (pts[0], pts[1], par)
        BONES[names[1]] = (pts[1], pts[2], names[0])
        BONES[names[2]] = (pts[2], pts[3], names[1])

arm_d = bpy.data.armatures.new("HoundRig")
rig = bpy.data.objects.new("HoundRig", arm_d)
bpy.context.scene.collection.objects.link(rig)
select_only(rig)
bpy.ops.object.mode_set(mode='EDIT')
order = []


def addb(n):
    if n in order:
        return
    par = BONES[n][2]
    if par:
        addb(par)
    order.append(n)


for n in BONES:
    addb(n)
for n in order:
    h, t, par = BONES[n]
    eb = arm_d.edit_bones.new(n)
    eb.head = g(*h)
    eb.tail = g(*t)
    eb.roll = 0
    if par:
        eb.parent = arm_d.edit_bones[par]
        # connected chains keep joints tight
bpy.ops.object.mode_set(mode='OBJECT')

SEG = {n: (g(*BONES[n][0]), g(*BONES[n][1])) for n in BONES}


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (p - (a + ab * t)).length


def skin_weights(ob, allowed=None, sigma=0.07, power=2.0, maxinf=3):
    me = ob.data
    ob.vertex_groups.clear()
    names = [n for n in BONES if (allowed is None or n in allowed)]
    vgs = {n: ob.vertex_groups.new(name=n) for n in BONES}
    M_ = ob.matrix_world
    for v in me.vertices:
        p = M_ @ v.co
        ds = sorted(((seg_dist(p, *SEG[n]), n) for n in names))
        # nearest bones only
        d0 = ds[0][0]
        ws = []
        for d, n in ds[:maxinf]:
            w = math.exp(-((d - d0) / sigma) ** power)
            ws.append((n, w))
        tot = sum(w for n, w in ws)
        for n, w in ws:
            if w / tot > 0.02:
                vgs[n].add([v.index], w / tot, 'REPLACE')
    md = ob.modifiers.new("Armature", 'ARMATURE')
    md.object = rig
    ob.parent = rig


# ----------------------------------------------------------------------------- body surface: displacement, wounds, colours
displace_noise(body, 0.011, 30.0, seed=1.0, octaves=3)
# gaunt: sink the flanks a little (hollow belly, visible hip bones) - displace along normal using a belly mask
for v in body.data.vertices:
    p = v.co  # blender coords: x, -z_model, y_model
    zm, ym = -p.y, p.z
    if ym < 0.58 and -0.35 < zm < 0.28:
        v.co = p - v.normal * 0.012 * min(1.0, (0.58 - ym) / 0.05)
body.data.update()

# wounds: cut open the left flank (ribs show), raw patches elsewhere
def in_ell(p, c, r):
    return ((p.x - c.x) / r[0]) ** 2 + ((p.y - c.y) / r[1]) ** 2 + ((p.z - c.z) / r[2]) ** 2 < 1.0


bm = bmesh.new()
bm.from_mesh(body.data)
bm.faces.ensure_lookup_table()
flank_c, flank_r = g(0.10, 0.60, 0.16), (0.085, 0.17, 0.085)       # (x, z, y) radii in blender order
cut = [f for f in bm.faces if in_ell(f.calc_center_median(), flank_c, (0.09, 0.19, 0.09)) and f.calc_center_median().x > 0.03]
cut += [f for f in bm.faces if in_ell(f.calc_center_median(), g(-0.11, 0.55, -0.34), (0.06, 0.09, 0.06)) and f.calc_center_median().x < -0.03]
bmesh.ops.delete(bm, geom=cut, context='FACES')
for f in bm.faces:
    c = f.calc_center_median()
    if in_ell(c, g(-0.10, 0.56, -0.36), (0.07, 0.10, 0.07)) or in_ell(c, g(0.07, 0.74, 0.55), (0.05, 0.07, 0.05)) or in_ell(c, g(-0.045, 0.78, 0.9), (0.03, 0.06, 0.035)):
        pass
bm.to_mesh(body.data)
bm.free()
body.data.materials.append(fur)
body.data.materials.append(raw)
decimate(body, 0.62)


def fur_color(co, n, i):
    ym = co.z
    zm = -co.y
    # darker saddle on the back, pale belly / legs / mask, frost on upward faces and tips
    saddle = smoothstep(0.58, 0.68, ym) * smoothstep(-0.55, -0.35, zm) * (1 - smoothstep(0.55, 0.75, zm))
    nz = 0.5 + 0.5 * noise.noise(co * 9.0)
    nb = 0.5 + 0.5 * noise.noise(co * 3.1 + Vector((5, 0, 0)))
    base = Vector((0.80, 0.8, 0.84)).lerp(Vector((0.34, 0.34, 0.38)), saddle * (0.5 + 0.5 * nb))
    base *= 0.82 + 0.3 * nz
    # blood-matted fur around the wounds and muzzle
    bl = smoothstep(0.7, 0.2, (co - g(0.10, 0.60, 0.16)).length) * 0.8 + smoothstep(0.35, 0.05, (co - g(0, 0.76, 1.0)).length) * 0.5
    base = base.lerp(Vector((0.35, 0.05, 0.06)), min(1.0, bl) * (0.5 + 0.5 * nz))
    up = max(0.0, n.z)
    fr = smoothstep(0.35, 0.9, up * (0.55 + 0.7 * nb)) * 0.8
    base = base.lerp(Vector((0.9, 0.96, 1.0)), fr)
    return (base.x, base.y, base.z, 1.0)


ensure_col(body)
set_vertex_color(body, fur_color)
uv_box(body, 1.6)
body.name = "hound_body"

# jaw / skull colours
jaw.data.materials.append(fur)
ensure_col(jaw)
set_vertex_color(jaw, fur_color)
uv_box(jaw, 1.6)

# ----------------------------------------------------------------------------- extra parts
parts_by_bone = []   # (object, allowed bones)
# ribs seen through the flank wound
mbr = MeshBuilder("ribs")
for k in range(7):
    zz = 0.30 - k * 0.055
    pts = []
    for j in range(8):
        a = j / 7.0
        x = 0.01 + 0.115 * math.sin(a * 1.55) * (1.0 - 0.08 * k / 6)
        y = 0.69 - 0.19 * (1 - math.cos(a * 1.4))
        pts.append(g(x, y, zz - 0.012 * a))
    add_tube(mbr, pts, [0.011 - 0.003 * (j / 7.0) for j in range(8)], sides=6, mat_index=0)
# spine knobs
for k in range(8):
    zz = 0.42 - k * 0.1
    add_crystal(mbr, g(0, 0.70 + (0.02 if k < 4 else 0.0), zz), Vector((0, -0.2, 1)), 0.05, 0.012, sides=5, rng=rng, mat_index=0)
ribs = mbr.build([bone_m])
# raw lining inside the flank wound
lb = MeshBuilder("lining")
add_blob(lb, g(0.045, 0.60, 0.16), (0.05, 0.19, 0.13), seg=10, rings=6, noise_amp=0.2)
add_blob(lb, g(-0.07, 0.55, -0.34), (0.03, 0.08, 0.06), seg=8, rings=5, noise_amp=0.2)
lining = lb.build([raw])
for ob in (ribs, lining):
    ensure_col(ob)
    shade_smooth(ob)
parts_by_bone += [(ribs, ["spine", "pelvis"]), (lining, ["spine", "pelvis"])]

# head details: ears, eyes (glow), nose, teeth, mouth lining, ice growth
hb = MeshBuilder("head_detail")
for sd in (-1, 1):
    # ear: flat tapering pyramid
    base = g(sd * 0.045, 0.875, 0.775)
    add_crystal(hb, base, g(sd * 0.28, 1.0, -0.1), 0.15, 0.04, sides=3, tip=0.3, jitter=0.05, rng=rng, mat_index=0, taper=0.55)
    # glowing eyes sunk in the sockets
    add_blob(hb, g(sd * 0.072, 0.845, 0.86), (0.017, 0.015, 0.017), seg=8, rings=6, mat_index=2)
add_blob(hb, g(0, 0.789, 1.133), (0.026, 0.02, 0.022), seg=8, rings=6, mat_index=3)    # nose leather
head_d = hb.build([fur, fur_cards, eye_m, nose_m])
ensure_col(head_d)
parts_by_bone.append((head_d, ["head", "neck2"]))

tb = MeshBuilder("teeth_up")
for sd in (-1, 1):
    for k in range(6):
        zz = 0.93 + k * 0.03
        add_crystal(tb, g(sd * 0.03, 0.775 - 0.002 * k, zz), g(sd * 0.0, -1, 0.15), 0.028 if k % 2 == 0 else 0.018, 0.0075, sides=4, tip=0.5, rng=rng, mat_index=0)
for sd in (-1, 1):   # fangs
    add_crystal(tb, g(sd * 0.032, 0.775, 1.03), g(0, -1, 0.1), 0.05, 0.01, sides=5, tip=0.6, rng=rng, mat_index=0)
teeth_up = tb.build([bone_m])
ensure_col(teeth_up)
parts_by_bone.append((teeth_up, ["head"]))

jb = MeshBuilder("teeth_lo")
for sd in (-1, 1):
    for k in range(6):
        zz = 0.88 + k * 0.032
        add_crystal(jb, g(sd * 0.026, 0.756, zz), g(0, 1, 0.1), 0.026 if k % 2 else 0.018, 0.007, sides=4, tip=0.5, rng=rng, mat_index=0)
    add_crystal(jb, g(sd * 0.025, 0.756, 1.045), g(0, 1, 0.2), 0.045, 0.009, sides=5, tip=0.6, rng=rng, mat_index=0)
# tongue / mouth lining
add_blob(jb, g(0, 0.752, 0.93), (0.022, 0.07, 0.01), seg=8, rings=5, mat_index=1)
teeth_lo = jb.build([bone_m, gum])
ensure_col(teeth_lo)
parts_by_bone.append((teeth_lo, ["jaw"]))
# dark mouth cavity in the muzzle
cb = MeshBuilder("cavity")
add_blob(cb, g(0, 0.78, 0.95), (0.026, 0.1, 0.014), seg=8, rings=5)
cavity = cb.build([gum])
ensure_col(cavity)
parts_by_bone.append((cavity, ["head"]))

# fur tufts: ruffled coat (flat tapered spikes sweeping back / down)
tf = MeshBuilder("tufts")


def tuft_spots():
    spots = []
    # (position, direction) samples on the body: neck ruff, withers, back, tail, leg feathers, ears fringe
    for k in range(70):   # back ridge + shoulders
        zz = rng.uniform(-0.45, 0.55)
        yy = 0.70 + 0.03 * math.sin(zz * 3) + rng.uniform(-0.01, 0.02)
        spots.append((g(rng.uniform(-0.07, 0.07), yy, zz), g(rng.uniform(-0.2, 0.2), 0.35, -0.9)))
    for k in range(60):   # neck ruff / chest
        a = rng.uniform(0, math.tau)
        zz = rng.uniform(0.42, 0.7)
        yy = 0.72 + 0.14 * (zz - 0.42) / 0.28
        spots.append((g(math.cos(a) * 0.075, yy + math.sin(a) * 0.08, zz), g(math.cos(a) * 0.6, math.sin(a) * 0.6 - 0.2, -0.8)))
    for k in range(40):   # flanks
        sd = rng.choice((-1, 1))
        spots.append((g(sd * 0.1, rng.uniform(0.5, 0.64), rng.uniform(-0.4, 0.3)), g(sd * 0.3, -0.3, -0.9)))
    for k in range(40):   # tail
        zz = rng.uniform(-1.1, -0.6)
        yy = 0.68 + 0.1 * (-zz - 0.6) / 0.5
        a = rng.uniform(0, math.tau)
        spots.append((g(math.cos(a) * 0.05, yy + math.sin(a) * 0.05, zz), g(math.cos(a) * 0.4, math.sin(a) * 0.4 - 0.2, -0.9)))
    for k in range(40):   # leg feathers
        sd = rng.choice((-1, 1))
        zz = rng.choice((0.38, -0.34))
        spots.append((g(sd * 0.12, rng.uniform(0.15, 0.5), zz + rng.uniform(-0.06, 0.06)), g(0, -0.6, -0.7)))
    return spots


for pos, d in tuft_spots():
    L = rng.uniform(0.05, 0.1)
    add_crystal(tf, pos - d.normalized() * 0.01, d, L, rng.uniform(0.007, 0.014), sides=3, tip=0.7, jitter=0.2, rng=rng, mat_index=0, taper=0.8,
                color=(rng.uniform(0.8, 1.0),) * 3 + (1,))
tufts = tf.build([fur_cards])
ensure_col(tufts)
set_vertex_color(tufts, lambda co, n, i: (lambda c: (c[0], c[1], c[2], 1.0))(fur_color(co, Vector((0, 0, 0.5)), i)))
parts_by_bone.append((tufts, None))

# crystal spines along the back + hanging icicles + frost crust patches
ib = MeshBuilder("ice")
for k in range(11):
    zz = 0.45 - k * 0.092
    L = rng.uniform(0.12, 0.28) * (1.4 if k % 3 == 0 else 1.0)
    add_crystal(ib, g(rng.uniform(-0.02, 0.02), 0.725 + 0.03 * math.sin(zz * 3), zz), g(rng.uniform(-0.2, 0.2), 1.0, -0.45 - 0.2 * rng.random()), L, rng.uniform(0.014, 0.026), rng=rng, mat_index=rng.choice([0, 1, 0]))
for k in range(5):   # crystals growing from the shoulder / hip
    sd = rng.choice((-1, 1))
    add_crystal(ib, g(sd * 0.09, 0.66, rng.choice((0.36, -0.36))), g(sd * 0.6, 0.9, -0.2), rng.uniform(0.1, 0.2), 0.02, rng=rng, mat_index=0)
for sd in (-1, 1):   # crystals from the eye sockets and muzzle
    add_crystal(ib, g(sd * 0.05, 0.86, 0.86), g(sd * 0.5, 0.8, 0.6), 0.1, 0.012, rng=rng, mat_index=2)
for k in range(5):
    add_crystal(ib, g(rng.uniform(-0.025, 0.025), 0.765, 1.07 + rng.uniform(-0.04, 0.02)), g(rng.uniform(-0.3, 0.3), -1, 0.1), rng.uniform(0.04, 0.11), 0.008, sides=5, tip=0.55, rng=rng, mat_index=3)
for k in range(8):    # frozen drool and blood icicles from the jaw / belly
    add_crystal(ib, g(rng.uniform(-0.03, 0.03), 0.74, rng.uniform(0.88, 1.05)), g(0, -1, 0.05), rng.uniform(0.05, 0.14), 0.007, sides=5, tip=0.6, rng=rng, mat_index=3)
for k in range(6):
    add_crystal(ib, g(rng.uniform(-0.08, 0.08), 0.5, rng.uniform(-0.3, 0.3)), g(0, -1, 0), rng.uniform(0.05, 0.12), 0.01, sides=5, tip=0.6, rng=rng, mat_index=1)
icegeo = ib.build([M["ice"], M["ice_deep"], M["ice_glow"], M["ice_blood"]])
ensure_col(icegeo)
parts_by_bone.append((icegeo, None))

# rest pose: mouth already agape (jaw swings about the hinge by ~0.3 rad)
hinge = g(0, 0.775, 0.80)
Rj = Matrix.Translation(hinge) @ Matrix.Rotation(0.30, 4, 'X') @ Matrix.Translation(-hinge)
for ob in (jaw, teeth_lo):
    ob.data.transform(Rj)

# ----------------------------------------------------------------------------- weights + export
skin_weights(body, allowed=[n for n in BONES if n not in ("jaw",)], sigma=0.05)
skin_weights(jaw, allowed=["jaw"], sigma=0.05)
for ob, allowed in parts_by_bone:
    skin_weights(ob, allowed=allowed, sigma=0.05)
for ob in [body, jaw] + [o for o, a in parts_by_bone]:
    shade_smooth(ob)
tr = total_tris([o for o in bpy.data.objects if o.type == 'MESH'])
print("hound tris", tr)
export(os.path.join(OUT_DIR, "hound.glb"))
