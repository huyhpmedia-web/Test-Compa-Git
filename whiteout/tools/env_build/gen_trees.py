import bpy, bmesh, sys, os, math, random, mathutils
from mathutils import Vector, Matrix
OUT=os.path.abspath(sys.argv[sys.argv.index('--')+1])
ACG=os.path.abspath("acg"); TEX=os.path.abspath("tex")

def mk_mat(name, color, nor, rough, texsize, alpha=None, scissor=0.5, double=True):
    m=bpy.data.materials.new(name); m.use_nodes=True
    nt=m.node_tree; nt.nodes.clear()
    out=nt.nodes.new('ShaderNodeOutputMaterial'); bsdf=nt.nodes.new('ShaderNodeBsdfPrincipled')
    nt.links.new(bsdf.outputs[0],out.inputs[0])
    def img(path,cs):
        im=bpy.data.images.load(path); im.colorspace_settings.name=cs
        if max(im.size)>texsize: s=texsize/max(im.size); im.scale(int(im.size[0]*s),int(im.size[1]*s))
        n=nt.nodes.new('ShaderNodeTexImage'); n.image=im; return n
    c=img(color,'sRGB'); nt.links.new(c.outputs[0],bsdf.inputs['Base Color'])
    if alpha=='alpha':
        nt.links.new(c.outputs[1],bsdf.inputs['Alpha'])
    if nor:
        n=img(nor,'Non-Color'); nm=nt.nodes.new('ShaderNodeNormalMap'); nt.links.new(n.outputs[0],nm.inputs[0]); nt.links.new(nm.outputs[0],bsdf.inputs['Normal'])
    if rough:
        r=img(rough,'Non-Color'); nt.links.new(r.outputs[0],bsdf.inputs['Roughness'])
    m.use_backface_culling=not double
    if alpha=='alpha':
        m.blend_method='CLIP' if hasattr(m,'blend_method') else None
        try: m.alpha_threshold=scissor
        except Exception: pass
    return m
bark=lambda size=1024,name='bark': mk_mat(name,f"{ACG}/Bark014/Bark014_1K-JPG_Color.jpg",f"{ACG}/Bark014/Bark014_1K-JPG_NormalGL.jpg",f"{ACG}/Bark014/Bark014_1K-JPG_Roughness.jpg",size,double=False)
frond=lambda: mk_mat('frond',f"{TEX}/frond_atlas.png",None,None,1024,alpha='alpha',double=True)

def frames(pts):
    # parallel transport
    T=[(pts[min(i+1,len(pts)-1)]-pts[max(i-1,0)]).normalized() for i in range(len(pts))]
    up=Vector((0,0,1)) if abs(T[0].z)<0.95 else Vector((1,0,0))
    N=(up-T[0]*up.dot(T[0])).normalized(); out=[]
    for i,t in enumerate(T):
        if i>0:
            N=(N-t*N.dot(t))
            if N.length<1e-5: N=t.orthogonal()
            N=N.normalized()
        out.append((t,N,t.cross(N)))
    return out
class MB:
    def __init__(s): s.v=[]; s.f=[]; s.uv=[]
    def tube(s,pts,radii,sides,vscale,u0=0.0,cap=True,rough=0.0,rng=None):
        fr=frames(pts); base=len(s.v); L=0.0
        for i,(t,n,b) in enumerate(fr):
            if i>0: L+=(pts[i]-pts[i-1]).length
            for k in range(sides+1):
                a=2*math.pi*k/sides
                r=radii[i]*(1+ (rng.uniform(-rough,rough) if rng and rough and k<sides else 0))
                s.v.append(pts[i]+(n*math.cos(a)+b*math.sin(a))*r)
                s.uv.append((k/sides*max(1,round(radii[0]*2*math.pi/0.35)) , L*vscale))
        # fix seam duplicates: last ring vert duplicates first -> separate vertex, fine
        for i in range(len(pts)-1):
            for k in range(sides):
                a=base+i*(sides+1)+k; b_=a+1; c=a+sides+1+1; d=a+sides+1
                s.f.append((a,b_,c,d))
    def card(s,pts,widths,uvrect,flip=False,sideaxis=None):
        # strip along pts, width across 'sideaxis' (or computed)
        base=len(s.v); u0,v0,u1,v1=uvrect
        n=len(pts)
        for i,p in enumerate(pts):
            t=(pts[min(i+1,n-1)]-pts[max(i-1,0)]).normalized()
            sd=sideaxis if sideaxis is not None else t.cross(Vector((0,0,1)))
            sd=(sd-t*sd.dot(t)).normalized()
            w=widths[i]
            s.v.append(p-sd*w*0.5); s.v.append(p+sd*w*0.5)
            vv=v0+(v1-v0)*i/(n-1)
            s.uv.append((u0,vv)); s.uv.append((u1,vv))
        for i in range(n-1):
            a=base+2*i
            s.f.append((a,a+1,a+3,a+2))
    def build(s,name,mat_idx_fn=None):
        pass
