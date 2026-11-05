import bpy, sys, os, math, mathutils
# usage: prev.py -- out.png a.glb [b.glb ...]  (laid out in a row)
args=sys.argv[sys.argv.index('--')+1:]
out=args[0]; files=args[1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
x=0; ext=[]
for f in files:
    before=set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=f)
    new=[o for o in bpy.context.scene.objects if o not in before and o.type=='MESH']
    mn=mathutils.Vector((1e9,)*3); mx=mathutils.Vector((-1e9,)*3)
    for o in new:
        for v in o.bound_box:
            w=o.matrix_world@mathutils.Vector(v); mn=mathutils.Vector([min(mn[i],w[i]) for i in range(3)]); mx=mathutils.Vector([max(mx[i],w[i]) for i in range(3)])
    w=mx.x-mn.x
    off=x-mn.x-w/2
    roots=[o for o in bpy.context.scene.objects if o not in before and o.parent is None]
    for o in roots: o.location.x+=off
    x+=w+1.0
    ext.append(max(mx.z-mn.z,w))
    print(f, "size", round(w,2), round(mx.y-mn.y,2), round(mx.z-mn.z,2))
sc=bpy.context.scene
cx=x/2
H=max(ext)
cam=bpy.data.cameras.new("c"); cam.type='ORTHO'; cam.ortho_scale=max(x*1.05,H*1.7)
co=bpy.data.objects.new("c",cam); sc.collection.objects.link(co)
co.location=(cx,-30,H*0.45); co.rotation_euler=(math.radians(90),0,0)
sc.camera=co
sc.render.engine='CYCLES'; sc.cycles.samples=24; sc.cycles.device='CPU'
sun=bpy.data.lights.new('s','SUN'); sun.energy=3
so=bpy.data.objects.new('s',sun); sc.collection.objects.link(so); so.rotation_euler=(math.radians(55),0,math.radians(-30))
sc.render.resolution_x=1100; sc.render.resolution_y=int(1100*max(H*1.7,1)/max(x*1.05,H*1.7))
sc.world=bpy.data.worlds.new("w"); sc.world.use_nodes=False; sc.world.color=(0.35,0.4,0.5)
sc.render.filepath=os.path.abspath(out)
bpy.ops.render.render(write_still=True)
