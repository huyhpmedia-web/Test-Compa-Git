import sys; sys.path.insert(0,'.')
from au import *
exec(open('build_amb.py').read().split('S_=lambda')[0].split('rng=')[0].replace("spec=","#"))  if False else None
OUT='/home/user/Test-Compa-Git/whiteout/audio/'
def chainS(parts,xf):
    n=int(xf*SR); y=parts[0].copy()
    for p in parts[1:]:
        t=np.linspace(0,np.pi/2,n)
        a=y[:,-n:]*np.cos(t)+p[:,:n]*np.sin(t)
        y=np.concatenate([y[:,:-n],a,p[:,n:]],axis=1)
    return y
def cut(x,a,b): return x[:,int(a*SR):int(b*SR)]
def fin(x,rms,pkdb=-1.0):
    x=x-x.mean(axis=1,keepdims=True)
    cur=20*np.log10(np.sqrt(np.mean(x**2))+1e-12); x=x*10**((rms-cur)/20)
    lim=10**(pkdb/20); return np.tanh(x/lim)*lim
def tilec(x,n):
    reps=int(np.ceil(n/x.shape[1])); return np.tile(x,(1,reps))[:,:n]
def Ls(p): return load(p,stereo=True)
def save(name,x,xf):
    x=loopify(x,xf); x=fin(x,RMS[name]); ogg_out(OUT+name+'.ogg',x,stereo=True,q=4); print(name,x.shape[1]/SR,'s')
RMS={'music_title':-21,'music_safe':-25,'music_tension':-22,'music_chase':-19,'music_boss':-19,'music_ending':-21}
save('music_title',cut(Ls('mus/wes_decoherence.ogg'),15,135),5)
save('music_safe',Ls('stn/mus_day.ogg'),4)
nt=Ls('stn/mus_night.ogg'); dr=Ls('stn/mus_dread.ogg')
base=chainS([nt,cut(nt,0,40)],4)
n=base.shape[1]+int(5*SR)  # loopify trims xf at end; layer must cover
dl=tilec(dr,base.shape[1])
save('music_tension',base+0.28*fin(dl,-30)/10**(-30/20)*10**(-22/20)*0+0.3*dl*(np.sqrt(np.mean(base**2))/np.sqrt(np.mean(dl**2))),5)
save('music_chase',cut(Ls('mus/wes_primal-carnage.ogg'),6,130),4)
save('music_boss',Ls('stn/mus_boss.ogg'),3)
save('music_ending',cut(Ls('mus/wes_helios.ogg'),20,140),6)
