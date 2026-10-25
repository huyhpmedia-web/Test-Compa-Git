"""Materials, vertex-colour painters and prop builders shared by the boss build scripts."""
import math, random
from bosslib import *
import texgen


def std_mats():
    """the common material set (names are matched by actors/models/enemy_glb.gd)."""
    d = {}
    d["ice"] = make_mat("ice", color=(0.55, 0.68, 0.78, 1), rough=0.05, spec=1.0, alpha=0.36, emission=(0.2, 0.5, 0.65, 1), emit=0.05)
    d["ice_deep"] = make_mat("ice_deep", color=(0.22, 0.33, 0.45, 1), rough=0.05, spec=1.0, alpha=0.55, emission=(0.1, 0.3, 0.5, 1), emit=0.05)
    d["ice_glow"] = make_mat("ice_glow", color=(0.4, 0.65, 0.75, 1), rough=0.05, spec=1.0, alpha=0.5, emission=(0.3, 0.8, 1.0, 1), emit=0.7)
    d["ice_blood"] = make_mat("ice_blood", color=(0.09, 0.008, 0.01, 1), rough=0.06, spec=1.0, alpha=0.92, emission=(0.1, 0.0, 0.0, 1), emit=0.0)
    d["ice_glaze"] = make_mat("ice_glaze", color=(0.7, 0.82, 0.9, 1), rough=0.05, spec=1.0, alpha=0.16, emission=(0.2, 0.5, 0.7, 1), emit=0.03)
    d["blood"] = make_mat("blood", color=(0.1, 0.008, 0.01, 1), rough=0.12, spec=0.9, coat=1.0, coat_rough=0.04)
    d["frost"] = make_mat("frost", color=(0.86, 0.92, 0.98, 1), rough=0.55, spec=0.5)
    d["throat_glow"] = make_mat("throat_glow", color=(0.2, 0.5, 0.6, 1), rough=0.4, emission=(0.5, 0.95, 1.0, 1), emit=4.0)
    d["mouth_dark"] = make_mat("mouth_dark", color=(0.02, 0.0, 0.01, 1), rough=0.9)
    d["eye_dead"] = make_mat("eye_dead", color=(0.78, 0.84, 0.9, 1), rough=0.12, spec=0.9)
    d["eye_glow"] = make_mat("glow_eye", color=(0.3, 0.7, 0.8, 1), rough=0.3, emission=(0.5, 0.95, 1.0, 1), emit=9.0)
    d["bone"] = make_mat("bone", color=(0.78, 0.74, 0.62, 1), rough=0.55, spec=0.5)
    d["rust"] = make_mat("rust", color=(0.30, 0.15, 0.09, 1), rough=0.8, metal=0.5)
    d["iron"] = make_mat("iron", color=(0.14, 0.14, 0.16, 1), rough=0.5, metal=0.85)
    return d


_flesh = {}


def flesh_mat(name="flesh_mortar", seed=5, rough=0.45):
    """fused-flesh material using a generated mottled texture + vertex colour; wet-looking."""
    if name in MATS:
        return MATS[name]
    p = os.path.join(CACHE, "tex", f"{name}_{seed}.jpg")
    if not os.path.exists(p):
        texgen.flesh_tex(p, seed=seed)
    return make_mat(name, tex=p, rough=rough, spec=0.6, coat=0.35, coat_rough=0.12, sss=0.1)


def smoothstep(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a + 1e-9)))
    return t * t * (3 - 2 * t)


def vcol_grime(axis=(0, 0), r0=0.35, r1=0.95, dark=0.7, seed=0, blue=0.1):
    """vertex colour: darker near the column core / low down + low-frequency blotches."""
    def fn(co, n, i):
        r = math.hypot(co.x - axis[0], co.y - axis[1])
        k = 1.0 - (1.0 - dark) * (1.0 - smoothstep(r0, r1, r))
        nz = 0.5 + 0.5 * noise.noise(co * 2.3 + Vector((seed, 0, 0)))
        k *= 0.7 + 0.3 * nz
        c = max(0.0, min(1.0, k))
        return (c * (1 - blue), c * (1 - blue * 0.4), c, 1.0)
    return fn


def vcol_flesh(seed=0, bloody=0.5):
    """mottled colours for sculpted flesh: blue-grey / pink / blood red with frost on upward faces."""
    cols = [(0.7, 0.58, 0.6), (0.75, 0.42, 0.44), (0.32, 0.05, 0.06), (0.42, 0.4, 0.5)]
    def fn(co, n, i):
        a = 0.5 + 0.5 * noise.noise(co * 1.7 + Vector((seed, 1.0, 0)))
        b = 0.5 + 0.5 * noise.noise(co * 4.1 + Vector((0, seed, 2.0)))
        c0 = Vector(cols[0]).lerp(Vector(cols[1]), a)
        t = smoothstep(0.55, 0.8, b) * bloody
        c0 = c0.lerp(Vector(cols[2]), t)
        c0 = c0.lerp(Vector(cols[3]), smoothstep(0.25, 0.1, a) * 0.6)
        # frost on top-facing surfaces
        up = max(0.0, n.z)
        f = smoothstep(0.55, 0.95, up * (0.6 + 0.6 * a))
        c0 = c0.lerp(Vector((1.0, 1.0, 1.0)), f * 0.65)
        return (c0.x, c0.y, c0.z, 1.0)
    return fn


