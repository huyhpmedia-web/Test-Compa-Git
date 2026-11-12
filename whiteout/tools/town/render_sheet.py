# Quick Cycles contact sheet of every building in a glb (vertex colours or materials), one cam per object.
import bpy, sys, math, mathutils, os
glb, out = sys.argv[-2], sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
sc = bpy.context.scene
sc.render.engine = 'CYCLES'; sc.cycles.samples = 12; sc.cycles.device = 'CPU'
sc.render.resolution_x = 360; sc.render.resolution_y = 300
w = bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
w.node_tree.nodes['Background'].inputs[0].default_value = (0.55, 0.6, 0.7, 1); w.node_tree.nodes['Background'].inputs[1].default_value = 0.7
sun = bpy.data.objects.new("S", bpy.data.lights.new("S", 'SUN')); sc.collection.objects.link(sun); sun.rotation_euler = (0.9, 0.3, 0.7); sun.data.energy = 3.5
cam = bpy.data.objects.new("C", bpy.data.cameras.new("C")); sc.collection.objects.link(cam); sc.camera = cam
meshes = [o for o in sc.objects if o.type == 'MESH']
os.makedirs(out, exist_ok=True)
for o in meshes:
    for m in meshes: m.hide_render = (m != o)
    bb = [o.matrix_world @ mathutils.Vector(c) for c in o.bound_box]
    mn = mathutils.Vector([min(v[i] for v in bb) for i in range(3)]); mx = mathutils.Vector([max(v[i] for v in bb) for i in range(3)])
    ctr = (mn + mx) / 2; size = (mx - mn).length
    cam.location = ctr + mathutils.Vector((size * 0.75, -size * 0.95, size * 0.35))
    cam.rotation_euler = (ctr - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = os.path.join(out, o.name + ".png")
    bpy.ops.render.render(write_still=True)
