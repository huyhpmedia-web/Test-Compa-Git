import sys; sys.path.insert(0,'.')
from au import *
OUT='/home/user/Test-Compa-Git/whiteout/audio/'
os.makedirs(OUT,exist_ok=True)
_c={}
def L(p):
    if p not in _c: _c[p]=load(p)
    return _c[p]
def trim(x,thr=-45,pre=0.003,post=0.03):
    e=env(x,0.004); m=e>e.max()*10**(thr/20); i=np.flatnonzero(m)
    if len(i)==0: return x
    return x[max(0,i[0]-int(pre*SR)):min(len(x),i[-1]+int(post*SR))]
def ken(n): return trim(L('ken/%s.ogg'%n))
def T(p,i,thr=-35,gap=0.15,minlen=0.08):
    x=L(p); s=slices(x,thr,gap,minlen); a,b=s[min(i,len(s)-1)]; return x[a:b]
def seg(p,a,d): x=L(p); return x[int(a*SR):int((a+d)*SR)]
def g(x,db): return x*10**(db/20)
def pit(x,r): return resample(x,r)
def W(name,x,db=-1.0,fo=0.02):
    x=fade(x,0.002,fo); wav_out(OUT+name+'.wav',x,db=db); 
def lvl(x,db): return norm_rms(x,db)
def pk(x,db): return peak_norm(x,db)
def tail(x,t): return fade(x,0,t)
rng=np.random.default_rng(7)
def noise(n): return rng.standard_normal(int(n*SR))

# ---------- footsteps
for i,l in enumerate('abc'):
    W('step_snow_'+l, pk(ken('fs_snow_00%d'%i),-9))
    W('step_concrete_'+l, pk(ken('fs_concrete_00%d'%i),-9))
    W('step_wood_'+l, pk(ken('fs_wood_00%d'%i),-9))
    t=hp(ken('fs_concrete_00%d'%(i+2)),400)*1.0; t=mix((0,t,1.0),(0.0,g(ken('im_plate_light_00%d'%i),-14),1.0),length=int(0.5*SR))
    W('step_tile_'+l, pk(reverb(t,0.35,0.28,i),-9))
    m=ken('fs_concrete_00%d'%i); mt=pit(ken('im_metal_light_00%d'%i),0.85)
    W('step_metal_'+l, pk(mix((0,hp(m,200),0.8),(0.01,g(mt,-3),1.0),length=int(0.6*SR)),-9))
wsl=slices(L('stn/fs_water.ogg'),-28,0.05,0.12)
wsl=[s for s in wsl if 0.18<(s[1]-s[0])/SR<0.9][:12]
for i,l in enumerate('abc'):
    a,b=wsl[min(i*2+1,len(wsl)-1)]; W('step_water_'+l,pk(L('stn/fs_water.ogg')[a:b],-9),fo=0.06)

# ---------- weapons
pf=trim(L('ia/sfx_pistol_fire.ogg')); pf2=T('stn/gun_pistol.ogg',0)
x=mix((0,pf,1.0),(0,g(pf2,-4),1.0),length=int(1.0*SR)); W('shot_handgun',reverb(x,0.4,0.18))
sg=trim(L('ia/sfx_shotgun_sawed_off_fire.ogg')); sg2=T('stn/gun_shotgun.ogg',0)
x=mix((0,sg,1.0),(0,g(sg2,-3),1.0),length=int(1.5*SR)); W('shot_shotgun',reverb(x,0.5,0.2),fo=0.2)
rv=trim(L('ia/sfx_revolver_fire.ogg')); 
x=mix((0,pit(rv,0.85),1.0),(0,g(pit(pf2,0.8),-2),1.0),(0,g(lp(pit(sg2,0.7),700),-8),1.0),length=int(1.6*SR)); W('shot_magnum',reverb(x,0.6,0.22),fo=0.2)
bl=trim(L('ia/sfx_morphic_blaster.ogg')); th=lp(pit(sg2,0.5),500)
ex=trim(L('ken/sf_explosionCrunch_000.ogg'))
x=mix((0,g(th,-1),1.0),(0.02,g(lp(bl,3000),-6),1.0),(0.05,g(lp(ex,1200),-8),1.0),length=int(2.0*SR)); W('shot_launcher',reverb(x,0.5,0.2),fo=0.3)
W('dry_fire',pk(T('stn/fol_dry.ogg',0),-3))
ro=T('stn/fol_mag_out.ogg',0); mi=T('stn/fol_mag_in.ogg',0); ms=T('stn/fol_mag_in.ogg',2)
W('reload',pk(mix((0,ro,1.0),(0.55,mi,1.0),(1.15,ms,1.0),length=int(1.7*SR)),-3))
W('equip',pk(T('stn/fol_draw.ogg',0),-4))
sw=[T('stn/swing.ogg',i) for i in (1,2,3)]
for i,l in enumerate('abc'):
    W('knife_swing_'+l,pk(mix((0,sw[i],1.0),(0,g(pit(trim(L('ia/sfx_miss_%s.ogg'%['light','medium','heavy'][i])),0.8),-6),1.0)),-5))
