"""THE CHOIR: a ~5 m pillar of 12 fused MakeHuman congregants.  -> assets/enemies/choir.glb
Nodes: Head0..Head4 (weak points, throat_glow material), ArmL / ArmR (sweep pivots at the shoulders, geometry hangs
along -Y in glTF space), Body (everything else).  Front of the creature = glTF +Z (Blender -Y)."""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bosslib import *
from common import *

reset()
rng = random.Random(1234)
M = std_mats()
flesh = flesh_mat("flesh_mortar", 5)

# ------------------------------------------------------------------ the congregation
# (char, skin seed, cloth style, yaw (deg from +X; -90 = faces glTF +Z/front), height, weak head index or None, lean)
FRONT = -90
SC = 1.3
TONES = [(1.0, 1.0, 1.0), (1.1, 0.95, 0.85), (0.8, 0.8, 0.85), (0.9, 0.78, 0.7)]
CONG = [
    ("rimebound_civ_f", 11, {"flat": (0.12, 0.13, 0.22)}, FRONT + 35, 1.0, None, 16, "reach_up"),             # navy coat
    ("rimebound_miner", 12, {}, 150, 1.35, None, 14, "embrace"),                                            # a miner
    ("rimebound_civ_m", 13, {"flat": (0.16, 0.16, 0.17)}, FRONT - 20, 1.65, 0, 18, "praise"),              # charcoal suit
    ("rimebound_nurse", 14, {"flat": (0.32, 0.38, 0.6)}, 20, 1.95, None, 14, "reach_up"),                   # Sunday dress
    ("ruth", 15, {"flat": (0.45, 0.42, 0.5)}, FRONT + 15, 2.25, 1, 18, "clasp"),                             # old woman, cardigan
    ("rimebound_civ_m", 16, {"flat": (0.24, 0.16, 0.1)}, 200, 2.55, None, 14, "embrace"),                    # brown coat
    ("elias", 17, {"flat": (0.1, 0.12, 0.15)}, FRONT - 30, 2.8, 2, 20, "praise"),                           # old man in an overcoat
    ("rimebound_civ_f", 18, {"flat": (0.42, 0.05, 0.07)}, 60, 3.1, None, 14, "reach_up"),                   # choir robe (oxblood)
    ("june", 19, {"flat": (0.55, 0.52, 0.48)}, FRONT + 25, 3.35, 3, 20, "clasp"),                           # cream coat
    ("rimebound_nurse", 20, {"flat": (0.62, 0.62, 0.68)}, 170, 3.6, None, 14, "embrace"),                   # white robe
    ("ruth", 21, {"flat": (0.1, 0.1, 0.12)}, FRONT - 5, 3.9, 4, 22, "praise"),                               # widow in black
    ("rimebound_civ_m", 22, {"flat": (0.45, 0.06, 0.08)}, -30, 4.15, None, 16, "reach_up"),                  # choir robe
]

POSES = {
    # (bone, axis, deg) in armature space: X right(+ = character's left), Y back, Z up.  Left arm: abduct = -Y-rot.
    "reach_up": [("upperarm_l", "Y", -150), ("upperarm_r", "Y", 150), ("lowerarm_l", "Y", -15), ("lowerarm_r", "Y", 15),
                 ("upperarm_l", "X", -25), ("upperarm_r", "X", -25)],
    "embrace": [("upperarm_l", "X", -80), ("upperarm_r", "X", -80), ("upperarm_l", "Y", 40), ("upperarm_r", "Y", -40),
                ("lowerarm_l", "X", -40), ("lowerarm_r", "X", -40)],
    "praise": [("upperarm_l", "Y", -125), ("upperarm_r", "Y", 125), ("lowerarm_l", "X", -55), ("lowerarm_r", "X", -55)],
    "clasp": [("upperarm_l", "X", -55), ("upperarm_r", "X", -55), ("upperarm_l", "Y", 30), ("upperarm_r", "Y", -30),
              ("lowerarm_l", "X", -80), ("lowerarm_r", "X", -80)],
}