def scatter_crystals(mb, rng, spots, count, length=(0.3, 1.0), radius=(0.03, 0.09), up_bias=0.6, spread=0.5, mat_index=0, color=(1, 1, 1, 1)):
    """spots: list of (position, outward normal) - crystal clusters growing from them."""
    for _ in range(count):
        pos, nrm = rng.choice(spots)
        d = Vector(nrm) * (1 - up_bias) + Vector((0, 0, 1)) * up_bias
        d += Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * spread
        if d.length < 0.01:
            d = Vector((0, 0, 1))
        add_crystal(mb, Vector(pos) - d.normalized() * 0.02, d, rng.uniform(*length), rng.uniform(*radius), rng=rng, mat_index=mat_index, color=color)


def icicles(mb, rng, points, count, length=(0.15, 0.7), radius=(0.012, 0.035), mat_index=0):
    """hanging icicles / frozen blood drips from the given points."""
    for _ in range(count):
        p = rng.choice(points)
        L = rng.uniform(*length)
        add_crystal(mb, p, Vector((rng.uniform(-0.15, 0.15), rng.uniform(-0.15, 0.15), -1)), L, rng.uniform(*radius), sides=5, tip=0.55,
                    rng=rng, mat_index=mat_index, taper=0.5)


def person_matrix(pos, yaw_out_deg, lean_deg, pivot_local, scale=1.0, roll_deg=0.0):
    """world matrix for a person authored standing at origin facing -Y: pivot (a local point) is placed at `pos`;
    yaw_out_deg is the direction (in the XY plane, from +X) the person faces; lean_deg > 0 leans back."""
    th = math.radians(yaw_out_deg) + math.pi / 2
    M = Matrix.Translation(pos) @ Matrix.Rotation(th, 4, 'Z') @ Matrix.Rotation(math.radians(roll_deg), 4, 'Y') \
        @ Matrix.Rotation(math.radians(-lean_deg), 4, 'X') @ Matrix.Scale(scale, 4) @ Matrix.Translation(-Vector(pivot_local))
    return M


def throat(mat, center, radii, M, name):
    """closed ellipsoid used behind an open mouth (dark or glowing)."""
    mb = MeshBuilder(name)
    add_blob(mb, center, radii, seg=10, rings=6)
    ob = mb.build([mat])
    ob.data.transform(M)
    return ob


def open_chest(res, ctr, wet, bone, glow, rx=0.13, rz=0.19, strands=14, rng=None, glow_scale=1.0):
    """Tear open the chest of a baked person (front = -Y): wet raw flesh on the body faces around `ctr`, a hole in the
    clothing, ribs, strand-like sinew, and a glowing heart cavity.  `res` = {role: obj} from finalize_person (modified in
    place).  Returns the new objects (ribs, heart, strands) - heart is the glowing blob."""
    rng = rng or random.Random(3)
    body = res["body"]
    body.data.materials.append(wet)
    widx = len(body.data.materials) - 1
    for f in body.data.polygons:
        q = body.matrix_world @ f.center - ctr
        if (q.x / rx) ** 2 + (q.z / rz) ** 2 + (q.y / 0.2) ** 2 < 1.0 and q.y < 0.04:
            f.material_index = widx
    for role, ob in list(res.items()):
        if role in ("shirt", "overalls", "top", "uniform", "cardigan", "jacket", "parka", "hoodie", "coat"):
            bm = bmesh.new(); bm.from_mesh(ob.data); bm.faces.ensure_lookup_table()
            kill = [f for f in bm.faces if (lambda q: (q.x / (rx * 1.25)) ** 2 + (q.z / (rz * 1.15)) ** 2 + (q.y / 0.25) ** 2 < 1.0 and q.y < 0.05)(f.calc_center_median() - ctr)]
            bmesh.ops.delete(bm, geom=kill, context='FACES')
            bm.to_mesh(ob.data); bm.free()
    rb = MeshBuilder("ribs")
    for k in range(5):
        z = ctr.z + 0.09 - k * 0.045
        for sx in (-1, 1):
            pts = []
            for j in range(9):
                a = j / 8.0
                pts.append(Vector((ctr.x + sx * (0.02 + 0.09 * a), ctr.y - 0.015 + 0.10 * a - 0.04 * math.sin(a * 3.0), z - 0.02 * a)))
            add_tube(rb, pts, [0.009 - 0.004 * (j / 8.0) for j in range(9)], sides=6, mat_index=0)
    ribs = rb.build([bone])
    hb = MeshBuilder("Heart")
    add_blob(hb, ctr + Vector((0, 0.04, 0.0)), (0.07 * glow_scale, 0.05 * glow_scale, 0.085 * glow_scale), seg=10, rings=8, noise_amp=0.2)
    heart = hb.build([glow])
    sb = MeshBuilder("strands")
    for k in range(strands):
        a0 = ctr + Vector((rng.uniform(-0.1, 0.1), -0.02, rng.uniform(-0.14, 0.12)))
        pts = [a0 + Vector((rng.uniform(-0.03, 0.03) * j, -0.03 * j, -0.02 * j * rng.uniform(0.5, 2))) for j in range(5)]
        add_tube(sb, pts, [0.012, 0.011, 0.009, 0.007, 0.004], sides=5, mat_index=0, color=(0.9, 0.3, 0.3, 1))
    strands_o = sb.build([wet])
    for ob in (ribs, heart, strands_o):
        ensure_col(ob)
        shade_smooth(ob)
    return ribs, heart, strands_o