def finish(name,groups,mats):
    # groups: list of MB in same order as mats
    obj_parts=[]
    me=bpy.data.meshes.new(name)
    allv=[];allf=[];alluv=[];fmat=[]
    for mi,g in enumerate(groups):
        off=len(allv)
        allv+= [tuple(v) for v in g.v]
        for f in g.f: allf.append(tuple(i+off for i in f)); fmat.append(mi)
        alluv+=g.uv
    me.from_pydata(allv,[],allf)
    uvl=me.uv_layers.new(name='UVMap')
    for p in me.polygons:
        for li in p.loop_indices:
            vi=me.loops[li].vertex_index
            uvl.data[li].uv=alluv[vi]
    for m in mats: me.materials.append(m)
    for p,mi in zip(me.polygons,fmat): p.material_index=mi
    me.update(); me.validate()
    for p in me.polygons: p.use_smooth=True
    ob=bpy.data.objects.new(name,me); bpy.context.scene.collection.objects.link(ob)
    return ob
def export(ob,path):
    bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True); bpy.context.view_layer.objects.active=ob
    os.makedirs(os.path.dirname(path),exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path,export_format='GLB',export_image_format='NONE',export_yup=True,use_selection=True,export_cameras=False,export_lights=False,export_jpeg_quality=80)
    t=sum(len(p.vertices)-2 for p in ob.data.polygons)
    print("GEN",path,t,"tris",round(os.path.getsize(path)/1e6,2),"MB",flush=True)

# ---------------------------------------------------------------- conifer
CELLS=[(0,0.5,0.5,1.0),(0.5,0.5,1.0,1.0),(0,0,0.5,0.5),(0.5,0,1.0,0.5)]  # u0,v0,u1,v1 (v up in gltf import: image v flipped handled by blender uv)
def conifer(name,seed,H=12.0,Rmax=2.4,bare=0.14,whorl=0.36,nb=7,droop=0.3,kind='fir',lod=False):
    rng=random.Random(seed)
    trunk=MB(); fr=MB()
    tr=H*0.018+0.05
    # trunk with slight lean/sweep
    n=14; pts=[]; rad=[]
    lean=Vector((rng.uniform(-1,1),rng.uniform(-1,1),0)).normalized()*rng.uniform(0.0,0.0025*H)
    for i in range(n+1):
        t=i/n; z=t*H
        p=Vector((lean.x*z*t+math.sin(t*5+seed)*0.06*(1-t),lean.y*z*t+math.cos(t*4+seed)*0.06*(1-t),z))
        pts.append(p); rad.append(tr*(1.55*(1-t)**1.2*0.55+0.12+ (1.0-t)*0.9+0.0)*(0.38 if False else 1))
    rad=[max(0.015,tr*(1.0-0.93*(i/n)**0.9)*(1.35 if i==0 else 1.0)) for i in range(n+1)]
    trunk.tube(pts,rad,8 if not lod else 5,0.35,rough=0.0)
    def trunkpos(z):
        t=z/H; return Vector((lean.x*z*t+math.sin(t*5+seed)*0.06*(1-t),lean.y*z*t+math.cos(t*4+seed)*0.06*(1-t),z))
    z=H*bare+rng.uniform(0,0.2); ph=rng.uniform(0,6.28); cnt=0
    while z<H-0.4:
        t=(z-H*bare)/(H*(1-bare))
        L=Rmax*((1-t)**0.88)*(0.85+0.3*rng.random())+0.25
        if kind=='spruce': L*= (1.0+0.15*math.sin(t*9))
        k=nb if t<0.75 else max(4,nb-2)
        if lod: k=max(4,k-2)
        ph+=rng.uniform(0.3,1.1)
        for j in range(k):
            a=ph+2*math.pi*j/k+rng.uniform(-0.25,0.25)
            dirh=Vector((math.cos(a),math.sin(a),0))
            ll=L*rng.uniform(0.8,1.15)
            dr=droop*(1-0.8*t)*ll   # tips droop on lower branches, rise on upper
            base=trunkpos(z+rng.uniform(-0.05,0.05))
            segs=4
            bp=[];bw=[]
            for s in range(segs+1):
                u=s/segs
                p=base+dirh*(ll*u*0.97)+Vector((0,0,-dr*(u**1.6)+0.16*ll*math.sin(u*math.pi)*(0.4+t*0.5)))
                bp.append(p); bw.append(ll*0.52*(0.55+0.9*math.sin(math.pi*min(1,u*0.8+0.12)))**1 if True else 0)
            bw=[w*(0.9 if kind=='fir' else 1.05) for w in bw]
            cell=CELLS[rng.randrange(4)]
            # main horizontal-ish card, plus a V-tilted second card (double sided)
            sd1=Vector((0,0,1)).cross(dirh).normalized()
            fr.card(bp,bw,cell,sideaxis=sd1)
            tilt=rng.choice([-1,1])*0.7
            sd2=(sd1*math.cos(tilt)+Vector((0,0,1))*math.sin(tilt)).normalized()
            fr.card(bp,[w*0.85 for w in bw],CELLS[rng.randrange(4)],sideaxis=sd2)
            # bough stick for lower branches
            if not lod and L>1.2 and rng.random()<0.7:
                trunk.tube(bp[:3],[0.025+0.012*ll*0.3,0.018,0.01],4,0.3)
        z+=whorl*(0.7+0.6*t)*(1.0+0.15*rng.random())
        cnt+=1
    # leader
    top=trunkpos(H)
    for q in range(3):
        a=q*2.094+rng.uniform(0,1)
        d=Vector((math.cos(a)*0.25,math.sin(a)*0.25,1)).normalized()
        pp=[trunkpos(H-0.9)+Vector((0,0,0)), top+d*0.9]
        pp=[trunkpos(H-1.0)+d*0.0,trunkpos(H-0.3),top+d*0.8]
        fr.card(pp,[0.9,0.7,0.1],CELLS[q],sideaxis=Vector((math.cos(a+1.57),math.sin(a+1.57),0)))
    mb=bark(512 if not lod else 256,'bark'); mf=frond()
    ob=finish(name,[trunk,fr],[mb,mf])
    return ob

