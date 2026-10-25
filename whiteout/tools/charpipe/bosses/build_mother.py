"""THE HOLLOW MOTHER.  -> assets/enemies/mother_p1.glb  (phase 1: crystal lattice + Ruth fused at the centre)
                        assets/enemies/mother_p2.glb  (phase 2: Ruth torn free on 8 crystalline spider legs)
Phase 1 nodes: Lattice (crystals/roots/thorax), Ruth (upper body, origin at her chest), Heart (glowing weak point), Ice (translucent
crystals).   Phase 2 nodes: Ruth, Heart, Abdomen, Ice, Leg0..Leg7 (each: up, lo, knee, tip - unit-length crystal pieces the
script poses with its two-bone IK: pieces are modelled along +Y (glTF) with radius 1 so the script's non-uniform scale shapes them).
Front = glTF +Z (Blender -Y); the lattice fans out behind (-Z)."""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bosslib import *
from common import *

ONLY = os.environ.get("MOTHER_ONLY", "")
SC = 1.28           # Ruth is larger than life


def mats():
    M = std_mats()
    M["wet"] = make_mat("blood_flesh", color=(0.42, 0.04, 0.05, 1), rough=0.1, spec=0.9, coat=1.0, coat_rough=0.05, sss=0.2)
    M["root"] = make_mat("root", color=(0.05, 0.05, 0.08, 1), rough=0.35, metal=0.3, emission=(0.1, 0.35, 0.5, 1), emit=0.5)
    M["heart_glow"] = make_mat("glow_heart", color=(0.3, 0.7, 0.8, 1), rough=0.3, emission=(0.5, 0.95, 1.0, 1), emit=5.0)
    M["flesh"] = flesh_mat("flesh_mortar", 5)
    return M


def ruth_person(tag, M, phase):
    st = {"variant": 7, "flat": (0.42, 0.28, 0.36), "frost": 0.55, "dirt": 0.4, "blood": 0.45}
    p = Person("ruth", tag, seed=321, cloth_style=st, skin_style={"frost": 0.5, "blood": 0.5, "livid": 0.55, "bruise": 0.4},
               keep=["body", "cardigan", "hair"])
    if phase == 1:
        p.head_morph(stretch=0.06, jaw=0.32, mouth_cut=0.009)
    else:
        p.head_morph(stretch=0.12, jaw=0.95, mouth_cut=0.013)
    p.add_eyes(M["eye_glow"], 1.12)
    tb = MeshBuilder("th")
    add_blob(tb, p.mouth + Vector((0, 0.03, -0.018)), (0.034, 0.045, 0.04), seg=10, rings=6)
    p.add_part(tb.build([M["throat_glow"]]), "throat", "head")
    return p


def crystal_chain_along(mb, rng, a, b, n, radius, mat_index=0, up=0.3):
    for k in range(n):
        t = rng.random()
        pt = a.lerp(b, t)
        d = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.2, 1))) + Vector((0, 0, up))
        add_crystal(mb, pt, d, rng.uniform(0.12, 0.4), radius * rng.uniform(0.6, 1.4), rng=rng, mat_index=mat_index)


