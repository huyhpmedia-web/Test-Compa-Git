"""THE HAULER: ~4 m tall, ~6 m long mound of fused frozen miners around a haul-truck driver.  -> assets/enemies/hauler.glb
Nodes (glTF/Godot space, front = +Z):
  Mass    (Node3D at origin)  children: Body, Ice, Crawler0..N  (Crawler = miner dragging himself; empties with local frame
          facing outward, geometry pivots at the shoulder; the script rocks them about their local X axis)
  Crown   (Node3D, the cab position (0, 3.35, 0.3))  children: Driver (origin = the glowing chest = weak point), Cab
"""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bosslib import *
from common import *

reset()
M = std_mats()
flesh = flesh_mat("flesh_mortar", 5)
wet = make_mat("blood_flesh", color=(0.1, 0.008, 0.01, 1), rough=0.12, spec=0.9, coat=1.0, coat_rough=0.04, sss=0.2)
rubber = make_mat("rubber", color=(0.04, 0.04, 0.045, 1), rough=0.85, spec=0.3)
rock = make_mat("rock", color=(0.16, 0.16, 0.19, 1), rough=0.9, spec=0.3)
heart_glow = make_mat("glow_heart", color=(0.6, 0.2, 0.1, 1), rough=0.3, emission=(1.0, 0.45, 0.2, 1), emit=4.0)
rng = random.Random(31337)

CROWN = Vector((0, -0.3, 3.35))     # Blender coords (Godot (0, 3.35, 0.3))
BODY_C = Vector((0, 0.15, 1.45))
EL = (2.05, 2.85, 1.65)             # mound half extents (x, y, z)


def surface_point(theta, phi):
    """point on the mound ellipsoid (theta: azimuth, phi: polar from +Z)"""
    return BODY_C + Vector((EL[0] * math.sin(phi) * math.cos(theta), EL[1] * math.sin(phi) * math.sin(theta), EL[2] * math.cos(phi)))


def surface_normal(theta, phi):
    n = Vector((math.sin(phi) * math.cos(theta) / EL[0], math.sin(phi) * math.sin(theta) / EL[1], math.cos(phi) / EL[2]))
    return n.normalized()


def yaw_of(n):
    """yaw (deg from +X) of a horizontal direction"""
    return math.degrees(math.atan2(n.y, n.x))


