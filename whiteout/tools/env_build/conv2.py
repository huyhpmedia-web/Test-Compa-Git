import bpy, sys, os, json, math, mathutils
# usage: conv2.py -- specs.json outroot [only_name ...]
a=sys.argv[sys.argv.index('--')+1:]
specs=json.load(open(a[0])); outroot=os.path.abspath(a[1]); only=set(a[2:])
PH=os.path.abspath("ph")
def tris(o): return sum(len(p.vertices)-2 for p in o.data.polygons)
def bbox(objs):
    mn=mathutils.Vector((1e9,)*3); mx=mathutils.Vector((-1e9,)*3)
    for o in objs:
        for v in o.bound_box:
            w=o.matrix_world@mathutils.Vector(v)
            mn=mathutils.Vector([min(mn[i],w[i]) for i in range(3)]); mx=mathutils.Vector([max(mx[i],w[i]) for i in range(3)])
    return mn,mx
def match(o,pick):
    for p in pick:
        if p.startswith('='):
            if o.name==p[1:]: return True
        elif p.startswith('^'):
            if o.name.startswith(p[1:]): return True
        elif o.name==p: return True
    return False
def do(spec):
    name=spec['src']; out=spec['out']; budget=spec.get('tris',8000); tex=spec.get('tex',512)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=f"{PH}/{name}/{name}_1k.gltf")
    sc=bpy.context.scene
    for o in list(sc.objects):
        if o.type!='MESH' and o.type!='EMPTY':
            bpy.data.objects.remove(o,do_unlink=True)
    bpy.ops.object.select_all(action='DESELECT')
    meshes=[o for o in sc.objects if o.type=='MESH']
    for o in meshes: o.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0]
    bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM')
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    for o in list(sc.objects):
        if o.type=='EMPTY': bpy.data.objects.remove(o,do_unlink=True)
    meshes=[o for o in sc.objects if o.type=='MESH']
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.make_single_user(object=True,obdata=True)
    for o in meshes:
        if o.data.shape_keys: o.shape_key_clear()
    if spec.get('pick'):
        for o in list(meshes):
            if not match(o,spec['pick']): bpy.data.objects.remove(o,do_unlink=True)
        meshes=[o for o in sc.objects if o.type=='MESH']
    if spec.get('drop'):
        for o in list(meshes):
            if match(o,spec['drop']): bpy.data.objects.remove(o,do_unlink=True)
        meshes=[o for o in sc.objects if o.type=='MESH']
    groups=[meshes]
    if spec.get('split'):
        groups=[[o] for o in meshes]
    for gi,grp in enumerate(groups):
        # work on copies per group when splitting: simply process in place then export selection
        pass
    def process(grp,outname):
        # duplicate objects of the group into a fresh collection state: simple approach, hide others
        for o in sc.objects: o.hide_viewport=True; o.hide_render=True; o.select_set(False)
        for o in grp: o.hide_viewport=False; o.hide_render=False
        bpy.ops.object.select_all(action='DESELECT')
        for o in grp: o.select_set(True)
        bpy.context.view_layer.objects.active=grp[0]
        # pivot
        if spec.get('pivot'):
            pv=[o for o in grp if o.name==spec['pivot']]
            pmn,pmx=bbox(pv) if pv else bbox(grp)
        else:
            pmn,pmx=bbox(grp)
        gmn,gmx=bbox(grp)
        cx=(pmn.x+pmx.x)/2; cy=(pmn.y+pmx.y)/2
        cz=gmn.z if not spec.get('keepz') else 0.0
        if spec.get('center',True):
            for o in grp: o.location-=mathutils.Vector((cx,cy,cz))
        if spec.get('rotz'):
            for o in grp:
                # rotate about origin
                m=mathutils.Matrix.Rotation(math.radians(spec['rotz']),4,'Z')
                o.matrix_world=m@o.matrix_world
        if spec.get('scale'):
            for o in grp: o.scale*=spec['scale']; o.location*=spec['scale']
        bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
        if len(grp)>1 and spec.get('join',True):
            bpy.ops.object.join(); grp=[bpy.context.view_layer.objects.active]
        t0=sum(tris(o) for o in grp)
        if t0>budget:
            r=budget/t0
            for o in grp:
                bpy.context.view_layer.objects.active=o
                m=o.modifiers.new("d",'DECIMATE'); m.decimate_type='COLLAPSE'; m.ratio=max(0.003,r); m.use_collapse_triangulate=True
                bpy.ops.object.modifier_apply(modifier="d")
        t1=sum(tris(o) for o in grp)
        for im in bpy.data.images:
            if im.size[0]>tex or im.size[1]>tex:
                s=tex/max(im.size); im.scale(max(4,int(im.size[0]*s)),max(4,int(im.size[1]*s)))
        fp=f"{outroot}/{outname}.glb"
        os.makedirs(os.path.dirname(fp),exist_ok=True)
        bpy.ops.object.select_all(action='DESELECT')
        for o in grp: o.select_set(True)
        bpy.ops.export_scene.gltf(filepath=fp,export_format='GLB',export_image_format='JPEG',export_jpeg_quality=82,export_yup=True,export_apply=True,use_selection=True,export_cameras=False,export_lights=False)
        mn,mx=bbox(grp)
        print(f"CONV {outname} tris {t0}->{t1} {os.path.getsize(fp)/1e6:.2f}MB size(x,y,z blender)=({mx.x-mn.x:.2f},{mx.y-mn.y:.2f},{mx.z-mn.z:.2f})",flush=True)
    if spec.get('split'):
        for i,o in enumerate(meshes):
            process([o],f"{out}_{i+1}")
    else:
        process(meshes,out)
for s in specs:
    if only and s['out'] not in only and s['src'] not in only: continue
    try: do(s)
    except Exception as e: print("FAIL",s['out'],repr(e)[:200],flush=True)
