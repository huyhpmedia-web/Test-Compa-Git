"""Eyeballs: inner sclera/iris sphere + refractive cornea shell, procedural iris."""
import math

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

import blcore

IRIS_R = 0.0060      # metres (visible iris radius)
PUPIL_R = 0.0019


def _sphere(name, radius, seg=64, rings=32):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=radius)
    # pole axis +Z -> -Y so that local -Y is the gaze direction
    bmesh.ops.transform(bm, matrix=Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1))), verts=bm.verts)
    bm.to_mesh(me)
    bm.free()
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    return me


def _shape(me, radius, cornea):
    co = blcore.get_coords(me)
    r = np.sqrt(co[:, 0] ** 2 + co[:, 2] ** 2)
    front = co[:, 1] < 0
    if cornea:
        t = np.clip(1.0 - r / (IRIS_R * 1.25), 0.0, 1.0) * front
        bulge = 0.0014 * (t * t * (3 - 2 * t))
        co *= (1.0 + bulge / radius)[:, None]
    else:
        inside = front & (r < IRIS_R)
        y_rim = -math.sqrt(max(radius ** 2 - IRIS_R ** 2, 0.0))
        co[inside, 1] = y_rim + 0.0007 * (1.0 - (r[inside] / IRIS_R) ** 2)   # shallow concave iris disc
    blcore.set_coords(me, co)


