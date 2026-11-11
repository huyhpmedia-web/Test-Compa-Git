"""A light-weight 'clay' scene used only while fitting: renders the head so that the
landmark detector can look at it, and ray-casts detected landmarks back onto the mesh."""
import math
import os
import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

import blcore
import fitlib
import mhlib

EYE_RADIUS = 0.0122  # metres -- adult eyeball


def _eye_material():
    mat = bpy.data.materials.new("FitEye")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs[0])
    xx = nt.nodes.new("ShaderNodeMath"); xx.operation = 'MULTIPLY'
    zz = nt.nodes.new("ShaderNodeMath"); zz.operation = 'MULTIPLY'
    nt.links.new(sep.outputs["X"], xx.inputs[0]); nt.links.new(sep.outputs["X"], xx.inputs[1])
    nt.links.new(sep.outputs["Z"], zz.inputs[0]); nt.links.new(sep.outputs["Z"], zz.inputs[1])
    add = nt.nodes.new("ShaderNodeMath"); add.operation = 'ADD'
    nt.links.new(xx.outputs[0], add.inputs[0]); nt.links.new(zz.outputs[0], add.inputs[1])
    rad = nt.nodes.new("ShaderNodeMath"); rad.operation = 'SQRT'
    nt.links.new(add.outputs[0], rad.inputs[0])
    # push the back hemisphere outside of the iris radius
    back = nt.nodes.new("ShaderNodeMath"); back.operation = 'GREATER_THAN'; back.inputs[1].default_value = 0.0
    nt.links.new(sep.outputs["Y"], back.inputs[0])
    r2 = nt.nodes.new("ShaderNodeMath"); r2.operation = 'ADD'
    nt.links.new(rad.outputs[0], r2.inputs[0]); nt.links.new(back.outputs[0], r2.inputs[1])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = 'CONSTANT'
    el = ramp.color_ramp.elements
    el[0].position = 0.0; el[0].color = (0.01, 0.01, 0.01, 1)
    el[1].position = 0.0021 / 0.02; el[1].color = (0.22, 0.30, 0.34, 1)
    e = el.new(0.0059 / 0.02); e.color = (0.85, 0.83, 0.80, 1)
    scale = nt.nodes.new("ShaderNodeMath"); scale.operation = 'MULTIPLY'; scale.inputs[1].default_value = 1 / 0.02
    nt.links.new(r2.outputs[0], scale.inputs[0])
    nt.links.new(scale.outputs[0], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.25
    return mat


def _skin_material(lips_path):
    mat = bpy.data.materials.new("FitSkin")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(lips_path)
    tex.image.colorspace_settings.name = 'Non-Color'
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = 'RGBA'
    mix.inputs["A"].default_value = (0.62, 0.42, 0.34, 1)
    mix.inputs["B"].default_value = (0.42, 0.13, 0.13, 1)
    nt.links.new(tex.outputs["Color"], mix.inputs["Factor"])
    nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.55
    bsdf.inputs["Subsurface Weight"].default_value = 0.0
    return mat


class FitScene:
    def __init__(self, base, verts, eye_centers, res=1254, samples=12):
        self.base = base
        self.scene = blcore.reset_scene()
        self.res = res
        self.body = blcore.make_body_object(base, verts)
        sub = self.body.modifiers.new("Subdiv", 'SUBSURF')
        sub.levels = 1
        sub.render_levels = 1
        self.body.data.materials.append(_skin_material(os.path.join(mhlib.MH_DATA, "mpfb_lips.jpg")))
        self.eyes = []
        emat = _eye_material()
        for i, c in enumerate(eye_centers):
            me = bpy.data.meshes.new(f"FitEye{i}")
            bm = bmesh.new()
            bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=16, radius=EYE_RADIUS)
            bm.to_mesh(me); bm.free()
            me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
            o = bpy.data.objects.new(f"FitEye{i}", me)
            blcore.link(o)
            o.location = Vector(c)
            me.materials.append(emat)
            self.eyes.append(o)
        # light: soft key + ambient
        key = bpy.data.lights.new("Key", 'AREA'); key.energy = 26; key.size = 1.0
        ko = bpy.data.objects.new("Key", key); blcore.link(ko)
        ko.matrix_world = Matrix(fitlib.look_at((0.5, -1.6, 2.1), (0, 0, 1.5)).tolist())
        world = bpy.data.worlds.new("FitWorld"); self.scene.world = world; world.use_nodes = True
        bg = world.node_tree.nodes["Background"]
        bg.inputs[0].default_value = (0.75, 0.78, 0.85, 1); bg.inputs[1].default_value = 0.42
        self.cam = bpy.data.objects.new("FitCam", bpy.data.cameras.new("FitCam"))
        blcore.link(self.cam)
        self.scene.camera = self.cam
        blcore.setup_cycles(self.scene, samples=samples, res=(res, res))
        self.scene.view_settings.view_transform = 'Standard'
        self._bvh = None

    def set_shape(self, verts, eye_centers=None):
        blcore.set_coords(self.body, verts[:mhlib.N_BODY])
        if eye_centers is not None:
            for o, c in zip(self.eyes, eye_centers):
                o.location = Vector(c)
        self._bvh = None
        bpy.context.view_layer.update()

    def render(self, cam_world, lens, path):
        self.cam.data.lens = lens
        self.cam.data.sensor_width = fitlib.SENSOR
        self.cam.data.clip_start = 0.05
        self.cam.matrix_world = Matrix(np.asarray(cam_world).tolist())
        blcore.render_to(self.scene, path)
        return path

    def bvh(self):
        if self._bvh is None:
            dg = bpy.context.evaluated_depsgraph_get()
            self._bvh = BVHTree.FromObject(self.body, dg)
        return self._bvh

    def raycast(self, pix, cam_world, lens):
        """Pixel coords -> (hit points Nx3, valid mask)."""
        fpx = fitlib.focal_px(lens, self.res)
        origin, dirs = fitlib.pixel_rays(pix, cam_world, fpx, self.res, self.res)
        bvh = self.bvh()
        hits = np.zeros((len(pix), 3))
        ok = np.zeros(len(pix), dtype=bool)
        o = Vector(origin)
        for i, d in enumerate(dirs):
            loc, nrm, idx, dist = bvh.ray_cast(o, Vector(d))
            if loc is not None:
                hits[i] = loc
                ok[i] = True
        return hits, ok