# --------------------------------------------------------------------------- the fused miners in the mound
ARMS = [
    [("upperarm_l", "X", -100), ("upperarm_r", "X", -100), ("upperarm_l", "Y", 20), ("upperarm_r", "Y", -20), ("lowerarm_l", "X", -20), ("lowerarm_r", "X", -20)],
    [("upperarm_l", "Y", -140), ("upperarm_r", "Y", 140), ("lowerarm_l", "X", -35), ("lowerarm_r", "X", -35)],
    [("upperarm_l", "X", -130), ("upperarm_r", "Y", 100), ("lowerarm_l", "X", -40), ("lowerarm_r", "X", -10)],
    [("upperarm_l", "Y", -60), ("upperarm_r", "X", -150), ("lowerarm_l", "X", -60), ("lowerarm_r", "X", -20)],
]
CHARS = ["rimebound_miner"] * 11 + ["rimebound_civ_m", "elias", "rimebound_miner", "rimebound_civ_f", "rimebound_nurse", "rimebound_miner", "ruth"]
MULS = [(1.0, 1.0, 1.0), (0.7, 0.7, 0.85), (0.9, 0.75, 0.6), (0.55, 0.55, 0.6)]
people = []
n_mound = 17
placed = []
for i in range(n_mound):
    for _try in range(40):
        theta = rng.uniform(0, math.tau)
        phi = rng.uniform(0.25, 1.75)
        pt = surface_point(theta, phi)
        if all((pt - q).length > 0.9 for q in placed):
            break
    placed.append(pt)
    nrm = surface_normal(theta, phi)
    horiz = Vector((nrm.x, nrm.y, 0))
    yaw = yaw_of(horiz if horiz.length > 0.2 else Vector((0, -1, 0)))
    ch = CHARS[i % len(CHARS)]
    st = {"variant": i, "mul": MULS[i % 4], "frost": 0.55, "dirt": 0.55, "blood": 0.3}
    p = Person(ch, f"m{i}", seed=100 + i, cloth_style=st, skin_style={"frost": 0.5, "blood": 0.4, "livid": 0.7})
    scream = i % 3 != 0
    p.head_morph(stretch=0.18 + 0.1 * (i % 3), jaw=0.55 if scream else 0.0, mouth_cut=0.008 if scream else 0.0)
    p.add_eyes(M["eye_dead"])
    if scream:
        tb = MeshBuilder("th")
        add_blob(tb, p.mouth + Vector((0, 0.03, -0.018)), (0.034, 0.045, 0.04), seg=10, rings=6)
        p.add_part(tb.build([M["mouth_dark"]]), "throat", "head")
    p.pose([("spine_03", "X", 6), ("neck_01", "X", -10), ("head", "X", -18 + 10 * (i % 3))] + ARMS[i % len(ARMS)])
    p.mark("m_lower", ["thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r", "ball_l", "ball_r"])
    lean = 25 + 25 * ((i * 7) % 4) / 3.0 + (20 if phi < 0.6 else 0)
    Mx = person_matrix(pt + nrm * 0.0 + Vector((0, 0, 0.1)), yaw, lean, (0, -0.02, 1.2), 1.5, roll_deg=rng.uniform(-18, 18))
    fn = vcol_grime(axis=(BODY_C.x, BODY_C.y), r0=0.5, r1=2.4, dark=0.6, seed=i)
    res = finalize_person(p, Mx, dec={"body": 0.1, "hair": 0.25, "default": 0.12}, vcol_fn=fn, select="m_lower", thr=0.5, invert=True, name=f"m{i}")
    people.extend(res.values())
print("mound miners tris", total_tris())

