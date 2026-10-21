import numpy as np, subprocess, os, wave
SR=44100
S='/tmp/claude-0/-home-user-Test-Compa-Git/b7d788c3-cd16-57ba-98fb-70cb388fdafd/scratchpad/audsrc/'
def load(p, sr=SR, stereo=False):
    if not p.startswith('/'): p=S+p
    ch=2 if stereo else 1
    r=subprocess.run(['ffmpeg','-v','error','-i',p,'-f','f32le','-ac',str(ch),'-ar',str(sr),'-'],capture_output=True)
    x=np.frombuffer(r.stdout,dtype=np.float32).astype(np.float64)
    return x.reshape(-1,2).T if stereo else x
def env(x,win=0.01):
    n=max(1,int(SR*win)); k=np.ones(n)/n
    return np.sqrt(np.convolve(x*x,k,'same')+1e-12)
def slices(x,thr_db=-38,gap=0.12,minlen=0.08):
    e=env(x,0.01); pk=e.max(); on=e>pk*10**(thr_db/20)
    # close small gaps
    out=[];i=0;n=len(x);g=int(gap*SR)
    idx=np.flatnonzero(on)
    if len(idx)==0: return out
    s=idx[0];p=idx[0]
    for j in idx[1:]:
        if j-p>g:
            if p-s>minlen*SR: out.append((s,p))
            s=j
        p=j
    if p-s>minlen*SR: out.append((s,p))
    return [(max(0,a-int(0.005*SR)),min(n,b+int(0.04*SR))) for a,b in out]
def fade(x,i=0.003,o=0.02):
    x=x.copy(); a=int(i*SR); b=int(o*SR)
    if a>0 and len(x)>a: x[:a]*=np.linspace(0,1,a)
    if b>0 and len(x)>b: x[-b:]*=np.linspace(1,0,b)
    return x
def hp(x,fc,order=2):
    from numpy.fft import rfft,irfft
    X=rfft(x); f=np.fft.rfftfreq(len(x),1/SR); X*=1/np.sqrt(1+(fc/np.maximum(f,1e-9))**(2*order)); return irfft(X,len(x))
def lp(x,fc,order=2):
    from numpy.fft import rfft,irfft
    X=rfft(x); f=np.fft.rfftfreq(len(x),1/SR); X*=1/np.sqrt(1+(f/fc)**(2*order)); return irfft(X,len(x))
def bp(x,a,b): return lp(hp(x,a),b)
def resample(x,ratio):  # ratio>1 = higher pitch/shorter
    n=int(len(x)/ratio); return np.interp(np.arange(n)*ratio,np.arange(len(x)),x)
def peak_norm(x,db=-1.0):
    m=np.abs(x).max()+1e-12; return x*10**(db/20)/m
def rms_db(x): return 20*np.log10(np.sqrt(np.mean(x**2))+1e-12)
def norm_rms(x,db): return x*10**((db-rms_db(x))/20)
def softclip(x,drive=1.0): return np.tanh(x*drive)/np.tanh(drive)
def mix(*parts,length=None):
    L=length or max(int(o*SR)+len(p) for o,p,g in parts)
    y=np.zeros(L)
    for o,p,g in parts:
        o=int(o*SR); n=min(len(p),L-o)
        if n>0: y[o:o+n]+=p[:n]*g
    return y
def reverb(x,rt=0.6,wet=0.25,seed=1,pre=0.01):
    rng=np.random.default_rng(seed); n=int(rt*SR); t=np.arange(n)/SR
    ir=rng.standard_normal(n)*np.exp(-6.9*t/rt); ir=lp(ir,5000); ir[:int(pre*SR)]=0
    ir/=np.sqrt(np.sum(ir**2))
    from numpy.fft import rfft,irfft
    N=len(x)+n; y=irfft(rfft(x,N)*rfft(ir,N),N)
    return np.concatenate([x,np.zeros(n)])*(1-wet)+y*wet*1.0
def echo(x,d,fb,n=4):
    y=np.zeros(len(x)+int(d*SR*n)+1); y[:len(x)]+=x
    for k in range(1,n+1):
        o=int(d*SR*k); y[o:o+len(x)]+=x*(fb**k)
    return y
def wav_out(p,x,sr=SR,db=-1.0,dcfix=True):
    if dcfix: x=hp(x,15,1) if len(x)>2000 else x
    x=peak_norm(x,db) if db is not None else x
    x=np.clip(x,-1,1)
    with wave.open(p,'wb') as w:
        w.setnchannels(1);w.setsampwidth(2);w.setframerate(sr);w.writeframes((x*32767).astype('<i2').tobytes())
def ogg_out(p,x,stereo=False,q=4,sr=SR):
    x=np.clip(x,-1,1)
    ch=2 if stereo else 1
    data=(x.T if stereo else x).astype('<f4').tobytes()
    subprocess.run(['ffmpeg','-y','-v','error','-f','f32le','-ar',str(sr),'-ac',str(ch),'-i','-','-c:a','libvorbis','-q:a',str(q),p],input=data,check=True)
def loopify(x,xf):
    """Seamless loop by equal-power crossfading tail onto head. x 1-D or (2,N)."""
    n=int(xf*SR)
    if x.ndim==1:
        body=x[:-n].copy(); tail=x[-n:]; head=x[:n]
        t=np.linspace(0,np.pi/2,n)
        body[:n]=head*np.sin(t)+tail*np.cos(t)
        return body
    return np.stack([loopify(c,xf) for c in x])