def pine(name,seed,H=15.0):
    rng=random.Random(seed)
    trunk=MB(); fr=MB()
    tr=H*0.016+0.08
    n=16; pts=[];lean=Vector((rng.uniform(-1,1),rng.uniform(-1,1),0)).normalized()*rng.uniform(0.0,0.003*H)
    def tp(z):
        t=z/H; return Vector((lean.x*z*t+math.sin(t*3+seed)*0.35*t,lean.y*z*t+math.cos(t*2.5+seed)*0.35*t,z))
    for i in range(n+1): pts.append(tp(i/n*H))
    rad=[max(0.02,tr*(1.0-0.88*(i/n)**1.1)*(1.4 if i==0 else 1.0)) for i in range(n+1)]
    trunk.tube(pts,rad,8,0.35)
    nbr=rng.randint(15,20)
    for b in range(nbr):
        z=H*rng.uniform(0.42,0.97)
        a=rng.uniform(0,6.28); ll=rng.uniform(1.8,3.6)*(1.15-0.6*(z/H-0.5))
        d=Vector((math.cos(a),math.sin(a),0))
        base=tp(z)
        bp=[base+d*ll*u+Vector((0,0,0.25*ll*u*(1-0.3*u)*math.sin(u*2)+0.05)) for u in (0,0.3,0.6,1.0)]
        trunk.tube(bp,[0.07*(1-z/H*0.5),0.05,0.035,0.02],5,0.3)
        # needle tuft at tip
        c=bp[-1]
        for q in range(6):
            aa=q*1.047+rng.uniform(-0.3,0.3)
            dd=Vector((math.cos(aa),math.sin(aa),rng.uniform(0.05,0.55))).normalized()
            L=rng.uniform(1.6,2.4)
            pp=[c-dd*0.2,c+dd*L*0.5+Vector((0,0,0.1)),c+dd*L+Vector((0,0,-0.15))]
            fr.card(pp,[L*0.45,L*0.6,L*0.2],CELLS[rng.randrange(4)],sideaxis=Vector((0,0,1)).cross(dd).normalized())
            fr.card(pp,[L*0.4,L*0.55,L*0.2],CELLS[rng.randrange(4)],sideaxis=(Vector((0,0,1)).cross(dd).normalized()*0.5+Vector((0,0,1))*0.8).normalized())
    # crown tuft
    top=tp(H)
    for q in range(8):
        aa=q*0.785+rng.uniform(-0.2,0.2); dd=Vector((math.cos(aa)*0.8,math.sin(aa)*0.8,rng.uniform(0.2,0.9))).normalized(); L=rng.uniform(1.4,2.0)
        pp=[top-dd*0.2,top+dd*L*0.5,top+dd*L+Vector((0,0,-0.2))]
        fr.card(pp,[L*0.5,L*0.65,L*0.2],CELLS[rng.randrange(4)],sideaxis=Vector((0,0,1)).cross(dd).normalized())
    mb=bark(512,'bark'); mf=frond()
    return finish(name,[trunk,fr],[mb,mf])

