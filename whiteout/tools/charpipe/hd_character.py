"""Generic HD character: put ANY realistic humanoid mesh (glb) onto the game's MPFB 'game_engine' skeleton.

  venv/bin/python -I tools/charpipe/hd_character.py <src.glb> <rig.blend> <out.glb> [options]

  rig.blend   armature-only file of the target character (tools/charpipe/anim_rigfile.py <model> <out.blend>); its rest bones,
              names and hierarchy are what ships, so assets/anims/*.glb, weapon IK, finger curls and the gore bone hooks keep working.

Sources handled (pose-free, the source rig is optional):
  * unrigged A-/T-pose meshes (most Sketchfab scans/zombies): orientation (facing / arm axis), scale by height and the joints
    (shoulders, elbows, wrists, hips, knees, ankles) are estimated from the mesh itself;
  * rigged sources (Mixamo-style "mixamorig:LeftArm", or any rig with --source-rig map.json {"upperarm_l": "SrcBoneName", ...}):
    the source rig's joint positions are used instead of the estimates; the source skin weights are ignored (bone heat is used).
How: build a copy of the MPFB rig "fitted" to the source pose (arms/legs rotated onto the mesh limbs), voxel-remesh a watertight
proxy, bone-heat weights on the proxy, nearest-surface transfer to the real mesh, then pose the fitted rig back onto the real MPFB
rest bones and bake (armature modifier applied) so the mesh now lies in the MPFB rest pose, parented to the unmodified MPFB rig.

Options:
  --height H        total height of the output (default: head-bone tail z of the rig)
  --tag NAME        material prefix (default: out file stem);  --mat "Body=skin,Hair=hair,Clothes=suit"  rename source materials to <tag>_<x>
  --drop a,b        mesh object names (substring) to discard
  --tex N           max texture size (default 1024)
  --face +y|-y|auto force the source facing axis (Blender frame after glb import; auto detects from the feet)
  --voxel V         proxy voxel size (default 0.012)
  --flipx           mirror the source in X (rare)
  --decimate N      target triangles for the final mesh (default: keep)
  --report          print landmark estimates
"""
import sys, os, math, json, argparse
import bpy, bmesh
import numpy as np
from mathutils import Vector, Matrix, Quaternion

ap = argparse.ArgumentParser()
ap.add_argument("src"); ap.add_argument("rig"); ap.add_argument("out")
ap.add_argument("--source-rig", default=None)
ap.add_argument("--height", type=float, default=None)
ap.add_argument("--tag", default=None)
ap.add_argument("--mat", default="")
ap.add_argument("--drop", default="")
ap.add_argument("--tex", type=int, default=1024)
ap.add_argument("--face", default="auto")
ap.add_argument("--voxel", type=float, default=0.012)
ap.add_argument("--flipx", action="store_true")
ap.add_argument("--decimate", type=int, default=0)
ap.add_argument("--min-rough", type=float, default=0.62)
ap.add_argument("--forearm-bend", type=float, default=0.0)
args = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
tag = args.tag or os.path.splitext(os.path.basename(args.out))[0]


def log(*a):
    print("[hd]", *a, flush=True)


# ------------------------------------------------------------------ MPFB rest skeleton
bpy.ops.wm.open_mainfile(filepath=args.rig)
rig = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
rig.name = tag + "_rig"
ROOT = {b.name: b.parent.name if b.parent else None for b in rig.data.bones}
H = {b.name: Vector(b.head_local) for b in rig.data.bones}
T = {b.name: Vector(b.tail_local) for b in rig.data.bones}
M0 = {b.name: b.matrix_local.copy() for b in rig.data.bones}
ORDER = [b.name for b in rig.data.bones]          # parents first
top_z = args.height or T["head"].z
log("rig height", top_z)

