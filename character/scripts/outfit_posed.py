"""Outfit, posed part: ribbon choker tied in a bow, halter strings, long hanging tail and
stud earrings.  Built against the posed body (front-shot pose) and bone-parented."""
import math

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

import blcore
import charlib
import fitlib


def ribbon_material():
    mat = bpy.data.materials.new("Ribbon_White")
    mat.use_nodes = True
    b = mat.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.90, 0.87, 0.87, 1)
    b.inputs["Roughness"].default_value = 0.7
    if "Sheen Weight" in b.inputs:
        b.inputs["Sheen Weight"].default_value = 0.5
    return mat


def curve_obj(name, pts, mat, col, cyclic=False, width=0.0, depth=0.0021):
    cu = bpy.data.curves.new(name, 'CURVE')
    cu.dimensions = '3D'
    cu.twist_mode = 'Z_UP'
    cu.bevel_depth = depth
    cu.bevel_resolution = 3
    cu.extrude = width
    cu.use_fill_caps = True
    sp = cu.splines.new('NURBS')
    sp.points.add(len(pts) - 1)
    for p, q in zip(sp.points, pts):
        p.co = (*q, 1.0)
    sp.use_cyclic_u = cyclic
    sp.use_endpoint_u = not cyclic
    sp.order_u = 4
    cu.resolution_u = 6
    cu.materials.append(mat)
    ob = bpy.data.objects.new(name, cu)
    blcore.link(ob, col)
    return ob


def keep_parent(obj, rig, bone):
    bpy.context.view_layer.update()
    world = obj.matrix_world.copy()
    obj.parent = rig
    obj.parent_type = 'BONE'
    obj.parent_bone = bone
    pb = rig.pose.bones[bone]
    obj.matrix_parent_inverse = (rig.matrix_world @ pb.matrix @ Matrix.Translation((0, pb.bone.length, 0))).inverted()
    obj.matrix_basis = world