ks=[ken_ for ken_ in ('rpg_knifeSlice','rpg_knifeSlice2','rpg_knifeSlice')]
hf=[T('stn/hit_flesh.ogg',0),T('stn/hit_flesh.ogg',1),T('stn/hit_head.ogg',1)]
for i,l in enumerate('abc'):
    W('knife_hit_'+l,pk(mix((0,ken(ks[i]),1.0),(0.02,g(hf[i],-3),1.0)),-2))
e1=trim(L('ia/sfx_explosion.ogg')); e2=T('stn/exp_near.ogg',0); 
x=mix((0,e1,0.8),(0,e2,0.9),(0,g(ex,-4),1.0),(0,g(lp(pit(e2,0.6),200),0),1.0),length=int(4.0*SR)); W('explosion',reverb(x,0.9,0.3),fo=0.8)

# ---------- player voice (male pain)
pv=slices(L('stn/pv_hurt.ogg'),-35,0.15,0.08)
for i,l in zip((1,3,6),'abc'):
    a,b=pv[i]; W('hurt_m_'+l,pk(L('stn/pv_hurt.ogg')[a:b],-3),fo=0.05)

# ---------- items / UI
W('heal',pk(reverb(mix((0,pit(ken('ui_bong_001'),1.25),1.0),(0.12,g(pit(ken('ui_pluck_002'),1.4),-3),1.0),length=int(1.4*SR)),1.0,0.35),-4),fo=0.4)
hb=L('bo/threat_heartbeat_60.mp3'); e=env(hb,0.01); st=int(np.argmax(e>e.max()*0.35))
W('heartbeat',pk(hb[max(0,st-int(0.03*SR)):st+int(0.9*SR)],-3),fo=0.1)
W('pickup',pk(mix((0,ken('rpg_handleSmallLeather2'),1.0),(0.05,g(ken('ui_pluck_001'),-6),1.0)),-4))
W('deny',pk(pit(ken('ui_error_002'),0.85),-6))
W('combine',pk(mix((0,trim(L('bo/sfx_fuse_insert.mp3')),1.0),(0.12,ken('rpg_metalClick'),1.0)),-4))
W('paper',pk(mix((0,ken('rpg_bookFlip1'),1.0),(0.3,ken('rpg_bookFlip2'),0.8)),-6),fo=0.05)
W('click',pk(trim(L('bo/sfx_flashlight_click.mp3')),-5))
W('ui_select',pk(ken('ui_select_002'),-8)); W('ui_move',pk(ken('ui_tick_001'),-10))
for i,l in enumerate('ab'):
    W('door_open_'+l,pk(mix((0,ken('rpg_doorOpen_%d'%(i+1)),1.0),(0.1,g(ken('rpg_creak%d'%(i+1)),-4),1.0)),-3),fo=0.1)
W('door_locked',pk(mix((0,trim(L('bo/sfx_door_handle.mp3')),1.0),(0.5,g(ken('rpg_metalClick'),-3),1.0)),-3))
W('unlock',pk(mix((0,T('bo/sfx_door_unlock.mp3',0),1.0),(0,g(ken('rpg_metalLatch'),-4),1.0),length=int(1.2*SR)),-3))
W('alarm',pk(seg('oga/oga-levelup-powerup__Alarm.wav',0,3.2),-4),fo=0.05)
for i,l in enumerate('abc'):
    gl=[T('stn/imp_glass.ogg',0),T('stn/imp_glass.ogg',1),T('stn/imp_glass.ogg',2)][i]
    W('glass_break_'+l,pk(mix((0,gl,1.0),(0,g(ken('im_glass_heavy_00%d'%i),-5),1.0),length=int(1.6*SR)),-2),fo=0.3)