# =============================================================================== phase 1
def build_p1():
    reset()
    M = mats()
    rng = random.Random(2026)
    p = ruth_person("r1", M, 1)
    p.pose([("spine_01", "X", -3), ("spine_03", "X", -5), ("neck_01", "X", -2), ("head", "X", -12),
            ("upperarm_l", "Y", -78), ("upperarm_r", "Y", 78), ("upperarm_l", "X", -12), ("upperarm_r", "X", -12),
            ("lowerarm_l", "X", -8), ("lowerarm_r", "X", -8), ("hand_l", "Y", -10), ("hand_r", "Y", 10)])
    p.mark("m_lower", ["thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r", "ball_l", "ball_r"])
    chest_local = Vector(p.arm.pose.bones["spine_03"].head)
    arm_pts = {n: (Vector(p.arm.pose.bones[n].head), Vector(p.arm.pose.bones[n].tail)) for n in ("upperarm_l", "lowerarm_l", "upperarm_r", "lowerarm_r", "hand_l", "hand_r")}
    head_posed = Vector(p.arm.pose.bones["head"].head) + Vector((0, -0.02, 0.1))
    HEART = Vector((0, -0.45, 2.75))
    Mx = Matrix.Translation(HEART) @ Matrix.Scale(SC, 4) @ Matrix.Translation(-(chest_local + Vector((0, -0.07, 0.0))))
    res = finalize_person(p, Mx, dec={"body": 0.5, "hair": 0.5, "default": 0.5}, vcol_fn=vcol_grime(axis=(0, 0), r0=10, r1=20, dark=0.9),
                          select="m_lower", thr=0.5, invert=True, name="ruth")
    # open the chest: wet flesh, ribs, crystals bursting out, glowing heart (separate node)
    ctr = HEART + Vector((0, 0.0, 0.0))
    ribs, heart, strands = open_chest(res, ctr, M["wet"], M["bone"], M["heart_glow"], rx=0.15, rz=0.21, strands=18, rng=rng, glow_scale=1.5)
    cb = MeshBuilder("chest_crystals")
    for k in range(14):
        d = Vector((rng.uniform(-0.7, 0.7), -rng.uniform(0.3, 1.0), rng.uniform(-0.3, 0.9)))
        add_crystal(cb, ctr + Vector((rng.uniform(-0.08, 0.08), 0.0, rng.uniform(-0.1, 0.1))), d, rng.uniform(0.15, 0.45), rng.uniform(0.012, 0.03), rng=rng, mat_index=rng.choice([0, 2, 2]))
    chest_cr = cb.build([M["ice"], M["ice_deep"], M["ice_glow"]])
    ensure_col(chest_cr)
    ruth_parts = list(res.values()) + [ribs, strands]
    # crystal sleeves along her spread arms (fused into the lattice)
    ab = MeshBuilder("arm_ice")
    for nm in ("upperarm_l", "lowerarm_l", "upperarm_r", "lowerarm_r"):
        h, t = arm_pts[nm]
        crystal_chain_along(ab, rng, Mx @ h, Mx @ t, 7, 0.018, mat_index=0, up=0.4)
    # crystals bursting from shoulders and out of the hair
    hc = Mx @ (Vector(p.bone_head("head")) + Vector((0, 0.05, 0.12)))
    for k in range(9):
        d = Vector((rng.uniform(-0.8, 0.8), rng.uniform(0.2, 0.8), 1.0))
        add_crystal(ab, hc, d, rng.uniform(0.2, 0.7), rng.uniform(0.014, 0.03), rng=rng, mat_index=rng.choice([0, 1]))
    arm_ice = ab.build([M["ice"], M["ice_deep"]])
    ensure_col(arm_ice)
    Ruth = join(ruth_parts, "Ruth")
    origin_to(Ruth, ctr)
    hm = empty("HeadMark", Mx @ head_posed)
    hm.parent = Ruth
    hm.matrix_parent_inverse = Ruth.matrix_world.inverted()
    Heart = join([heart, chest_cr], "Heart")
    origin_to(Heart, ctr)

    # ------------------------------------------------------------- the vast crystal lattice behind her
    hub = Vector((0, 1.0, 3.0))
    ib = MeshBuilder("Ice")
    imats = [M["ice"], M["ice_deep"], M["ice_glow"], M["ice_blood"]]
    cores = []
    for i in range(86):
        d = Vector((rng.uniform(-1.0, 1.0), rng.uniform(0.12, 1.0), rng.uniform(-0.55, 1.0))).normalized()
        start = hub + Vector((rng.uniform(-1, 1), rng.uniform(-0.5, 0.5), rng.uniform(-0.6, 0.8)))
        L = rng.uniform(2.5, 8.5)
        R = rng.uniform(0.14, 0.5)
        mi = [1, 1, 1, 0, 0, 1, 2][i % 7]
        add_crystal(ib, start, d, L, R, sides=6, tip=0.18, jitter=0.2, rng=rng, mat_index=mi, taper=0.8)
        if i % 2 == 0:   # inner glowing core: reads as light trapped inside the crystal
            add_crystal(ib, start + d * 0.1, d, L * 0.8, R * 0.38, sides=5, tip=0.2, jitter=0.1, rng=rng, mat_index=2, taper=0.7)
    for i in range(36):  # floor spikes behind
        x = rng.uniform(-10, 10)
        y = rng.uniform(1.5, 7)
        d = Vector((rng.uniform(-0.3, 0.3) - x * 0.03, rng.uniform(-0.4, 0.2), 1.0))
        L = rng.uniform(2.0, 6.0)
        R = rng.uniform(0.2, 0.55)
        add_crystal(ib, Vector((x, y, -0.2)), d, L, R, tip=0.2, rng=rng, mat_index=1)
        if i % 3 == 0:
            add_crystal(ib, Vector((x, y, -0.1)), d, L * 0.75, R * 0.35, sides=5, tip=0.2, rng=rng, mat_index=2)
    for i in range(40):   # small shards close to her
        a = rng.uniform(0, math.tau)
        base = Vector((math.cos(a) * rng.uniform(0.8, 2.4), rng.uniform(0.2, 1.4), 2.0 + math.sin(a) * rng.uniform(0.5, 1.8)))
        add_crystal(ib, base, Vector((math.cos(a), 0.2, math.sin(a))), rng.uniform(0.4, 1.2), rng.uniform(0.04, 0.1), rng=rng, mat_index=rng.choice([0, 1, 2]))
    ice = ib.build(imats)
    ensure_col(ice)
    shade_smooth(ice)
    arm_ice_o = arm_ice

    lat = MeshBuilder("Lattice")
    # dark root tendrils draped over everything (glow faintly)
    for i in range(26):
        top = hub + Vector((rng.uniform(-3, 3), rng.uniform(-0.5, 3), rng.uniform(0.5, 4)))
        pts = [top]
        for k in range(4):
            pts.append(pts[-1] + Vector((rng.uniform(-0.5, 0.5), rng.uniform(-0.3, 0.5), -rng.uniform(0.7, 1.4))))
            pts[-1].z = max(pts[-1].z, 0.0)
        add_tube(lat, pts, [0.11 - 0.015 * k for k in range(len(pts))], sides=6, mat_index=0, noise_amp=0.25, seed=i)
    root_o = lat.build([M["root"]])
    ensure_col(root_o)
    shade_smooth(root_o)
    # thorax mass she is fused into: sculpted flesh/ice mortar (metaballs)
    elems = [((0, 0.35, 2.1), 1.5, 2.0, (1.1, 0.9, 0.9)), ((0.0, 0.55, 2.5), 1.2, 2.0, (1.4, 0.8, 0.9)), ((-1.2, 0.4, 2.7), 0.7, 2.0, (1, 1, 1)), ((1.2, 0.4, 2.7), 0.7, 2.0, (1, 1, 1)),
             ((0, 0.2, 1.3), 1.2, 2.0, (1.2, 0.9, 0.8)), ((-0.9, 0.2, 1.0), 0.6, 2.0, (1, 1, 1)), ((0.9, 0.2, 1.0), 0.6, 2.0, (1, 1, 1))]
    for k in range(18):
        a = rng.uniform(0, math.tau)
        elems.append(((math.cos(a) * rng.uniform(0.7, 1.7), rng.uniform(0.2, 0.9), 2.1 + math.sin(a) * rng.uniform(0.5, 1.5)), rng.uniform(0.35, 0.6), 2.0, (1, 1, 1)))
    mortar = metaball_mesh("mortar", elems, resolution=0.09, threshold=0.55, mat=M["flesh"])
    smooth_mesh(mortar, 2, 0.5)
    displace_noise(mortar, 0.07, 2.8, seed=3.0, octaves=4)
    decimate(mortar, min(1.0, 9000 / max(1, tri_count(mortar))))
    uv_box(mortar, 0.5)
    shade_smooth(mortar)
    ensure_col(mortar)
    set_vertex_color(mortar, vcol_flesh(seed=6, bloody=0.4))
    lattice = join([root_o, mortar], "Lattice")
    ice_all = join([ice, arm_ice_o], "Ice")
    print("P1 tris", total_tris())
    export(os.path.join(OUT_DIR, "mother_p1.glb"))