# ------------------------------------------------------------------ import the source
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=args.src)
new = [o for o in bpy.data.objects if o not in before]
sarms = [o for o in new if o.type == "ARMATURE"]
for a in bpy.data.actions:            # no imported clip may drive the pose
    pass
for sa in sarms:
    if sa.animation_data:
        sa.animation_data.action = None
    for pb in sa.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
bpy.context.view_layer.update()

# source rig joints (world, before any transform) by name heuristics or an explicit map
SRC = {}
if sarms:
    sa = sarms[0]
    wm = sa.matrix_world
    explicit = json.load(open(args.source_rig)) if args.source_rig else {}

    def norm(n):
        n = n.split(":")[-1].lower().replace("_", "").replace(".", "").replace("-", "")
        return "".join(c for c in n if not c.isdigit()) if n[-2:].isdigit() else n

    byn = {}
    for b in sa.pose.bones:
        byn.setdefault(norm(b.name), b)
    def sb(key, *cands):
        if key in explicit:
            return sa.pose.bones.get(explicit[key])
        for c in cands:
            if c in byn: return byn[c]
        return None
    for side, sd in (("l", "left"), ("r", "right")):
        pairs = {"upperarm": sb("upperarm_" + side, sd + "arm", "upperarm" + side, "arm" + side, sd + "upperarm"),
                 "lowerarm": sb("lowerarm_" + side, sd + "forearm", "forearm" + side, "lowerarm" + side),
                 "hand": sb("hand_" + side, sd + "hand", "hand" + side),
                 "thigh": sb("thigh_" + side, sd + "upleg", "thigh" + side, "upleg" + side, sd + "upperleg"),
                 "calf": sb("calf_" + side, sd + "leg", "calf" + side, "shin" + side, sd + "lowerleg"),
                 "foot": sb("foot_" + side, sd + "foot", "foot" + side)}
        for k, b in pairs.items():
            if b is not None:
                SRC[k + "_" + side] = (wm @ b.head, wm @ b.tail)
    hd = sb("head", "head"); hp = sb("pelvis", "hips", "pelvis")
    if hd: SRC["head"] = (wm @ hd.head, wm @ hd.tail)
    if hp: SRC["pelvis"] = (wm @ hp.head, wm @ hp.tail)
    log("source rig joints:", sorted(SRC))

# meshes: drop junk, bake the pose-less skin (armature modifiers removed -> rest/bind pose), join
drop = [d for d in args.drop.split(",") if d]
meshes = []
for o in new:
    if o.type != "MESH":
        continue
    if any(d in o.name for d in drop):
        bpy.data.objects.remove(o); continue
    meshes.append(o)
for o in meshes:
    for m in list(o.modifiers):
        if m.type == "ARMATURE":          # the glb mesh is stored in bind pose already: just drop the skin
            o.modifiers.remove(m)
    if o.data.shape_keys:
        o.shape_key_clear()
    mw = o.matrix_world.copy()
    o.parent = None
    o.data.transform(mw)
    o.matrix_world = Matrix.Identity(4)
    o.vertex_groups.clear()
for o in list(bpy.data.objects):
    if o.type != "MESH" and o not in (rig,):
        bpy.data.objects.remove(o)
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
mesh = bpy.context.view_layer.objects.active
mesh.name = tag
for o in mesh.data.shape_keys.key_blocks if mesh.data.shape_keys else []:
    pass


# ------------------------------------------------------------------ normalise: z-up, feet on z=0, lateral axis = X, facing -Y, scale
def verts():
    n = len(mesh.data.vertices)
    a = np.empty(n * 3, dtype=np.float64)
    mesh.data.vertices.foreach_get("co", a)
    return a.reshape(n, 3)

def put_verts(v):
    mesh.data.vertices.foreach_set("co", v.astype(np.float32).reshape(-1))
    mesh.data.update()

V = verts()
def xform(Mx):
    global V
    mesh.data.transform(Mx)
    for k in SRC:
        SRC[k] = (Mx @ SRC[k][0], Mx @ SRC[k][1])
    V = verts()

