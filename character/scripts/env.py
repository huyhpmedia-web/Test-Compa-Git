"""Environment that echoes the reference photos: black slatted gate, brick pillar,
foliage and a concrete canopy with a wood-slat soffit -- behind her (front shots) and
on her left (profile shot)."""
import math

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

import blcore


def _mat(name, color, rough=0.6, metallic=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metallic
    return m


def _box(name, size, loc, mat, col, rot_z=0.0):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bm.to_mesh(me); bm.free()
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    blcore.link(ob, col)
    ob.matrix_world = Matrix.Translation(Vector(loc)) @ Matrix.Rotation(rot_z, 4, 'Z')
    return ob


def _slats(name, n, pitch, size, origin, step_axis, mat, col):
    """One mesh holding n boxes spaced along an axis."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    for i in range(n):
        r = bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=Vector(size), verts=r["verts"])
        bmesh.ops.translate(bm, vec=Vector(step_axis) * (i * pitch), verts=r["verts"])
    bm.to_mesh(me); bm.free()
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    blcore.link(ob, col)
    ob.location = Vector(origin)
    return ob


def _brick_mat():
    m = bpy.data.materials.new("Brick_Grey")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    br = nt.nodes.new("ShaderNodeTexBrick")
    br.inputs["Color1"].default_value = (0.30, 0.27, 0.24, 1)
    br.inputs["Color2"].default_value = (0.22, 0.20, 0.18, 1)
    br.inputs["Mortar"].default_value = (0.12, 0.11, 0.10, 1)
    br.inputs["Scale"].default_value = 5.5
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Rotation"].default_value = (math.radians(90), 0, 0)
    nt.links.new(tc.outputs["Object"], mp.inputs[0]); nt.links.new(mp.outputs[0], br.inputs["Vector"])
    nt.links.new(br.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.85
    return m


def _foliage(name, centers, radii, n, col, seed=3):
    rng = np.random.default_rng(seed)
    verts, faces = [], []
    for k in range(n):
        j = rng.integers(len(centers))
        d = rng.normal(0, 1, 3); d /= np.linalg.norm(d)
        c = np.array(centers[j]) + d * np.array(radii[j]) * rng.random() ** 0.4
        a = rng.normal(0, 1, 3); a /= np.linalg.norm(a)
        b = np.cross(a, rng.normal(0, 1, 3)); b /= np.linalg.norm(b)
        s = rng.uniform(0.035, 0.07)
        base = len(verts)
        verts += [c - a * s, c + b * s * 0.45, c + a * s, c - b * s * 0.45]
        faces.append([base, base + 1, base + 2, base + 3])
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    m = bpy.data.materials.new("Leaves")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.10, 0.22, 0.05, 1)
    b.inputs["Roughness"].default_value = 0.45
    b.inputs["Subsurface Weight"].default_value = 0.25
    b.inputs["Subsurface Radius"].default_value = (0.3, 0.8, 0.1)
    b.inputs["Subsurface Scale"].default_value = 0.01
    me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    blcore.link(ob, col)
    return ob


def build(base, fit, body, rig, M_head):
    col = blcore.collection("Environment")
    black = _mat("Gate_Black", (0.012, 0.012, 0.014), 0.45, 0.6)
    concrete = _mat("Concrete", (0.36, 0.36, 0.35), 0.9)
    wood = _mat("Wood_Slats", (0.36, 0.20, 0.09), 0.6)
    paving = _mat("Paving", (0.30, 0.30, 0.29), 0.85)
    brick = _brick_mat()
    _box("Ground", (40, 40, 0.1), (0, 0, -0.05), paving, col)
    # ---- behind her (front + close-up shots look towards +Y)
    _box("Gate_Back_Panel", (7.0, 0.04, 2.9), (2.3, 3.60, 1.45), black, col)
    _slats("Gate_Back_Slats", 110, 0.062, (0.034, 0.05, 2.8), (-1.15, 3.54, 1.42), (1, 0, 0), black, col)
    _box("Pillar_Back", (0.62, 0.62, 2.7), (-1.62, 3.5, 1.35), brick, col)
    _box("Wall_Back", (3.0, 0.3, 1.5), (-3.3, 3.6, 0.75), brick, col)
    _box("Canopy_Back", (6.5, 3.4, 0.42), (2.35, 2.6, 3.02), concrete, col)
    _slats("Soffit_Back", 34, 0.10, (6.4, 0.07, 0.03), (2.35, 0.95, 2.79), (0, 1, 0), wood, col)
    _foliage("Foliage_Back", [(-2.0, 2.9, 2.5), (-2.9, 2.6, 2.0), (-1.7, 3.3, 3.2)],
             [(0.9, 0.7, 0.9), (0.8, 0.7, 0.8), (0.8, 0.6, 0.7)], 5200, col, seed=3)
    # ---- on her left (the profile shot looks towards +X)
    _box("Gate_Side_Panel", (0.04, 7.0, 2.9), (3.60, -2.3, 1.45), black, col)
    _slats("Gate_Side_Slats", 110, 0.062, (0.05, 0.034, 2.8), (3.54, -5.6, 1.42), (0, 1, 0), black, col)
    _box("Pillar_Side", (0.62, 0.62, 2.7), (3.5, 1.62, 1.35), brick, col)
    _box("Wall_Side", (0.3, 3.0, 1.5), (3.6, 3.3, 0.75), brick, col)
    _box("Canopy_Side", (3.4, 6.5, 0.42), (2.6, -2.35, 3.02), concrete, col)
    _slats("Soffit_Side", 34, 0.10, (0.07, 6.4, 0.03), (0.95, -2.35, 2.79), (1, 0, 0), wood, col)
    _foliage("Foliage_Side", [(2.9, 2.0, 2.5), (2.6, 2.9, 2.0), (3.3, 1.7, 3.2)],
             [(0.7, 0.9, 0.9), (0.7, 0.8, 0.8), (0.6, 0.8, 0.7)], 5200, col, seed=5)
    return {}