# =============================================================================== phase 2
def build_p2():
    reset()
    M = mats()
    rng = random.Random(7)
    p = ruth_person("r2", M, 2)
    p.pose([("spine_01", "X", -10), ("spine_03", "X", -12), ("neck_01", "X", 6), ("head", "X", 10),
            ("upperarm_l", "X", -95), ("upperarm_r", "X", -105), ("upperarm_l", "Y", 18), ("upperarm_r", "Y", -22),
            ("lowerarm_l", "X", -25), ("lowerarm_r", "X", -15), ("hand_l", "X", -10), ("hand_r", "X", -20)])
    p.mark("m_lower", ["thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r", "ball_l", "ball_r"])
    chest_local = Vector(p.arm.pose.bones["spine_03"].head)
    # In game space the Ruth node sits at (0, 1.5, 0.2) (Blender (0,-0.2,1.5)); her waist is ~ (0, 0.2, ~2.0)
    head_posed = Vector(p.arm.pose.bones["head"].head) + Vector((0, -0.02, 0.1))
    HEART = Vector((0, -0.55, 3.0))
    Mx = Matrix.Translation(HEART) @ Matrix.Rotation(math.radians(-14), 4, 'X') @ Matrix.Scale(SC, 4) @ Matrix.Translation(-(chest_local + Vector((0, -0.07, 0.0))))
    res = finalize_person(p, Mx, dec={"body": 0.5, "hair": 0.5, "default": 0.5}, vcol_fn=vcol_grime(axis=(0, 0), r0=10, r1=20, dark=0.9),
                          select="m_lower", thr=0.5, invert=True, name="ruth")
    ctr = HEART
    ribs, heart, strands = open_chest(res, ctr, M["wet"], M["bone"], M["heart_glow"], rx=0.15, rz=0.21, strands=18, rng=rng, glow_scale=1.4)
    # torn waist: ragged flesh collar, exposed spine and ribs, strands trailing back to the abdomen
    wb = MeshBuilder("waist")
    wc = Mx @ (Vector(p.bone_head("pelvis")) + Vector((0, 0.0, 0.05)))
    add_blob(wb, wc + Vector((0, 0.05, 0.0)), (0.34, 0.26, 0.2), seg=12, rings=8, noise_amp=0.4, color=(0.85, 0.5, 0.52, 1))
    for k in range(16):
        a = rng.uniform(0, math.tau)
        pts = [wc + Vector((math.cos(a) * 0.2, math.sin(a) * 0.15, -0.05))]
        for j in range(5):
            pts.append(pts[-1] + Vector((math.cos(a) * 0.04 + rng.uniform(-0.05, 0.05), 0.2 + rng.uniform(0, 0.1), -0.08 - rng.uniform(0, 0.05))))
        add_tube(wb, pts, [0.03 - 0.004 * j for j in range(6)], sides=5, color=(0.85, 0.45, 0.48, 1), noise_amp=0.2)
    for k in range(10):   # broken ribs / spine splinters
        a = rng.uniform(0, math.tau)
        add_crystal(wb, wc + Vector((math.cos(a) * 0.2, math.sin(a) * 0.16, 0.0)), Vector((math.cos(a) * 0.3, math.sin(a) * 0.3, -1)), rng.uniform(0.12, 0.3), 0.012, sides=5, rng=rng, mat_index=1)
    waist = wb.build([M["wet"], M["bone"]])
    ensure_col(waist); shade_smooth(waist)
    # crystals growing from her back, shoulders and chest (the lattice is in her now)
    cb = MeshBuilder("growth")
    for k in range(18):
        d = Vector((rng.uniform(-0.8, 0.8), rng.uniform(0.0, 0.9), 1.0))
        add_crystal(cb, HEART + Vector((rng.uniform(-0.3, 0.3), 0.2, rng.uniform(-0.2, 0.3))), d, rng.uniform(0.25, 0.8), rng.uniform(0.02, 0.05), rng=rng, mat_index=rng.choice([0, 1, 2]))
    for k in range(10):
        d = Vector((rng.uniform(-0.7, 0.7), -rng.uniform(0.3, 1.0), rng.uniform(-0.3, 0.9)))
        add_crystal(cb, ctr + Vector((rng.uniform(-0.08, 0.08), 0.0, rng.uniform(-0.1, 0.1))), d, rng.uniform(0.15, 0.4), rng.uniform(0.012, 0.028), rng=rng, mat_index=2)
    growth = cb.build([M["ice"], M["ice_deep"], M["ice_glow"]])
    ensure_col(growth)
    ruth_parts = list(res.values()) + [ribs, strands, waist, growth]
    Ruth = join(ruth_parts, "Ruth")
    # origin where the script puts the node: (0,-0.2,1.5) Blender
    origin_to(Ruth, Vector((0, -0.2, 1.5)))
    hm = empty("HeadMark", Mx @ head_posed)
    hm.parent = Ruth
    hm.matrix_parent_inverse = Ruth.matrix_world.inverted()
    Heart = heart
    Heart.name = "Heart"
    origin_to(Heart, ctr)

    # abdomen: a translucent crystal sac glowing from within, trailing behind her
    ab = Vector((0, 1.0, 2.0))
    abm = MeshBuilder("Abdomen")
    add_blob(abm, ab, (0.9, 1.35, 0.8), seg=14, rings=10, noise_amp=0.18, mat_index=0)
    for k in range(10):
        a = rng.uniform(0, math.tau)
        add_crystal(abm, ab + Vector((math.cos(a) * 0.5, rng.uniform(0.2, 0.9), 0.5 + 0.2 * math.sin(a))), Vector((math.cos(a) * 0.4, 0.5, 1)), rng.uniform(0.6, 1.3), rng.uniform(0.07, 0.14), rng=rng, mat_index=1)
    for k in range(7):    # veins
        a0 = ab + Vector((rng.uniform(-0.6, 0.6), rng.uniform(-0.8, 0.8), rng.uniform(0.3, 0.7)))
        pts = [a0 + Vector((rng.uniform(-0.25, 0.25) * j, 0.28 * j, 0.0)) for j in range(5)]
        add_tube(abm, pts, [0.045 - 0.007 * j for j in range(5)], sides=5, mat_index=2, noise_amp=0.2)
    add_blob(abm, ab, (0.55, 0.9, 0.5), seg=10, rings=8, mat_index=3)       # glowing core
    abdomen = abm.build([M["flesh"], M["ice_deep"], M["root"], M["ice_glow"]])
    ensure_col(abdomen); shade_smooth(abdomen)
    origin_to(abdomen, ab)

    # legs: unit-space crystal pieces
    def piece(name, kind):
        mb = MeshBuilder(name)
        r_ = random.Random(hash(name) % 1000 + 1)
        if kind in ("up", "lo"):
            n = 5 if kind == "up" else 4
            for k in range(n):
                ang = math.tau * k / n + r_.uniform(-0.3, 0.3)
                off = Vector((math.cos(ang), 0, math.sin(ang))) * (0.0 if k == 0 else 0.45)
                # blender: glTF Y up = Blender +Z ; unit piece along +Z
                base = Vector((off.x, off.z, r_.uniform(-0.02, 0.1)))
                L = r_.uniform(0.7, 1.05) if k else 1.0
                add_crystal(mb, base, Vector((off.x * 0.12, off.z * 0.12, 1.0)), L, 0.62 if k == 0 else r_.uniform(0.25, 0.5), sides=6, tip=0.12 if kind == "up" else 0.2,
                            jitter=0.25, rng=r_, mat_index=0, taper=0.78)
        elif kind == "tip":
            add_crystal(mb, Vector((0, 0, 0)), Vector((0, 0, 1)), 1.0, 1.0, sides=5, tip=0.55, jitter=0.15, rng=r_, mat_index=1, taper=0.7)
        else:
            add_blob(mb, Vector((0, 0, 0)), (0.13, 0.13, 0.13), seg=8, rings=6, noise_amp=0.2, mat_index=2)
        ob = mb.build([M["ice_deep"], M["ice"], M["ice_glow"]])
        ensure_col(ob); shade_smooth(ob)
        return ob

    legs = []
    for i in range(8):
        root = empty(f"Leg{i}", (0, 0, 0))
        for kind in ("up", "lo", "knee", "tip"):
            o = piece(f"Leg{i}_{kind}", kind)
            o.name = kind if False else f"Leg{i}_{kind}"
            o.parent = root
        legs.append(root)
    ice = MeshBuilder("Ice")
    # spiny crystals trailing over the abdomen are in its mesh; a halo of shards around Ruth's shoulders
    for k in range(24):
        a = rng.uniform(0, math.tau)
        add_crystal(ice, HEART + Vector((math.cos(a) * 0.5, 0.3 + math.sin(a) * 0.3, 0.3 + rng.uniform(0, 0.5))), Vector((math.cos(a) * 0.5, 0.4, 1)), rng.uniform(0.4, 1.0), rng.uniform(0.02, 0.05), rng=rng, mat_index=rng.choice([0, 1]))
    iceo = ice.build([M["ice"], M["ice_deep"]])
    ensure_col(iceo)
    print("P2 tris", total_tris())
    export(os.path.join(OUT_DIR, "mother_p2.glb"))


if ONLY in ("", "1"):
    build_p1()
if ONLY in ("", "2"):
    build_p2()