if args.flipx:
    xform(Matrix.Scale(-1, 4, Vector((1, 0, 0))))
    mesh.data.flip_normals() if hasattr(mesh.data, "flip_normals") else None
# lateral axis: arms spread -> wider in X than Y. rotate 90 deg if not
ext = V.max(0) - V.min(0)
if ext[1] > ext[0] * 1.15:
    xform(Matrix.Rotation(math.radians(90), 4, "Z"))
# put feet on the floor, and scale to the target height
V = verts()
zmin, zmax = V[:, 2].min(), V[:, 2].max()
h0 = zmax - zmin
s = top_z / h0
xform(Matrix.Scale(s, 4) @ Matrix.Translation((0, 0, -zmin)))
log("source height", h0, "scale", s)
V = verts()
Hh = V[:, 2].max()
# facing: feet protrude forward of the ankle. compare the foot slice's y extent around the leg slice (z ~ 0.3H)
foot = V[V[:, 2] < 0.05 * Hh]; shin = V[(V[:, 2] > 0.25 * Hh) & (V[:, 2] < 0.35 * Hh)]
dy = foot[:, 1].mean() - shin[:, 1].mean()
dy_ext = (foot[:, 1].max() - shin[:, 1].max()) + (foot[:, 1].min() - shin[:, 1].min())
face_neg = (dy_ext < 0) if args.face == "auto" else (args.face == "-y")
log("foot dy", dy, "ext", dy_ext, "faces -Y" if face_neg else "faces +Y -> rotate 180")
if not face_neg:
    xform(Matrix.Rotation(math.pi, 4, "Z"))
# center: x on the median of the torso, y so the hip-level slice centre sits on the rig pelvis
V = verts()
hipband = V[(V[:, 2] > 0.50 * Hh) & (V[:, 2] < 0.58 * Hh)]
cx = 0.5 * (hipband[:, 0].min() + hipband[:, 0].max())
cy = 0.5 * (hipband[:, 1].min() + hipband[:, 1].max())
xform(Matrix.Translation((-cx, H["pelvis"].y - cy, 0)))
V = verts()

# ------------------------------------------------------------------ landmark estimation on the (T/A-pose) mesh
def side_pts(sign, zlo, zhi, xmin_frac=0.0):
    m = (V[:, 2] > zlo * Hh) & (V[:, 2] < zhi * Hh) & (V[:, 0] * sign > xmin_frac * Hh)
    return V[m]

# arm height / tips: look at the outermost 8% of the x extent
xmax = V[:, 0].max(); xmin = V[:, 0].min()
L = {}
for sign, sd in ((1, "l"), (-1, "r")):
    edge = xmax if sign > 0 else xmin
    tipv = V[(V[:, 0] - edge) * sign > -0.05 * Hh]
    tip = Vector(tipv.mean(0))
    # shoulder: torso half width under the arm; pick the chest slice a bit below the arm
    za = tip.z
    chest = V[(V[:, 2] > za - 0.16 * Hh) & (V[:, 2] < za - 0.10 * Hh)]
    chest = chest[np.abs(chest[:, 0]) < 0.30 * Hh]
    tw = np.percentile(np.abs(chest[:, 0]), 96) if len(chest) else 0.19 * Hh
    sx = sign * min(max(tw * 0.88, 0.12 * Hh * 0.8), 0.2 * Hh)
    # shoulder y: the body centre line at that height
    sl = V[(np.abs(V[:, 2] - za) < 0.03 * Hh) & (np.abs(V[:, 0]) < abs(sx))]
    sy = 0.5 * (sl[:, 1].min() + sl[:, 1].max()) if len(sl) else H["upperarm_l"].y
    if za < 0.72 * Hh:       # arms hanging down: shoulder from the rig proportions, tip = hand centre
        rs = H["upperarm_" + sd]
        sx = sign * abs(rs.x); sy = rs.y; za = rs.z
        hand = V[(V[:, 2] < 0.62 * Hh) & (V[:, 2] > 0.30 * Hh) & ((V[:, 0] - edge) * sign > -0.06 * Hh)]
        if len(hand): tip = Vector(hand.mean(0)) + Vector((0, 0, -0.06 * Hh))
        log("arms-down source", sd, tip)
    L["tip_" + sd] = tip; L["sh_" + sd] = Vector((sx, sy, za + 0.0))
    # legs
    fl = V[(V[:, 2] < 0.05 * Hh) & (V[:, 0] * sign > 0.01)]
    L["foot_" + sd] = Vector(fl.mean(0)) if len(fl) else Vector((sign * 0.1, 0, 0.02))
    L["toe_" + sd] = Vector((fl[:, 0].mean(), (fl[:, 1].min() if face_neg or True else fl[:, 1].max()), 0.02)) if len(fl) else L["foot_" + sd]