people_objs = []
people_centres = []
tears = []
heads = {}
mouth_pts = []     # (position, outward normal)
head_pts = []
rng2 = random.Random(99)

for idx, (char, seed, cst, yaw, z, weak, lean, pose) in enumerate(CONG):
    tag = f"p{idx}"
    st = {"variant": idx, "frost": 0.55, "dirt": 0.5, "blood": 0.3}
    st.update(cst)
    p = Person(char, tag, seed=seed, cloth_style=st, skin_style={"frost": 0.5, "blood": 0.35, "livid": 0.4 + 0.1 * (idx % 4), "tone": TONES[idx % 4]})
    is_weak = weak is not None
    p.head_morph(stretch=0.55 if is_weak else 0.32, jaw=0.95 if is_weak else 0.75, mouth_cut=0.013 if is_weak else 0.011)
    p.pose([("spine_03", "X", 8), ("neck_01", "X", -3), ("head", "X", -6)] + POSES[pose])
    # throat: dark (or glowing) closed ellipsoid just behind the open mouth, skinned to the head bone
    tmat = M["throat_glow"] if is_weak else M["mouth_dark"]
    p.add_eyes(M["eye_glow"] if is_weak else M["eye_dead"])
    tb = MeshBuilder("throat")
    add_blob(tb, p.mouth + Vector((0, 0.03, -0.018)), (0.034, 0.045, 0.04), seg=10, rings=6)
    to = tb.build([tmat])
    p.add_part(to, "throat", "head")
    p.mark("m_lower", ["thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r", "ball_l", "ball_r"])
    p.mark("m_head", ["head"])
    hd_local = Vector((0, p.eye_c.y + 0.06, p.eye_c.z - 0.06))
    mouth_local = Vector(p.mouth)
    rad = 0.62 - 0.12 * (z / 4.0)
    a = math.radians(yaw)
    pos = Vector((math.cos(a) * rad, math.sin(a) * rad, z))
    Mx = person_matrix(pos, yaw, lean * 0.6, (0, -0.02, 1.2), SC)
    fn = vcol_grime(r0=0.2, r1=0.8, dark=0.7, seed=idx)
    body_roles = ["body", "hair", "boots", "jeans", "shirt", "top", "overalls", "cardigan", "skirt", "uniform", "jacket", "parka", "hoodie",
                  "trousers", "gloves", "hardhat", "lamp", "coat"]
    if is_weak:
        hres = finalize_person(p, Mx, dec={"body": 0.45, "hair": 0.45}, vcol_fn=fn, select="m_head", thr=0.3, roles=["body", "hair", "throat", "throat_eyes"],
                               name=f"H{weak}", free=False)
    bres = finalize_person(p, Mx, dec={"body": 0.16 if not is_weak else 0.2, "hair": 0.3, "default": 0.2}, vcol_fn=fn, select="m_lower", thr=0.5,
                           invert=True, name=tag, free=True)
    bres.pop("throat", None) if False else None
    # remove the head from the body objects of weak persons (the Head node carries it) and drop throats
    for role, ob in list(bres.items()):
        if is_weak and role.startswith("throat"):
            delete(ob); del bres[role]; continue
        if is_weak and role in ("body", "hair"):
            bm = bmesh.new(); bm.from_mesh(ob.data); bm.verts.ensure_lookup_table()
            lay = bm.verts.layers.float.get("m_head")
            if lay is not None:
                bmesh.ops.delete(bm, geom=[v for v in bm.verts if v[lay] >= 0.7], context='VERTS')
            bm.to_mesh(ob.data); bm.free()
    people_objs.extend(bres.values())
    for sx in (-1, 1):
        ep = Mx @ Vector((sx * p.eye_dx, p.eye_c.y - 0.005, p.eye_c.z - 0.012))
        tears.append(ep)
    people_centres.append(Mx @ Vector((0, -0.02, 1.2)))
    hc = Mx @ hd_local
    mc = Mx @ mouth_local
    out_dir = Vector((math.cos(a), math.sin(a), 0.35)).normalized()
    mouth_pts.append((mc, out_dir))
    head_pts.append((hc, out_dir))
    if is_weak:
        heads[weak] = (hres, hc, mc)

