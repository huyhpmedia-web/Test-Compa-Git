exec(open('build_en.py').read().split('# ---- zombie')[0])
import importlib.util
spec=importlib.util.spec_from_file_location('ga','/home/user/Test-Compa-Git/whiteout/tools/gen_audio.py'); ga=importlib.util.module_from_spec(spec); spec.loader.exec_module(ga)
bk=L('bo/sfx_breaker_engage.mp3')[:int(60*SR)]
s=slices(bk,-30,0.3,0.1); print([(round(a/SR,1),round((b-a)/SR,2)) for a,b in s[:6]])
th=bk[s[0][0]:s[0][0]+int(min(1.2,(s[0][1]-s[0][0])/SR)*SR)]
buzz=ga.foreman_lamp()[:int(2.2*SR)]; buzz=hp(buzz,120)*np.linspace(0,1,len(buzz))**2*np.exp(-np.arange(len(buzz))/SR/1.3)
V('lights_on',[(0,th,1.0),(0,g(ken('im_metal_heavy_001'),-6),1.0),(0.25,g(buzz,-4)*0.5,1.0),(0.9,g(ken('im_tin_medium_002'),-12),1.0)],length=int(2.4*SR),db=-3,fo=0.5)