# crotch height: highest z (below 0.6H) at which the central strip x~0 holds no vertices
cz = 0.47 * Hh
for zf in np.arange(0.30, 0.60, 0.005):
    band = V[(V[:, 2] > (zf - 0.01) * Hh) & (V[:, 2] < zf * Hh)]
    if (np.abs(band[:, 0]) < 0.02 * Hh).sum() > 12:
        cz = zf * Hh; break
log("arm height", L["tip_l"].z, "shoulder", L["sh_l"], "tip", L["tip_l"], "crotch z", cz)

# ------------------------------------------------------------------ fitted rig: MPFB bones moved onto the source pose
def arc(a, b):
    a = a.normalized(); b = b.normalized()
    return a.rotation_difference(b)

fit = {}      # name -> (head, tail, rotation Quaternion applied to the orig bone axes)
for n in ORDER:
    fit[n] = [H[n].copy(), T[n].copy(), Quaternion()]
CH_ARM = lambda sd: ["upperarm_" + sd, "lowerarm_" + sd, "hand_" + sd]
def subtree(n):
    out = [n]
    for c in ORDER:
        if ROOT[c] == n:
            out += subtree(c)
    return out

# global z-fit for the spine chain: pelvis/hip at the crotch-derived height
hip_z = cz + 0.045 * Hh
for sd, sign in (("l", 1), ("r", -1)):
    ua, la, ha = CH_ARM(sd)
    sh = L["sh_" + sd]
    tip = L["tip_" + sd]
    if "upperarm_" + sd in SRC:
        sh = SRC["upperarm_" + sd][0]; tip_w = SRC["hand_" + sd][1] if "hand_" + sd in SRC else tip
    d_arm = (tip - sh).normalized()
    Lu = (T[ua] - H[ua]).length; Ll = (T[la] - H[la]).length; Lh = (T[ha] - H[ha]).length
    # straight arm along the mesh arm axis (elbow bend is restored by the pose-back)
    el = sh + d_arm * Lu
    if "lowerarm_" + sd in SRC:
        el = SRC["lowerarm_" + sd][0]
    wr = el + d_arm * Ll
    if "hand_" + sd in SRC:
        wr = SRC["hand_" + sd][0]
    # clavicle: spine_03 head stays, tail goes to the shoulder
    cl = "clavicle_" + sd
    fit[cl][1] = sh.copy(); fit[cl][2] = arc(T[cl] - H[cl], sh - H[cl])
    fit[ua][0] = sh.copy(); fit[ua][1] = el.copy(); fit[ua][2] = arc(T[ua] - H[ua], el - sh)
    fit[la][0] = el.copy(); fit[la][1] = wr.copy(); fit[la][2] = arc(T[la] - H[la], wr - el)
    qh = arc(T[ha] - H[ha], d_arm)
    fit[ha][0] = wr.copy(); fit[ha][1] = wr + d_arm * Lh; fit[ha][2] = qh
    for c in subtree(ha)[1:]:
        fit[c][0] = wr + qh @ (H[c] - H[ha]); fit[c][1] = wr + qh @ (T[c] - H[ha]); fit[c][2] = qh
    # legs: hip joint x/y from the rig pelvis line but z at the crotch-derived height; ankle above the foot centroid
    th, ca, ft, bl = "thigh_" + sd, "calf_" + sd, "foot_" + sd, "ball_" + sd
    hip = Vector((H[th].x, H[th].y, hip_z))
    fc = L["foot_" + sd]
    ankle = Vector((fc.x, fc.y + 0.02 * Hh, H[ft].z))
    if "foot_" + sd in SRC:
        ankle = SRC["foot_" + sd][0]; hip = SRC["thigh_" + sd][0] if "thigh_" + sd in SRC else hip
    hip.x = hip.x * 0.5 + (hip.x if abs(fc.x) < 1e-3 else math.copysign(min(abs(hip.x), abs(fc.x)), fc.x)) * 0.5
    knee = (hip + ankle) * 0.5
    if "calf_" + sd in SRC:
        knee = SRC["calf_" + sd][0]
    toe = L["toe_" + sd]
    ball = Vector((ankle.x, toe.y + 0.03, H[bl].z if bl in H else 0.01)) if True else None
    ball_t = Vector((ankle.x, ball.y - 0.07, ball.z))
    # the real foot bone goes ankle -> ball; keep the orig lengths flexible
    fit[th][0] = hip; fit[th][1] = knee; fit[th][2] = arc(T[th] - H[th], knee - hip)
    fit[ca][0] = knee; fit[ca][1] = ankle; fit[ca][2] = arc(T[ca] - H[ca], ankle - knee)
    fit[ft][0] = ankle; fit[ft][1] = ball; fit[ft][2] = arc(T[ft] - H[ft], ball - ankle)
    if bl in fit:
        fit[bl][0] = ball; fit[bl][1] = ball_t; fit[bl][2] = arc(T[bl] - H[bl], ball_t - ball)