# ---------------------------------------------------------------- bare deciduous
def bare_tree(name,seed,H=11.0,spread=1.0,max_order=4,sides=(9,6,4,3,3,3),lod=False,budget=None):
    rng=random.Random(seed)
    trunk=MB()
    tr=H*0.016+0.07
    def grow(p0,d,length,r0,order,remaining):
        npt=max(3,int(length/(0.9 if order<2 else 0.6))+2)
        pts=[p0]; d=d.copy(); p=p0.copy()
        step=length/(npt-1)
        for i in range(1,npt):
            # random bend + gravitropism
            bend=Vector((rng.uniform(-1,1),rng.uniform(-1,1),rng.uniform(-0.4,0.6)))*(0.16+0.1*order)
            d=(d+bend*(0.6 if order==0 else 1.0)).normalized()
            if order>=2: d=(d+Vector((0,0,0.05))).normalized()
            p=p+d*step; pts.append(p.copy())
        rad=[max(0.006,r0*(1-0.82*(i/(npt-1))**0.9)) for i in range(npt)]
        trunk.tube(pts,rad,sides[min(order,len(sides)-1)] if not lod else (max(3,sides[min(order,5)]-3)),0.3 if order<2 else 0.6,rough=0.0)
        if order>=max_order or length<0.5: return
        # children
        nch=int(length*(1.7 if order==0 else 1.3))+ (2 if order<2 else 1)
        if order==0: nch=int(H*2.3)
        nch=min(nch,[int(H*2.3),8,5,3,2,2][order])
        for c in range(nch):
            t=rng.uniform(0.18,0.97) if order>0 else rng.uniform(0.32,0.99)
            i=min(npt-2,int(t*(npt-1))); pp=pts[i].lerp(pts[i+1],t*(npt-1)-i)
            tang=(pts[i+1]-pts[i]).normalized()
            az=rng.uniform(0,6.28)
            side=tang.orthogonal().normalized(); side2=tang.cross(side)
            ang=math.radians(rng.uniform(28,62) if order<2 else rng.uniform(35,70))
            nd=(tang*math.cos(ang)+(side*math.cos(az)+side2*math.sin(az))*math.sin(ang)).normalized()
            if order==0: nd.z=max(nd.z,0.15) if t>0.5 else max(nd.z,-0.05); nd=nd.normalized()
            rr=rad[i]
            clen=length*rng.uniform(0.35,0.62)*(1.0 if order>0 else (0.55+0.55*(1-t))*spread*1.35)
            if order==0: clen=H*rng.uniform(0.3,0.5)*(1.0-0.5*t)*spread*(1.0+0.25*(1-t))
            grow(pp,nd,clen,rr*rng.uniform(0.42,0.6),order+1,remaining)
    # trunk: lean + flare
    root=Vector((0,0,0))
    # main stem
    grow(root,Vector((rng.uniform(-0.05,0.05),rng.uniform(-0.05,0.05),1.0)).normalized(),H*0.8,tr,0,0)
    # root flare
    for q in range(5):
        a=q*1.256+rng.uniform(-0.3,0.3)
        d=Vector((math.cos(a),math.sin(a),0))
        trunk.tube([d*0.02+Vector((0,0,0.55)),d*(tr*1.3)+Vector((0,0,0.12)),d*(tr*2.6)+Vector((0,0,-0.03))],[tr*0.6,tr*0.5,tr*0.3],5,0.3)
    mb=bark(1024 if not lod else 256,'bark')
    return finish(name,[trunk],[mb])

def run():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    jobs=[]
    for i,(H,R,seed,kind) in enumerate([(13,2.4,11,'fir'),(11,2.0,23,'fir'),(15,2.7,35,'spruce')]):
        ob=conifer(f"fir_{i+1}",seed,H=H,Rmax=R,kind=kind); export(ob,f"{OUT}/trees/conifer_{i+1}.glb")
    ob=conifer("fir_s",5,H=4.5,Rmax=1.15,bare=0.08,whorl=0.28,nb=6); export(ob,f"{OUT}/trees/conifer_small.glb")
    for i,seed in enumerate((41,57)):
        ob=pine(f"pine_{i+1}",seed); export(ob,f"{OUT}/trees/pine_{i+1}.glb")
    for i,(H,sp,seed) in enumerate([(11,1.0,3),(13,1.0,8),(9.5,0.9,19),(12,1.0,31),(10,1.0,44)]):
        ob=bare_tree(f"bare_{i+1}",seed,H=H,spread=sp); export(ob,f"{OUT}/trees/bare_{i+1}.glb")
        bpy.data.objects.remove(ob)
        ob=bare_tree(f"bare_{i+1}_lod",seed,H=H,spread=sp,max_order=2,lod=True); export(ob,f"{OUT}/trees/bare_{i+1}_lod.glb")
run()