def iris_material(name="Eye_Iris_Sclera", iris_rgb=(0.30, 0.40, 0.46)):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    N = nt.nodes.new
    tc = N("ShaderNodeTexCoord")
    sep = N("ShaderNodeSeparateXYZ"); nt.links.new(tc.outputs["Object"], sep.inputs[0])
    xz = N("ShaderNodeCombineXYZ"); nt.links.new(sep.outputs["X"], xz.inputs[0]); nt.links.new(sep.outputs["Z"], xz.inputs[1])
    rad = N("ShaderNodeVectorMath"); rad.operation = 'LENGTH'; nt.links.new(xz.outputs[0], rad.inputs[0])
    # the back half never shows iris
    back = N("ShaderNodeMath"); back.operation = 'GREATER_THAN'; back.inputs[1].default_value = 0.0
    nt.links.new(sep.outputs["Y"], back.inputs[0])
    r = N("ShaderNodeMath"); r.operation = 'ADD'; nt.links.new(rad.outputs["Value"], r.inputs[0]); nt.links.new(back.outputs[0], r.inputs[1])
    rn = N("ShaderNodeMath"); rn.operation = 'DIVIDE'; rn.inputs[1].default_value = IRIS_R
    nt.links.new(r.outputs[0], rn.inputs[0])                      # 0 centre .. 1 limbus
    # radial fibres: noise stretched along the radius
    ang = N("ShaderNodeMath"); ang.operation = 'ARCTAN2'
    nt.links.new(sep.outputs["X"], ang.inputs[0]); nt.links.new(sep.outputs["Z"], ang.inputs[1])
    fib_co = N("ShaderNodeCombineXYZ"); nt.links.new(ang.outputs[0], fib_co.inputs[0]); nt.links.new(rn.outputs[0], fib_co.inputs[1])
    noise = N("ShaderNodeTexNoise"); noise.inputs["Scale"].default_value = 1.0; noise.inputs["Detail"].default_value = 6.0
    mapping = N("ShaderNodeMapping"); mapping.inputs["Scale"].default_value = (14.0, 1.2, 1.0)
    nt.links.new(fib_co.outputs[0], mapping.inputs[0]); nt.links.new(mapping.outputs[0], noise.inputs["Vector"])
    ramp = N("ShaderNodeValToRGB")
    e = ramp.color_ramp.elements
    c = iris_rgb
    e[0].position = 0.0; e[0].color = (0.0, 0.0, 0.0, 1)
    e[1].position = PUPIL_R / IRIS_R; e[1].color = (0.0, 0.0, 0.0, 1)
    for pos, col in ((PUPIL_R / IRIS_R + 0.03, (c[0] * 0.75, c[1] * 0.62, c[2] * 0.50)),
                     (0.55, c), (0.86, (c[0] * 0.85, c[1] * 0.9, c[2] * 0.95)),
                     (0.97, (c[0] * 0.28, c[1] * 0.30, c[2] * 0.34)),
                     (1.04, (0.80, 0.76, 0.74)), (1.6, (0.86, 0.82, 0.80))):
        el = e.new(min(pos / 2.0, 1.0)); el.color = (*col, 1)
    e[1].position = PUPIL_R / IRIS_R / 2.0
    half = N("ShaderNodeMath"); half.operation = 'MULTIPLY'; half.inputs[1].default_value = 0.5
    nt.links.new(rn.outputs[0], half.inputs[0]); nt.links.new(half.outputs[0], ramp.inputs[0])
    # modulate the iris by the fibres
    fib = N("ShaderNodeMapRange"); fib.inputs["To Min"].default_value = 0.72; fib.inputs["To Max"].default_value = 1.28
    nt.links.new(noise.outputs["Fac"], fib.inputs["Value"])
    is_iris = N("ShaderNodeMath"); is_iris.operation = 'LESS_THAN'; is_iris.inputs[1].default_value = 0.98
    nt.links.new(rn.outputs[0], is_iris.inputs[0])
    gain = N("ShaderNodeMix"); gain.data_type = 'FLOAT'; gain.inputs["A"].default_value = 1.0
    nt.links.new(is_iris.outputs[0], gain.inputs["Factor"]); nt.links.new(fib.outputs["Result"], gain.inputs["B"])
    mul = N("ShaderNodeMix"); mul.data_type = 'RGBA'; mul.blend_type = 'MULTIPLY'; mul.inputs["Factor"].default_value = 1.0
    grey = N("ShaderNodeCombineColor")
    for k in ("Red", "Green", "Blue"):
        nt.links.new(gain.outputs["Result"], grey.inputs[k])
    nt.links.new(ramp.outputs["Color"], mul.inputs["A"]); nt.links.new(grey.outputs[0], mul.inputs["B"])
    nt.links.new(mul.outputs["Result"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.35
    bsdf.inputs["Subsurface Weight"].default_value = 0.15
    bsdf.inputs["Subsurface Radius"].default_value = (1.0, 0.6, 0.5)
    bsdf.inputs["Subsurface Scale"].default_value = 0.002
    bsdf.inputs["Specular IOR Level"].default_value = 0.2
    return mat


def cornea_material(name="Eye_Cornea"):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (1, 1, 1, 1)
    bsdf.inputs["Roughness"].default_value = 0.02
    bsdf.inputs["IOR"].default_value = 1.376
    bsdf.inputs["Transmission Weight"].default_value = 1.0
    out = nt.nodes["Material Output"]
    # let light through for shadow rays so the iris underneath is lit
    lp = nt.nodes.new("ShaderNodeLightPath")
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(lp.outputs["Is Shadow Ray"], mix.inputs[0])
    nt.links.new(bsdf.outputs[0], mix.inputs[1]); nt.links.new(tr.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    return mat


def build_eyes(centers, radii, col=None, iris_rgb=(0.30, 0.40, 0.46)):
    """centers: {'L': xyz, 'R': xyz}.  Returns {'L': eyeball object, 'R': ...}."""
    m_in, m_out = iris_material(iris_rgb=iris_rgb), cornea_material()
    out = {}
    for side in ("L", "R"):
        R = float(radii[side])
        me = _sphere(f"Eyeball_{side}_Mesh", R)
        _shape(me, R, cornea=False)
        me.materials.append(m_in)
        ob = bpy.data.objects.new(f"Eyeball_{side}", me)
        blcore.link(ob, col)
        ob.location = Vector(centers[side])
        mc = _sphere(f"Cornea_{side}_Mesh", R + 0.00012)
        _shape(mc, R + 0.00012, cornea=True)
        mc.materials.append(m_out)
        oc = bpy.data.objects.new(f"Cornea_{side}", mc)
        blcore.link(oc, col)
        oc.parent = ob
        out[side] = ob
    return out