# pelvis / spine: translate pelvis head to hip height blend (only the pelvis bone, spine kept)
dz = hip_z - H["thigh_l"].z
fit["pelvis"][0] = H["pelvis"] + Vector((0, 0, dz * 0.6))
fit["pelvis"][1] = T["pelvis"] + Vector((0, 0, dz * 0.4))
fit["spine_01"][0] = fit["pelvis"][1].copy()

# ------------------------------------------------------------------ build the fitted armature (copy of the MPFB rig, edited)
bpy.ops.object.select_all(action="DESELECT")
rig_fit = rig.copy(); rig_fit.data = rig.data.copy(); rig_fit.name = tag + "_fit"
bpy.context.collection.objects.link(rig_fit)
bpy.context.view_layer.objects.active = rig_fit
rig_fit.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
eb = rig_fit.data.edit_bones
for n in ORDER:
    e = eb[n]
    h, t, q = fit[n]
    e.use_connect = False
for n in ORDER:
    e = eb[n]
    h, t, q = fit[n]
    R3 = (q.to_matrix().to_4x4() @ M0[n].to_3x3().to_4x4())
    ln = max((t - h).length, 1e-3)
    e.head = h
    e.tail = h + (R3.to_3x3() @ Vector((0, 1, 0))) * ln
    # roll: align bone z axis with the rotated original z axis
    e.align_roll(R3.to_3x3() @ Vector((0, 0, 1)))
bpy.ops.object.mode_set(mode="OBJECT")