print("persons built; tris", total_tris())

# ------------------------------------------------------------------ Head0..4 objects
head_objs = []
for wi in sorted(heads):
    hres, hc, mc = heads[wi]
    ho = join(list(hres.values()), f"Head{wi}")
    origin_to(ho, hc)
    head_objs.append(ho)

# ------------------------------------------------------------------ the sweep arms (stretched fused arm bundles)
def build_arm_bundle(side, name):
    """four fused, grotesquely stretched arms hanging along -Z from the shoulder pivot; side +1 = left-arm bones (+X)."""
    parts = []
    sfx = "_l" if side > 0 else "_r"
    chars = ["ruth", "rimebound_miner", "rimebound_civ_m", "elias"] if side > 0 else ["rimebound_nurse", "june", "rimebound_civ_f", "rimebound_civ_m"]
    flats = [(0.45, 0.42, 0.5), (0.2, 0.22, 0.3), (0.16, 0.16, 0.17), (0.1, 0.12, 0.15)] if side > 0 else [(0.62, 0.62, 0.68), (0.55, 0.52, 0.48), (0.42, 0.05, 0.07), (0.45, 0.06, 0.08)]
    piv = Vector((-0.5 * side, 0.1, 2.9))
    for k, ch in enumerate(chars):
        st = {"variant": 40 + k + (0 if side > 0 else 5), "frost": 0.6, "dirt": 0.5, "blood": 0.4, "flat": flats[k]}
        q = Person(ch, f"{name}{k}", seed=60 + k + (0 if side > 0 else 7), cloth_style=st, skin_style={"frost": 0.55, "blood": 0.5})
        bones = ["upperarm" + sfx, "lowerarm" + sfx, "hand" + sfx] + [f"{f}_{n:02d}{sfx}" for f in ("index", "middle", "ring", "pinky", "thumb") for n in (1, 2, 3)]
        q.mark("m_arm", bones)
        q.pose([("upperarm" + sfx, "Y", 43 * side), ("lowerarm" + sfx, "X", 38 + 18 * k), ("hand" + sfx, "X", 20 - 10 * k)])
        sh = Vector(q.bone_head("upperarm" + sfx))
        yaw = [-22, 4, 20, 36][k] * side
        S = Matrix.Diagonal((1.25, 1.25, 1.9 + 0.12 * k, 1.0))
        Mq = Matrix.Translation(piv + Vector((0.1 * side * (k - 1.5), 0.06 * (k - 1.5), 0))) @ Matrix.Rotation(math.radians(yaw), 4, 'Z') \
            @ Matrix.Rotation(math.radians(10 * (k - 1.5)), 4, 'X') @ S @ Matrix.Translation(-sh)
        r = finalize_person(q, Mq, dec={"body": 0.22, "default": 0.25}, vcol_fn=vcol_grime(r0=0.2, r1=0.9, dark=0.8, seed=k), select="m_arm", thr=0.5,
                            roles=["body", "shirt", "top", "overalls", "cardigan", "uniform", "jacket", "parka", "hoodie", "coat", "gloves"],
                            name=f"{name}{k}", free=True)
        parts.extend(r.values())
    return parts

arm_objs = []
for side, nm in ((1, "ArmR"), (-1, "ArmL")):
    parts = build_arm_bundle(side, nm + "_")
    sb = MeshBuilder(nm + "_lump")
    piv = Vector((-0.5 * side, 0.1, 2.9))
    add_blob(sb, piv + Vector((0.0, 0, 0.04)), (0.26, 0.24, 0.26), seg=12, rings=8, noise_amp=0.35, seed=side, color=(0.9, 0.9, 1.0, 1))
    # sinew bands tying the arms together
    for j in range(4):
        zz = piv.z - 0.4 - j * 0.4
        pts = [piv + Vector((math.cos(a_) * 0.11 * side, math.sin(a_) * 0.11, zz - piv.z)) for a_ in [x * 0.8 for x in range(9)]]
        add_tube(sb, pts, 0.02, sides=5, color=(0.9, 0.7, 0.72, 1), cap=False)
    parts.append(sb.build([flesh]))
    ao = join(parts, nm)
    origin_to(ao, piv)
    arm_objs.append(ao)

