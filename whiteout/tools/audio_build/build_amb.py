import sys, importlib.util; sys.path.insert(0,'.')
from au import *
spec=importlib.util.spec_from_file_location('ga','/home/user/Test-Compa-Git/whiteout/tools/gen_audio.py'); ga=importlib.util.module_from_spec(spec); spec.loader.exec_module(ga)
OUT='/home/user/Test-Compa-Git/whiteout/audio/'
rng=np.random.default_rng(3)
def chain(parts,xf):
    n=int(xf*SR); y=parts[0].copy()
    for p in parts[1:]:
        t=np.linspace(0,np.pi/2,n); a=y[-n:]*np.cos(t)+p[:n]*np.sin(t)
        y=np.concatenate([y[:-n],a,p[n:]])
    return y
def to_len(x,L,xf=3):
    """make exactly L seconds seamless-loop material from x (tile via crossfade if short)"""
    n=int(L*SR)
    while len(x)<n+int(xf*SR): x=chain([x,x],xf)
    return loopify(x[:n+int(xf*SR)],xf)
def place(base,src,times,gain):
    for t in times:
        o=int(t*SR); m=min(len(src),len(base)-o)
        if m>0: base[o:o+m]+=src[:m]*gain
    return base
def fin(x,rms=-27,pkdb=-1.5):
    x=x-x.mean(); x=hp(x,20,1); x=norm_rms(x,rms)
    m=np.abs(x).max()
    if m>10**(pkdb/20): x=np.tanh(x/ (10**(pkdb/20)))*10**(pkdb/20)
    return x
def seam(x):
    return abs(x[0]-x[-1])
S_=lambda p:load(p)
# ---------------- wind
wm=S_('stn/wind_mid.ogg'); ws=S_('stn/wind_strong.ogg'); wl=S_('stn/wind_light.ogg')
x=chain([wm,ws[int(2*SR):]],4)[:int(84*SR)]
x=loopify(x,4)
x=x+0.3*to_len(lp(wl,1500),len(x)/SR-0,3)[:len(x)]
ogg_out(OUT+'amb_wind.ogg',fin(x,-25))
print('wind',len(x)/SR)
# ---------------- interior
tile=S_('bo/ambient_room_tone_tile.mp3'); base=S_('bo/ambient_room_tone_basement.mp3'); dl=S_('bo/ambient_drone_low_loop.mp3')
L=78
y=to_len(tile,L,3)+0.5*to_len(base,L,3)+0.35*to_len(lp(dl,400),L,3)
for k,p in enumerate(['bo/ambient_house_creak_01.mp3','bo/ambient_house_creak_02.mp3']):
    c=S_(p); c=c[:int(3*SR)]; place(y,c,rng.uniform(5,L-5,3),0.5)
ogg_out(OUT+'amb_interior.ogg',fin(y,-27)); print('interior',len(y)/SR)
# ---------------- mine
L=80
d1=S_('bo/ambient_drip_01.mp3'); d2=S_('bo/ambient_drip_02.mp3'); tc=S_('stn/tree_creak.ogg')
y=0.8*to_len(base,L,3)
y+=0.9*to_len(d1,L,2)*0.5+0.9*to_len(d2,L,2)*0.5
hm=np.tile(ga.hum(),4)[:int(L*SR)]; y+=0.5*lp(hm,500)*np.abs(y).max()*1.0/ (np.abs(hm).max()+1e-9)*0.5
for t0 in (6,19,33,47,61,72):
    s=tc[int(rng.uniform(0,20)*SR):][:int(rng.uniform(2.5,4)*SR)]; place(y,fade(lp(s,3000),0.3,0.8),[t0],0.6*np.abs(y).max()/ (np.abs(s).max()+1e-9)*0.25)
ogg_out(OUT+'amb_mine.ogg',fin(y,-27)); print('mine',len(y)/SR)
# ---------------- datacenter
fan=S_('ia/amb_027.ogg'); L=80
fl=fin(loopify(fan[:int(81.8*SR)],1.8),-25); L=len(fl)/SR
y=0.7*fl+0.8*fin(ga.server_hum(L),-27)[:len(fl)]+0.25*fin(to_len(tile,L,3),-30)[:len(fl)]
ogg_out(OUT+'amb_datacenter.ogg',fin(y,-26)); print('datacenter',len(y)/SR)
# ---------------- cavern
du=S_('ia/amb_013.ogg'); cv=S_('ia/amb_011.ogg'); L=80
ch=ga.crystal_chimes(L+3,seed=9,density=0.3)
ch=reverb(ch,2.5,0.5)[:len(ch)]
chl=loopify(ch,3)[:int(L*SR)]
ib=load('fd/resonant_ice_fracture_cc0.mp3')[:int(20*SR)]
y=fin(loopify(du[int(30*SR):int(30*SR)+int(83*SR)],3),-26)+0.6*fin(to_len(cv,L,3),-28)+0.5*fin(chl,-30)
tk=np.zeros(int(L*SR)); place(tk,hp(ib[int(rng.uniform(0,15)*SR):][:int(0.3*SR)],1500),rng.uniform(4,L-3,6),1.0); y+=0.15*fin(tk,-30)*0
ogg_out(OUT+'amb_cavern.ogg',fin(y,-26)); print('cavern',len(y)/SR)