def build(base, fit, body, rig, M_head):
    col = blcore.collection("Character")
    bpy.context.scene.frame_set(1)
    dg = bpy.context.evaluated_depsgraph_get()
    surfs = [BVHTree.FromObject(body, dg)]
    top = bpy.data.objects.get("Top")
    if top is not None:
        surfs.append(BVHTree.FromObject(top, dg))
    mw = rig.matrix_world

    def cast(origin, direction, both=True):
        best = None
        for bvh in (surfs if both else surfs[:1]):
            loc, nrm, _, dist = bvh.ray_cast(Vector(origin), Vector(direction))
            if loc is not None and (best is None or dist < best[1]):
                best = (np.array(loc), dist)
        return None if best is None else best[0]

    mat = ribbon_material()
    n0 = np.array(mw @ rig.pose.bones["neck01"].head)
    h0 = np.array(mw @ rig.pose.bones["head"].head)
    axis = (h0 - n0) / np.linalg.norm(h0 - n0)
    cen = n0 + (h0 - n0) * 0.50
    e1 = np.cross(axis, [0.0, 1.0, 0.0]); e1 /= np.linalg.norm(e1)       # ~ +X
    e2 = np.cross(axis, e1)                                               # ~ front (-Y)
    if e2[1] > 0:
        e2 = -e2
    ring = []
    angs = np.linspace(0, 2 * math.pi, 72, endpoint=False)
    for a in angs:
        d = e1 * math.sin(a) + e2 * math.cos(a)                           # a = 0 is the front
        c = cen - axis * 0.006 * math.cos(a)                              # sits lower in front
        hit = cast(c + d * 0.25, -d, both=False)
        ring.append((hit if hit is not None else c + d * 0.05) + d * 0.0022)
    ring = np.array(ring)
    objs = [curve_obj("Choker", ring, mat, col, cyclic=True, width=0.0042, depth=0.0011)]

    def ring_at(deg):
        a = math.radians(deg) % (2 * math.pi)
        i = int(round(a / (2 * math.pi) * 72)) % 72
        d = e1 * math.sin(a) + e2 * math.cos(a)
        t = np.cross(axis, d)
        return ring[i], d, t / np.linalg.norm(t)

    # bow on her right-front (negative X): two loops, a short and a long tail
    knot, out, tan = ring_at(-38.0)
    knot = knot + out * 0.003
    down = -axis
    for i, sgn in enumerate((-1.0, 1.0)):
        u = (down * 0.80 + tan * sgn * 0.60); u /= np.linalg.norm(u)
        w = np.cross(out, u)
        s = np.linspace(0, 1, 14)
        loop = [knot + u * (0.034 * math.sin(math.pi * t)) + w * (0.011 * math.sin(2 * math.pi * t)) + out * (0.004 * math.sin(math.pi * t)) for t in s]
        objs.append(curve_obj(f"Bow_Loop_{i}", loop, mat, col, width=0.0036, depth=0.0011))
    objs.append(curve_obj("Bow_Knot", [knot - tan * 0.005 + out * 0.002, knot + out * 0.004, knot + tan * 0.005 + out * 0.002], mat, col, width=0.004, depth=0.0022))

    def drape(p_from, p_to, n=16, off=0.006, sag=0.0):
        pts = []
        for t in np.linspace(0, 1, n):
            p = p_from * (1 - t) + p_to * t
            p[2] -= sag * math.sin(math.pi * t)
            hit = cast((p[0], p[1] - 0.6, p[2]), (0, 1, 0))
            if hit is not None and p[1] > hit[1] - off:
                p[1] = hit[1] - off
            pts.append(p)
        return pts

    z_apex = float(fit["verts"][:, 2].max()) - 0.385
    tail_end = np.array([knot[0] - 0.045, knot[1] - 0.02, knot[2] - 0.185])
    objs.append(curve_obj("Bow_Tail_Long", drape(knot.copy(), tail_end, n=18), mat, col, width=0.0032, depth=0.0010))
    short_end = np.array([knot[0] + 0.022, knot[1] - 0.01, knot[2] - 0.060])
    objs.append(curve_obj("Bow_Tail_Short", drape(knot.copy(), short_end, n=8), mat, col, width=0.0032, depth=0.0010))
    # halter strings: choker -> corners of the neckline
    for name, deg, sx in (("String_R", -52.0, -1.0), ("String_L", 58.0, 1.0)):
        start, _, _ = ring_at(deg)
        corner = cast((sx * 0.122, -0.6, start[2] - 0.085), (0, 1, 0))
        if corner is None:
            continue
        corner = corner + np.array([0, -0.004, 0])
        objs.append(curve_obj(name, drape(start.copy(), corner, n=12, off=0.0045), mat, col, depth=0.0024))
    for ob in objs:
        keep_parent(ob, rig, "neck02")

    # stud earrings: located by ray-casting the earring pixel of the close-up photo (rest pose)
    cams = charlib.photo_cameras(fit)
    fpx = fitlib.focal_px(charlib.LENS, charlib.RES)
    o, d = fitlib.pixel_rays(np.array([[963.0, 558.0]]), cams["closeup"], fpx, charlib.RES, charlib.RES)
    rest = bpy.data.objects.new("tmp", body.data)            # un-posed copy for the rest-pose ray
    bpy.context.scene.collection.objects.link(rest)
    bpy.context.view_layer.update()
    hit = BVHTree.FromObject(rest, bpy.context.evaluated_depsgraph_get()).ray_cast(Vector(o), Vector(d[0]))
    bpy.data.objects.remove(rest)
    if hit[0] is not None:
        gem = bpy.data.materials.new("Stud_Crystal")
        gem.use_nodes = True
        g = gem.node_tree.nodes["Principled BSDF"]
        g.inputs["Base Color"].default_value = (0.95, 0.95, 1.0, 1)
        g.inputs["Metallic"].default_value = 1.0
        g.inputs["Roughness"].default_value = 0.08
        p = np.array(hit[0])
        for side, sx in (("L", 1.0), ("R", -1.0)):
            me = bpy.data.meshes.new(f"Stud_{side}_Mesh")
            bm = bmesh.new()
            bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.0021)
            bm.to_mesh(me); bm.free()
            me.materials.append(gem)
            ob = bpy.data.objects.new(f"Earring_{side}", me)
            blcore.link(ob, col)
            q = np.array([abs(p[0]) * sx + 0.0012 * sx, p[1], p[2]])
            ob.location = Vector((M_head[:3, :3] @ q + M_head[:3, 3]).tolist())
            keep_parent(ob, rig, "head")
    return {"objects": objs}