# ------------------------------------------------------------------ weights: voxel proxy + bone heat on the fitted rig, nearest-surface transfer
bpy.ops.object.select_all(action="DESELECT")
bpy.context.view_layer.objects.active = mesh
mesh.select_set(True)
proxy = mesh.copy(); proxy.data = mesh.data.copy(); proxy.name = "weight_proxy"
proxy.data.materials.clear()
bpy.context.collection.objects.link(proxy)
rm = proxy.modifiers.new("vox", "REMESH")
rm.mode = "VOXEL"; rm.voxel_size = args.voxel
bpy.ops.object.select_all(action="DESELECT")
proxy.select_set(True); bpy.context.view_layer.objects.active = proxy
bpy.ops.object.modifier_apply(modifier="vox")
dec = proxy.modifiers.new("dec", "DECIMATE"); dec.ratio = min(1.0, 80000 / max(1, len(proxy.data.polygons)))
bpy.ops.object.modifier_apply(modifier="dec")
log("proxy faces", len(proxy.data.polygons))
bpy.ops.object.select_all(action="DESELECT")
proxy.select_set(True); rig_fit.select_set(True); bpy.context.view_layer.objects.active = rig_fit
bpy.ops.object.parent_set(type="ARMATURE_AUTO")
unw = sum(1 for v in proxy.data.vertices if len(v.groups) == 0)
log("proxy unweighted:", unw, "/", len(proxy.data.vertices))
for g in proxy.vertex_groups:
    mesh.vertex_groups.new(name=g.name)
dt = mesh.modifiers.new("dt", "DATA_TRANSFER")
dt.object = proxy; dt.use_vert_data = True
dt.data_types_verts = {"VGROUP_WEIGHTS"}; dt.vert_mapping = "POLYINTERP_NEAREST"
dt.layers_vgroup_select_src = "ALL"; dt.layers_vgroup_select_dst = "NAME"
bpy.ops.object.select_all(action="DESELECT")
mesh.select_set(True); bpy.context.view_layer.objects.active = mesh
bpy.ops.object.modifier_apply(modifier="dt")
bpy.data.objects.remove(proxy)
nun = sum(1 for v in mesh.data.vertices if len(v.groups) == 0)
log("mesh unweighted:", nun)
if nun > 0.02 * len(mesh.data.vertices) or unw > 0.02 * len(mesh.data.vertices):
    log("bone heat failed -> distance weights")
    mesh.vertex_groups.clear()
    Vv = verts()
    names = [n for n in ORDER if n != "Root"]
    D = np.empty((len(Vv), len(names)))
    for j, n in enumerate(names):
        a_, b_ = np.array(fit[n][0]), np.array(fit[n][1])
        ab = b_ - a_; t = np.clip(((Vv - a_) @ ab) / max(ab @ ab, 1e-9), 0, 1)
        D[:, j] = np.linalg.norm(Vv - (a_ + t[:, None] * ab), axis=1)
    # finger bones are tiny: let them take weight only close to them (distance already handles it)
    W = 1.0 / np.maximum(D, 0.004) ** 3
    idx = np.argsort(-W, axis=1)[:, :4]
    vg = {n: mesh.vertex_groups.new(name=n) for n in names}
    for i in range(len(Vv)):
        tot = W[i, idx[i]].sum()
        for j in idx[i]:
            vg[names[j]].add([i], float(W[i, j] / tot), "REPLACE")
bpy.ops.object.mode_set(mode="WEIGHT_PAINT")
bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
bpy.ops.object.mode_set(mode="OBJECT")

if os.environ.get("HD_DEBUG"):
    from collections import Counter
    c = Counter()
    for v in mesh.data.vertices:
        if abs(v.co.x) > 0.5 and v.groups:
            g = max(v.groups, key=lambda g: g.weight); c[mesh.vertex_groups[g.group].name] += 1
    log("far-x dominant groups", c.most_common(8))