# ------------------------------------------------------------------ fused flesh mortar (metaballs)
elems = []
for k in range(26):
    zz = 0.2 + k * 0.19
    rr = 0.1
    ang = k * 2.4
    elems.append((Vector((math.cos(ang) * rr, math.sin(ang) * rr, zz)), 0.62 - 0.14 * zz / 4.8, 2.0, (1.0, 1.0, 1.4)))
for i, (char, seed, cst, yaw, z, weak, lean, pose) in enumerate(CONG):
    a = math.radians(yaw)
    rad = 0.66 - 0.14 * (z / 4.0)
    elems.append((Vector((math.cos(a) * rad * 0.5, math.sin(a) * rad * 0.5, z - 0.5)), 0.45, 2.0, (1.1, 1.1, 1.6)))
# swollen base mound
for k in range(12):
    ang = k * (math.tau / 12) + 0.2
    elems.append((Vector((math.cos(ang) * 0.85, math.sin(ang) * 0.85, 0.2)), 0.55, 2.0, (1.4, 1.4, 0.8)))
elems.append((Vector((0, 0, 0.35)), 1.0, 2.0, (1.4, 1.4, 0.7)))
mortar = metaball_mesh("Mortar", elems, resolution=0.075, threshold=0.55, mat=flesh)
smooth_mesh(mortar, 2, 0.5)
displace_noise(mortar, 0.05, 3.2, seed=4.0, octaves=4)
decimate(mortar, min(1.0, 13000 / max(1, tri_count(mortar))))
uv_box(mortar, 0.55)
shade_smooth(mortar)
ensure_col(mortar)
set_vertex_color(mortar, vcol_flesh(seed=3, bloody=0.35))
print("mortar tris", tri_count(mortar))
glaze = mortar.copy()
glaze.data = mortar.data.copy()
bpy.context.scene.collection.objects.link(glaze)
glaze.name = "Glaze"
glaze.data.materials.clear()
glaze.data.materials.append(M["ice_glaze"])
for v in glaze.data.vertices:
    v.co = v.co + v.normal * (0.014 + 0.01 * noise.noise(v.co * 5.0))
decimate(glaze, 0.35)
ensure_col(glaze)
set_vertex_color(glaze, lambda co, n, i: (1, 1, 1, 1))
# sinew: flesh cords bridging neighbouring congregants
sinew = MeshBuilder("sinew")
for i in range(len(CONG) - 1):
    for _ in range(3):
        a0 = people_centres[i] + Vector((rng2.uniform(-0.15, 0.15), rng2.uniform(-0.15, 0.15), rng2.uniform(-0.2, 0.2)))
        a1 = people_centres[i + 1] + Vector((rng2.uniform(-0.15, 0.15), rng2.uniform(-0.15, 0.15), rng2.uniform(-0.2, 0.2)))
        mid = (a0 + a1) * 0.5 + Vector((rng2.uniform(-0.1, 0.1), rng2.uniform(-0.1, 0.1), 0)) + (a0 - Vector((0, 0, a0.z))).normalized() * 0.12
        pts = [a0.lerp(mid, t) .lerp(mid.lerp(a1, t), t) for t in [x / 7 for x in range(8)]]
        add_tube(sinew, pts, [0.02 + 0.012 * math.sin(j) for j in range(8)], sides=5, color=(0.85, 0.62, 0.66, 1), noise_amp=0.25)
sinew_o = sinew.build([flesh])
shade_smooth(sinew_o)

# ------------------------------------------------------------------ ice crystals + frozen blood
mb = MeshBuilder("Ice")
imats = [M["ice"], M["ice_deep"], M["ice_glow"], M["ice_blood"]]
rng3 = random.Random(5)
for (mc, nrm) in mouth_pts:           # crystals bursting from mouths
    for _ in range(2):
        d = nrm + Vector((rng3.uniform(-0.6, 0.6), rng3.uniform(-0.6, 0.6), rng3.uniform(0.0, 0.8)))
        add_crystal(mb, mc + nrm * 0.04, d, rng3.uniform(0.18, 0.5), rng3.uniform(0.01, 0.022), rng=rng3, mat_index=rng3.choice([0, 0, 2]))
