import bpy, sys, numpy as np, mathutils
glb=sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
out=[]
for o in bpy.data.objects:
    if o.type!='MESH': continue
    me=o.data
    ca=me.color_attributes.get('Color')
    cols=set()
    if ca:
        a=np.empty(len(ca.data)*4,dtype=np.float32); ca.data.foreach_get('color',a); a=a.reshape(-1,4)
        q=np.round(a[:,:3]*20).astype(int)
        u,c=np.unique(q,axis=0,return_counts=True)
        cols=len(u)
    p=o.parent.name if o.parent else ''
    out.append((o.name,p,[round(x,1) for x in o.dimensions],len(me.polygons),cols,[round(x,1) for x in o.matrix_world.translation]))
for r in out: print(r)