# --------------------------------------------------------------------------- crawlers: miners dragging the mass
crawlers = []
crawl_roots = []
NC = 10
for i in range(NC):
    f = (i + 0.5) / NC
    # distribute around the front half and sides (the crawl arms pull forward)
    ang = math.radians(-90) + math.radians(rng.uniform(-125, 125)) * (1 if i % 2 == 0 else -1) * (0.35 + 0.65 * ((i // 2) / (NC / 2.0)))
    rad_x, rad_y = 2.1, 2.85
    pos = Vector((math.cos(ang) * (rad_x + 0.1), math.sin(ang) * (rad_y + 0.05), 0.55))
    outward = Vector((math.cos(ang) / rad_x, math.sin(ang) / rad_y, 0)).normalized()
    yaw = yaw_of(outward)
    ch = ["rimebound_miner", "rimebound_civ_m", "rimebound_miner", "rimebound_nurse"][i % 4]
    st = {"variant": 20 + i, "mul": MULS[(i + 1) % 4], "frost": 0.6, "dirt": 0.5, "blood": 0.35}
    p = Person(ch, f"c{i}", seed=200 + i, cloth_style=st, skin_style={"frost": 0.55, "blood": 0.45})
    p.head_morph(stretch=0.1, jaw=0.4 if i % 2 else 0.0, mouth_cut=0.008 if i % 2 else 0.0)
    p.add_eyes(M["eye_dead"])
    p.pose([("spine_03", "X", 15), ("neck_01", "X", -28), ("head", "X", -30),
            ("upperarm_l", "X", -70 - 25 * (i % 2)), ("upperarm_r", "X", -95 + 25 * (i % 2)), ("upperarm_l", "Y", 18), ("upperarm_r", "Y", -18),
            ("lowerarm_l", "X", -8), ("lowerarm_r", "X", -8)])
    p.mark("m_lower", ["thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r", "ball_l", "ball_r"])
    shoulder = Vector((0, -0.02, 1.28))
    # local frame: pivot at the shoulder, leaning forward (negative lean) ~50 deg
    Mloc = person_matrix(Vector((0, 0, 0)), -90, -50 - 6 * (i % 3), shoulder, 1.5)
    fn = vcol_grime(axis=(0, 0), r0=10, r1=20, dark=0.75, seed=i)
    res = finalize_person(p, Mloc, dec={"body": 0.1, "hair": 0.25, "default": 0.12}, vcol_fn=fn, select="m_lower", thr=0.5, invert=True, name=f"c{i}")
    # pelvis stump flesh + shoulder fixed: join to one object, root empty at the shoulder world position
    co = join(list(res.values()), f"Crawler{i}")
    root = empty(f"Crawler{i}_root", pos + Vector((0, 0, 0.6)))
    root.rotation_euler = (0, 0, math.radians(yaw) + math.pi / 2)
    co.parent = root
    crawl_roots.append((root, co))
print("crawlers tris", total_tris())

# --------------------------------------------------------------------------- the driver (weak point)
dst = {"variant": 90, "mul": (1.0, 0.8, 0.5), "frost": 0.3, "dirt": 0.6, "blood": 0.7}
d = Person("rimebound_miner", "drv", seed=77, cloth_style=dst, skin_style={"frost": 0.25, "blood": 0.85, "livid": 0.5, "bruise": 0.6})
d.head_morph(stretch=0.1, jaw=0.9, mouth_cut=0.012)
d.add_eyes(M["eye_dead"], 1.1)
tb = MeshBuilder("th")
add_blob(tb, d.mouth + Vector((0, 0.03, -0.018)), (0.034, 0.045, 0.04), seg=10, rings=6)
d.add_part(tb.build([M["mouth_dark"]]), "throat", "head")
d.pose([("spine_01", "X", -4), ("spine_03", "X", -10), ("neck_01", "X", -20), ("head", "X", -32),
        ("upperarm_l", "Y", -150), ("upperarm_r", "Y", 150), ("upperarm_l", "X", -35), ("upperarm_r", "X", -35),
        ("lowerarm_l", "X", -35), ("lowerarm_r", "X", -35)])
chest_local = Vector(d.arm.pose.bones["spine_03"].head)
d.mark("m_lower", ["thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r", "ball_l", "ball_r"])
# stand the torso in the cab, waist below the crown floor
HEART = Vector((0, -0.38, 3.25))
Md = Matrix.Translation(HEART) @ Matrix.Rotation(math.radians(8), 4, 'X') @ Matrix.Translation(-(chest_local + Vector((0, 0, 0.08))))
dres = finalize_person(d, Md, dec={"body": 0.35, "hair": 0.4, "default": 0.4}, vcol_fn=vcol_grime(axis=(0, 0), r0=10, r1=20, dark=0.9), select="m_lower", thr=0.5,
                       invert=True, name="drv")
# torn-open chest: wet flesh, hole in the shirt, ribs, glowing heart cavity, sinew strands
ctr = Md @ (chest_local + Vector((0, -0.09, 0.0)))
print("driver chest world", ctr)
ribs, heart, strands = open_chest(dres, ctr, wet, M["bone"], heart_glow, strands=14, rng=rng)
drv_parts = list(dres.values()) + [ribs, heart, strands]
Driver = join(drv_parts, "Driver")
origin_to(Driver, ctr + Vector((0, 0.0, 0.0)))

# the cab: rusted rollover frame + dashboard + steering wheel, bent and iced
cb = MeshBuilder("Cab")
rust = M["rust"]
cc = CROWN
for sx in (-1, 1):
    add_tube(cb, [Vector((sx * 0.85, -0.55, cc.z - 0.55)), Vector((sx * 0.8, -0.62, cc.z + 0.45)), Vector((sx * 0.62, -0.7, cc.z + 1.0)), Vector((sx * 0.1, -0.6, cc.z + 1.25))],
             [0.045, 0.04, 0.04, 0.04], sides=6, mat_index=0)
add_tube(cb, [Vector((-0.85, 0.15, cc.z - 0.5)), Vector((-0.8, 0.2, cc.z + 0.5)), Vector((0.7, 0.2, cc.z + 0.9)), Vector((0.85, 0.15, cc.z - 0.5))], 0.04, sides=6, mat_index=0)
add_tube(cb, [Vector((-0.85, -0.55, cc.z + 0.2)), Vector((0.85, -0.55, cc.z + 0.2))], 0.035, sides=6, mat_index=0)
# floor plate and dashboard
add_blob(cb, Vector((0, -0.2, cc.z - 0.6)), (0.95, 0.75, 0.07), seg=12, rings=4, noise_amp=0.1, mat_index=0)
add_blob(cb, Vector((0, -0.85, cc.z - 0.1)), (0.7, 0.12, 0.28), seg=10, rings=6, noise_amp=0.15, mat_index=0)
for k in range(5):
    sx = rng.uniform(-0.8, 0.8)
    add_crystal(cb, Vector((sx, -0.6, cc.z + rng.uniform(-0.3, 1.0))), Vector((sx * 0.3, -0.5, 1)), rng.uniform(0.2, 0.5), 0.03, rng=rng, mat_index=1)
cab = cb.build([rust, M["ice"]])
ensure_col(cab); shade_smooth(cab)
# lamp on the cab
lb = MeshBuilder("Lamp")
add_blob(lb, Vector((0.78, -0.62, cc.z + 0.98)), (0.1, 0.1, 0.09), seg=8, rings=6)
lamp = lb.build([make_mat("glow_lamp", color=(1, 0.85, 0.5, 1), rough=0.3, emission=(1.0, 0.8, 0.45, 1), emit=8.0)])
ensure_col(lamp)
cab = join([cab, lamp], "Cab")

# --------------------------------------------------------------------------- mortar of fused flesh (metaballs) + props
elems = []
for k in range(18):
    f = k / 17.0
    y = -2.1 + 4.4 * f
    elems.append((Vector((0, y * 0.85, 1.2 + 0.3 * math.sin(f * 3.14))), 1.0, 2.0, (1.2, 1.0, 0.95)))
for k in range(16):
    th = rng.uniform(0, math.tau)
    ph = rng.uniform(0.3, 1.6)
    q = surface_point(th, ph) * 0.8 + BODY_C * 0.2
    elems.append((q * 0.9 + BODY_C * 0.1, rng.uniform(0.35, 0.55), 2.0, (1, 1, 1)))
elems.append((Vector((0, -0.3, 2.45)), 1.0, 2.0, (1.0, 1.0, 0.8)))
mortar = metaball_mesh("Mortar", elems, resolution=0.11, threshold=0.55, mat=flesh)
smooth_mesh(mortar, 3, 0.55)
displace_noise(mortar, 0.07, 2.4, seed=2.0, octaves=4)
decimate(mortar, min(1.0, 13000 / max(1, tri_count(mortar))))
uv_box(mortar, 0.5)
shade_smooth(mortar)
ensure_col(mortar)
set_vertex_color(mortar, vcol_flesh(seed=9, bloody=0.9))
print("mortar tris", tri_count(mortar))

props = []
# giant haul-truck tyre half sunk in the rear-left, crushed bumper plate
bpy.ops.mesh.primitive_torus_add(major_radius=1.15, minor_radius=0.48, major_segments=32, minor_segments=14, location=(-1.65, 1.7, 1.15), rotation=(math.radians(70), math.radians(18), math.radians(22)))
tire = bpy.context.view_layer.objects.active
tire.name = "Tire"
displace_noise(tire, 0.04, 3.0, seed=1.0, octaves=3)
tire.data.materials.append(rubber)
shade_smooth(tire)
ensure_col(tire)
props.append(tire)
# ore boulders
for k in range(9):
    ang = rng.uniform(0, math.tau)
    r = rng.uniform(0.25, 0.6)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=r, location=(math.cos(ang) * rng.uniform(1.9, 2.5), math.sin(ang) * rng.uniform(2.6, 3.2), r * 0.5))
    rk = bpy.context.view_layer.objects.active
    rk.scale = (1, rng.uniform(0.7, 1.2), rng.uniform(0.6, 1.0))
    displace_noise(rk, r * 0.35, 2.0, seed=k, octaves=3, ridged=True)
    rk.data.materials.append(rock)
    shade_smooth(rk)
    ensure_col(rk)
    props.append(rk)

# bones, boots and torn limbs sticking out (real tibias, broken ends, frost)
bb = MeshBuilder("Bones")
for k in range(10):
    th = rng.uniform(0, math.tau)
    ph = rng.uniform(0.5, 1.5)
    a = surface_point(th, ph)
    nrm = surface_normal(th, ph)
    d_ = nrm + Vector((rng.uniform(-0.4, 0.4), rng.uniform(-0.4, 0.4), rng.uniform(0, 0.5)))
    L = rng.uniform(0.5, 1.2)
    pts = [a + d_.normalized() * (L * j / 4.0) for j in range(5)]
    add_tube(bb, pts, [0.05, 0.035, 0.03, 0.035, 0.05 - 0.01], sides=7, mat_index=0, noise_amp=0.08)
    # jagged break
    tip = pts[-1]
    for _ in range(3):
        add_crystal(bb, tip, d_ + Vector((rng.uniform(-0.5, 0.5), rng.uniform(-0.5, 0.5), 0)), rng.uniform(0.06, 0.14), 0.014, sides=4, rng=rng, mat_index=0)
bones = bb.build([M["bone"]])
shade_smooth(bones); ensure_col(bones)
props.append(bones)

# --------------------------------------------------------------------------- ice + frozen blood
mb = MeshBuilder("Ice")
imats = [M["ice"], M["ice_deep"], M["ice_glow"], M["ice_blood"]]
spots = []
for _ in range(120):
    th = rng.uniform(0, math.tau)
    ph = rng.uniform(0.1, 1.9)
    spots.append((surface_point(th, ph) * 1.0, surface_normal(th, ph)))
scatter_crystals(mb, rng, spots, 40, length=(0.3, 1.1), radius=(0.03, 0.09), up_bias=0.4, spread=0.5, mat_index=0)
scatter_crystals(mb, rng, spots, 13, length=(0.7, 1.7), radius=(0.07, 0.14), up_bias=0.5, spread=0.4, mat_index=1)
scatter_crystals(mb, rng, spots[:30], 8, length=(0.3, 0.7), radius=(0.04, 0.08), up_bias=0.5, spread=0.4, mat_index=2)
# crown spikes around the cab
for k in range(10):
    ang = rng.uniform(0, math.tau)
    add_crystal(mb, CROWN + Vector((math.cos(ang) * 0.9, math.sin(ang) * 0.7, -0.6)), Vector((math.cos(ang) * 0.4, math.sin(ang) * 0.4, 1)), rng.uniform(0.7, 1.4), 0.06, rng=rng, mat_index=1)
# frozen blood icicles / drips hanging from the mound and crawlers
drip = [surface_point(rng.uniform(0, math.tau), rng.uniform(0.9, 1.6)) for _ in range(30)]
icicles(mb, rng, drip, 16, length=(0.25, 0.9), mat_index=3)
ice = mb.build(imats)
shade_smooth(ice); ensure_col(ice)

# --------------------------------------------------------------------------- assemble, hierarchy, export
bodyobj = join(people + [mortar] + props, "Body")
mass = empty("Mass", (0, 0, 0))
crown = empty("Crown", CROWN)
for ob in (bodyobj, ice):
    ob.parent = mass
for root, co in crawl_roots:
    root.parent = mass
for ob in (Driver, cab):      # the glTF exporter ignores parent-inverse: store the offset in the local location
    ob.parent = crown
    ob.matrix_parent_inverse = Matrix.Identity(4)
    ob.location = ob.location - CROWN
tris = export(os.path.join(OUT_DIR, "hauler.glb"))