# ------------------------------------------------------------------ pose the fitted rig onto the MPFB rest bones, bake
mesh.parent = rig_fit
am = mesh.modifiers.new("Armature", "ARMATURE"); am.object = rig_fit
bpy.context.view_layer.objects.active = rig_fit
bpy.ops.object.mode_set(mode="POSE")
for n in ORDER:
    pb = rig_fit.pose.bones[n]
    pb.matrix = M0[n]
    bpy.context.view_layer.update()
    if n in ("upperarm_l", "hand_l", "foot_l"):
        log("pose", n, (rig_fit.matrix_world @ pb.head - H[n]).length)
bpy.ops.object.mode_set(mode="OBJECT")
bpy.context.view_layer.objects.active = mesh
bpy.ops.object.select_all(action="DESELECT"); mesh.select_set(True)
bpy.ops.object.modifier_apply(modifier="Armature")
mesh.parent = None
bpy.data.objects.remove(rig_fit)
V = verts()
log("final bbox z", V[:, 2].min(), V[:, 2].max(), "x", V[:, 0].min(), V[:, 0].max(), "y", V[:, 1].min(), V[:, 1].max())

# ------------------------------------------------------------------ cleanup: decimate, materials, textures
mesh.data.polygons.foreach_set("use_smooth", [True] * len(mesh.data.polygons))
if args.decimate and len(mesh.data.polygons) > args.decimate:
    d = mesh.modifiers.new("dec", "DECIMATE"); d.ratio = args.decimate / len(mesh.data.polygons)
    d.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier="dec")
done_rough = set()
ren = dict(kv.split("=") for kv in args.mat.split(",") if "=" in kv)
for i, m in enumerate(mesh.data.materials):
    if m is None:
        continue
    key = next((k for k in ren if k.lower() == m.name.lower().split(".")[0]), None)
    m.name = tag + "_" + (ren[key] if key else "".join(c for c in m.name.lower() if c.isalnum())[:14] or "m%d" % i)
    if m.use_nodes:
        for nd in m.node_tree.nodes:
            if nd.type == "BSDF_PRINCIPLED":
                if not nd.inputs["Metallic"].links and nd.inputs["Metallic"].default_value > 0.35 and "metal" not in m.name:
                    nd.inputs["Metallic"].default_value = 0.1
            if nd.type == "BSDF_PRINCIPLED" and "eye" not in m.name:
                ri = nd.inputs["Roughness"]; mi = nd.inputs["Metallic"]
                nd.inputs["Metallic"].default_value = min(mi.default_value, 0.05) if not mi.links else mi.default_value
                if ri.links:
                    n1 = ri.links[0].from_node
                    img = n1.inputs[0].links[0].from_node.image if n1.inputs and n1.inputs[0].links and hasattr(n1.inputs[0].links[0].from_node, "image") else None
                    if img is not None and img.name not in done_rough:
                        done_rough.add(img.name)
                        w, hh = img.size
                        px = np.array(img.pixels[:], dtype=np.float32).reshape(-1, 4)
                        px[:, 1] = np.maximum(px[:, 1], args.min_rough)
                        px[:, 2] = np.minimum(px[:, 2], 0.05)
                        img.pixels.foreach_set(px.reshape(-1)); img.update()
                else:
                    ri.default_value = max(ri.default_value, args.min_rough)
            if nd.type == "TEX_IMAGE" and nd.image:
                im = nd.image
                if max(im.size) > args.tex:
                    f = args.tex / max(im.size)
                    im.scale(max(1, int(im.size[0] * f)), max(1, int(im.size[1] * f)))
for n in ORDER:
    pass
mesh.name = tag
mesh.data.name = tag

# ------------------------------------------------------------------ attach to the real MPFB rig and export
mesh.parent = rig
am = mesh.modifiers.new("Armature", "ARMATURE"); am.object = rig
bpy.ops.object.select_all(action="DESELECT")
rig.select_set(True); mesh.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(filepath=args.out, export_format="GLB", use_selection=True, export_animations=False,
                          export_skins=True, export_yup=True, export_image_format="JPEG", export_jpeg_quality=88)
log("EXPORTED", args.out, len(mesh.data.polygons), "faces")
