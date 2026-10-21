"""Headless Blender build of the Whiteout characters.

  python build_characters.py [--only elias,june,...] [--no-anim] [--out DIR]
(run with a python that has `bpy`, e.g. the venv from tools/charpipe/README.txt)
"""
import os, sys, json, math, argparse, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import bpy
from mathutils import Vector
import mh_lib as mh
import bl_common as bc
import specs

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../.."))
OUT_DIR = os.path.join(REPO, "assets/characters")
WORK = os.path.join(mh.CACHE, "work")


def A(*p):
    return os.path.join(mh.ASSETS, *p)


class CharBuilder:
    def __init__(self, spec):
        self.spec = spec
        self.name = spec["name"]
        bc.clear_scene()
        self.H = mh.Human()
        self._morph()
        self.rig, self.wts = mh.load_rig("game_engine")
        self.bones = sorted(self.rig.keys())
        self.W = mh.dense_weights(self.wts, self.bones)
        self._xform()
        self.objs = []

    # ---------------- morph ----------------
    def _morph(self):
        s = self.spec
        H = self.H
        H.macro(gender=s["gender"], age_years=s["age"], muscle=s.get("muscle", 0.5),
                weight=s.get("weight", 0.5), height=s.get("height_slider", 0.5))
        for item in s.get("details", []):
            H.detail(*item)

    def _xform(self):
        b = mh.mh_to_blender(self.H.v[:mh.N_BODY])
        h = b[:, 2].max() - b[:, 2].min()
        self.s = self.spec["height_m"] / h
        self.z0 = -b[:, 2].min() * self.s

    def conv(self, v_mh):
        b = mh.mh_to_blender(v_mh) * self.s
        b[..., 2] += self.z0
        return b

    # ---------------- armature ----------------
    def build_armature(self):
        H = self.H
        def jp(spec):
            if spec["strategy"] == "CUBE":
                p = H.joint(spec["cube_name"])
            else:
                p = H.v[spec["vertex_indices"]].mean(axis=0)
            return self.conv(p)
        self.arm, self.bone_order = bc.build_armature("Armature_" + self.name, self.rig, jp)
        self.arm.name = self.name + "_rig"

    # ---------------- meshes ----------------
    def build_body(self, delete_verts):
        H = self.H
        faces = H.body_faces
        dv = np.zeros(mh.N_BODY, dtype=bool)
        if len(delete_verts):
            dv[np.array(sorted(set(delete_verts)))[np.array(sorted(set(delete_verts))) < mh.N_BODY]] = True
        keep = [f for f in faces if not any(dv[i] for i in f[0])]
        used = sorted({i for f in keep for i in f[0]})
        remap = -np.ones(mh.N_BODY, dtype=np.int64)
        remap[used] = np.arange(len(used))
        verts = self.conv(H.v[:mh.N_BODY])[used]
        fi = [[int(remap[i]) for i in f[0]] for f in keep]
        ti = [f[1] for f in keep]
        ob = bc.make_mesh(self.name + "_body", verts, fi, H.uv, ti)
        if getattr(self, 'arm', None) is not None:
            bc.set_weights(ob, self.W[used], self.bones)
            bc.parent_to_armature(ob, self.arm)
        self.body = ob
        self.body_used = used
        return ob

    def build_proxy(self, label, path, material=None, weights_from_body=True, bone=None):
        P = mh.Proxy(path)
        pos = self.conv(P.fit(self.H.v, self.H.base_v))
        fi = [f[0] for f in P.faces]; ti = [f[1] for f in P.faces]
        ob = bc.make_mesh(f"{self.name}_{label}", pos, fi, P.uv, ti)
        if getattr(self, 'arm', None) is None:
            pass
        elif bone is not None:
            ob.vertex_groups.new(name=bone).add(list(range(len(pos))), 1.0, 'REPLACE')
            for b in self.bones:
                if b != bone: ob.vertex_groups.new(name=b)
        else:
            bc.set_weights(ob, P.skin_weights(self.W), self.bones)
        if getattr(self, 'arm', None) is not None:
            bc.parent_to_armature(ob, self.arm)
        if material is not None:
            ob.data.materials.append(material)
        self.objs.append(ob)
        return ob, P


    # ---------------- generic helpers ----------------
    def add_mesh(self, label, pos, fvs, fts=None, uv=None, W=None, bone=None, mat=None, smooth=True):
        """pos (n,3) blender coords; fvs list of vertex-index lists; W dense weights (n, nbones)."""
        ob = bc.make_mesh(f"{self.name}_{label}", pos, fvs, uv, fts)
        if not smooth:
            for p in ob.data.polygons: p.use_smooth = False
        arm = getattr(self, 'arm', None)
        if arm is not None:
            if bone is not None:
                for b in self.bones: ob.vertex_groups.new(name=b)
                ob.vertex_groups[bone].add(list(range(len(pos))), 1.0, 'REPLACE')
            elif W is not None:
                bc.set_weights(ob, W, self.bones)
            bc.parent_to_armature(ob, arm)
        if mat is not None:
            ob.data.materials.append(mat)
        self.objs.append(ob)
        return ob

    def components(self, P):
        n = len(P.v0); par = list(range(n))
        def f(a):
            while par[a] != a:
                par[a] = par[par[a]]; a = par[a]
            return a
        for fc, _ in P.faces:
            for i in fc[1:]:
                par[f(i)] = f(fc[0])
        roots = {}
        comp = np.zeros(n, dtype=np.int64)
        for i in range(n):
            comp[i] = roots.setdefault(f(i), len(roots))
        return comp

    def sub_mesh(self, pos, faces, vsel_mask):
        """faces whose verts are all in mask -> (pos_sub, [fv], [ft], remap, vidx)"""
        keep = [fc for fc in faces if all(vsel_mask[i] for i in fc[0])]
        used = sorted({i for fc in keep for i in fc[0]})
        remap = -np.ones(len(pos), dtype=np.int64); remap[used] = np.arange(len(used))
        return (pos[used], [[int(remap[i]) for i in fc[0]] for fc in keep], [fc[1] for fc in keep],
                remap, np.array(used, dtype=np.int64))

    def body_dense_W_for_pos_nearest(self, pos):
        """weights for arbitrary new geometry: copy from nearest body vertex (blender coords)."""
        bp = self.conv(self.H.v[:mh.N_BODY])
        out = np.zeros((len(pos), self.W.shape[1]))
        for i, p in enumerate(pos):
            d = ((bp - p) ** 2).sum(1)
            out[i] = self.W[int(np.argmin(d))]
        return out

    # ---------------- materials ----------------
    def mat_from_mhmat(self, name, mhmat_path, color=(1, 1, 1, 1), rough=0.9, max_size=1024,
                       use_normal=True, alpha=False, **kw):
        d = mh.parse_mhmat(mhmat_path)
        base_dir = os.path.dirname(mhmat_path)
        base = nrm = None
        if "diffuseTexture" in d:
            base = bc.tex_image(os.path.join(base_dir, d["diffuseTexture"][0]), "sRGB", max_size)
        if use_normal and "normalmapTexture" in d:
            nrm = bc.tex_image(os.path.join(base_dir, d["normalmapTexture"][0]), "Non-Color", max_size)
        return bc.make_material(name, color=color, base=base, normal=nrm, rough=rough, alpha_tex=alpha, **kw)