im=[T('stn/imp_metal.ogg',0),T('stn/imp_metal.ogg',2),T('stn/imp_metal.ogg',3)]
for i,l in enumerate('abc'):
    W('metal_impact_'+l,pk(mix((0,ken('im_metal_heavy_00%d'%i),1.0),(0,g(im[i],-4),1.0),length=int(1.2*SR)),-2),fo=0.2)
dr=slices(L('bo/ambient_drip_01.mp3'),-30,0.3,0.05)
dsl=[s for s in dr if (s[1]-s[0])/SR<1.5][:3]
for i,l in enumerate('abc'):
    a,b=dsl[min(i,len(dsl)-1)]; W('water_drip_'+l,pk(reverb(L('bo/ambient_drip_01.mp3')[a:b],0.8,0.2,i),-6),fo=0.3)
# elevator: motor hum (Kenney sci-fi engine) + ding
eng=lp(L('ken/sf_spaceEngine_001.ogg')[:int(5*SR)],900)
W('elevator',pk(mix((0,fade(eng,0.8,0.8)*1.0,1.0),(4.5,g(pit(ken('ui_bong_001'),1.1),-2)*1.0,1.0),length=int(5.8*SR)),-3),fo=0.3)
dg=resample(L('fd/resonant_concrete_drag_cc0.mp3')[int(2*SR):int(5*SR)],1.4)
W('shutter',pk(mix((0,bp(dg,300,6000),1.0),(0,g(trim(L('ia/sfx_door_open_gate.ogg')),-2),0.0+1.0),(2.0,trim(L('ia/sfx_door_close_gate.ogg')),1.0),length=int(3.0*SR)),-3),fo=0.2)
mg=L('fd/resonant_metal_groan_cc0.mp3'); 
W('valve',pk(mix((0,trim(L('ia/sfx_lever_pull.ogg')),0.8),(0.3,pit(mg[int(1*SR):int(3.2*SR)],1.3),0.8),(2.4,g(ken('rpg_metalLatch'),-2),1.0),length=int(3.0*SR)),-3),fo=0.2)
sa=L('stn/stg_night.ogg')[:int(5.5*SR)]; sb=L('bo/scares_scare_sting_general.mp3')[:int(5.5*SR)]
W('stinger_a',pk(sa,-3),fo=1.0); W('stinger_b',pk(sb,-3),fo=1.0)
W('item_get',pk(reverb(trim(L('oga/oga-levelup-powerup__Upper01.wav')),0.6,0.2),-5),fo=0.3)
fi=L('stn/fire_ignite.ogg'); fr=hp(L('stn/fire_roar.ogg')[:int(2.2*SR)],1500)
W('flare_ignite',pk(mix((0,fi,1.0),(0.3,g(fade(fr,0.2,0.8),-8),1.0),length=int(2.6*SR)),-3),fo=0.5)
ifr=L('fd/resonant_ice_fracture_cc0.mp3'); oi=L('fd/frostwrithe_organic_ice_cc0.mp3')
isl=slices(ifr,-30,0.12,0.12); osl=slices(oi,-30,0.12,0.12)
print('ice slices',len(isl),len(osl),[round((b-a)/SR,2) for a,b in isl[:10]],[round((b-a)/SR,2) for a,b in osl[:10]])
pool=[ifr[a:b] for a,b in isl if 0.2<(b-a)/SR<1.6]+[oi[a:b] for a,b in osl if 0.2<(b-a)/SR<1.6]
for i,l in enumerate('abc'):
    W('ice_crack_'+l,pk(pool[(i*3)%len(pool)],-3),fo=0.1)
ic=L('fd/frostwrithe_icicle_collapse_cc0.mp3')
for i,l in enumerate('ab'):
    W('ice_shatter_'+l,pk(mix((0,trim(ic) if i==0 else pit(trim(ic),1.15),1.0),(0,g(ken('im_glass_light_00%d'%i),-6),1.0),length=int(2.2*SR)),-2),fo=0.4)
ws=L('stn/wind_strong.ogg'); ew=env(ws,0.5)
for i,l in enumerate('ab'):
    c=int(np.argmax(ew[int(5*SR+i*20*SR):int(20*SR+i*20*SR)]))+int(5*SR+i*20*SR)
    W('wind_gust_'+l,pk(ws[max(0,c-int(2.5*SR)):c+int(2.5*SR)],-4),fo=2.0)
print('sfx part 1 done')