for (hc, nrm) in head_pts:            # growing out of skulls
    for _ in range(2):
        d = Vector((rng3.uniform(-0.5, 0.5), rng3.uniform(-0.5, 0.5), 1.0))
        add_crystal(mb, hc + Vector((0, 0, 0.1)), d, rng3.uniform(0.2, 0.7), rng3.uniform(0.014, 0.03), rng=rng3, mat_index=rng3.choice([0, 1]))
col_spots = []
for k in range(120):                  # growth from the fused core
    zz = rng3.uniform(0.3, 4.6)
    ang = rng3.uniform(0, math.tau)
    rr = (0.62 - 0.14 * zz / 4.0) * rng3.uniform(0.7, 1.0)
    col_spots.append((Vector((math.cos(ang) * rr, math.sin(ang) * rr, zz)), Vector((math.cos(ang), math.sin(ang), 0.3))))
scatter_crystals(mb, rng3, col_spots, 30, length=(0.2, 0.7), radius=(0.02, 0.06), up_bias=0.35, spread=0.45, mat_index=0)
scatter_crystals(mb, rng3, col_spots, 8, length=(0.5, 1.1), radius=(0.05, 0.09), up_bias=0.3, spread=0.4, mat_index=1)
for k in range(14):                   # crown of crystal above the top head
    ang = rng3.uniform(0, math.tau)
    rr = rng3.uniform(0.0, 0.3)
    d = Vector((math.cos(ang) * 0.3, math.sin(ang) * 0.3, 1.0))
    add_crystal(mb, Vector((math.cos(ang) * rr, math.sin(ang) * rr, 4.55)), d, rng3.uniform(0.5, 1.3), rng3.uniform(0.05, 0.11), rng=rng3, mat_index=2 if k % 4 == 0 else 1)
for k in range(11):                   # base shards radiating outward
    ang = k * (math.tau / 18) + rng3.uniform(-0.1, 0.1)
    d = Vector((math.cos(ang), math.sin(ang), rng3.uniform(0.6, 1.2)))
    add_crystal(mb, Vector((math.cos(ang) * 1.0, math.sin(ang) * 1.0, 0.05)), d, rng3.uniform(0.6, 1.5), rng3.uniform(0.06, 0.13), rng=rng3, mat_index=rng3.choice([0, 1]))
# frozen blood: icicles hanging from mouths + frozen rivulets running down the bodies
icicles(mb, rng3, [mc + Vector((0, 0, -0.03)) for mc, n in mouth_pts] * 3, 26, length=(0.15, 0.6), mat_index=3)
for (mc, nrm) in mouth_pts:
    pts = []
    p0 = mc + nrm * 0.03 + Vector((rng3.uniform(-0.03, 0.03), 0, -0.03))
    for j in range(9):
        pts.append(p0 + Vector((nrm.x * 0.03 * j + rng3.uniform(-0.02, 0.02), nrm.y * 0.03 * j + rng3.uniform(-0.02, 0.02), -0.11 * j)))
    add_tube(mb, pts, [0.03 - 0.0025 * j for j in range(9)], sides=6, mat_index=3, noise_amp=0.4)
for tp in tears:   # frozen tears
    add_crystal(mb, tp, Vector((0, 0.1, -1)), rng3.uniform(0.07, 0.16), 0.006, sides=4, tip=0.6, rng=rng3, mat_index=0)
ice = mb.build(imats)
shade_smooth(ice)
ensure_col(ice)

# ------------------------------------------------------------------ assemble + export
body = join(people_objs + [mortar, sinew_o], "Body")
for ob in (body, ice, glaze, *head_objs, *arm_objs):
    ob.rotation_mode = 'XYZ'
tris = export(os.path.join(OUT_DIR, "choir.glb"))