def export_glb(cb, path, anims=True):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in bpy.data.objects:
        ob.select_set(True)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', use_selection=True,
        export_apply=False, export_yup=True, export_skins=True, export_animations=anims,
        export_animation_mode='ACTIONS' if anims else 'ACTIVE_ACTIONS',
        export_image_format='AUTO', export_texcoords=True, export_normals=True,
        export_tangents=False, export_materials='EXPORT', export_cameras=False, export_lights=False,
        export_force_sampling=True, export_optimize_animation_size=True,
        export_def_bones=False, export_leaf_bone=False)
    print("exported", path, os.path.getsize(path) // 1024, "KB")


def build(name, anims=True, out_dir=OUT_DIR):
    t0 = time.time()
    spec = specs.SPECS[name]
    cb = CharBuilder(spec)
    cb.build_armature()
    specs.assemble(cb, spec)
    export_glb(cb, os.path.join(out_dir, spec["file"]), anims)
    tris = 0
    for ob in bpy.data.objects:
        if ob.type == 'MESH':
            tris += sum(len(p.vertices) - 2 for p in ob.data.polygons)
    print(f"[{name}] tris={tris} time={time.time()-t0:.0f}s")
    return cb


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--no-anim", action="store_true")
    ap.add_argument("--out", default=OUT_DIR)
    a = ap.parse_args(argv)
    names = a.only.split(",") if a.only else list(specs.SPECS.keys())
    for n in names:
        build(n, anims=not a.no_anim, out_dir=a.out)
