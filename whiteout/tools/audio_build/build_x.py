exec(open('build_en.py').read().split('# ---- zombie')[0])
# hound howl/bite
wh=L('stn/wolf_howl.ogg'); dh=L('stn/dog_howl.ogg')
print('howl slices',[(round(a/SR,1),round((b-a)/SR,1)) for a,b in slices(wh,-30,0.4,0.5)][:8])
ws_=[wh[a:b] for a,b in slices(wh,-30,0.4,1.5)]
dhs=[dh[a:b] for a,b in slices(dh,-30,0.4,1.0)]
cand=[s for s in ws_+dhs if len(s)/SR<8]
for i,l in enumerate('ab'):
    V('hound_howl_'+l,[(0,fade(pit(cand[i],1.05),0.2,0.6),1.0),(0.3,crackle(90+i,min(3,len(cand[i])/SR),-24),1.0)],db=-3,fo=0.8)
hf=[T('stn/hit_flesh.ogg',0),T('stn/hit_flesh.ogg',1),T('stn/hit_head.ogg',0)]
snr=L('ia/sfx_dog_snarl.ogg'); br2=sl('stn/dog_bark.ogg',-30,0.06,0.1,0.15,1.2)
for i,l in enumerate('abc'):
    V('hound_bite_'+l,[(0,hf[i],0.9),(0,g(trim(snr),-3),1.0),(0.02,g(br2[i],-8),1.0)],length=int(0.8*SR),db=-2,fo=0.1)
    V('husk_armor_'+l,[(0,ken('im_plate_light_00%d'%i),1.0),(0,g(hp(IB[(i*2+1)%len(IB)],1500),-6),1.0),(0,g(ken('im_tin_medium_00%d'%i),-6),1.0)],length=int(0.6*SR),db=-3,fo=0.1)
    V('husk_crack_'+l,[(0,IB[(i*3+2)%len(IB)],1.0),(0.05,ken('im_plate_heavy_00%d'%i),0.7),(0,pit(trim(ic)[:int(1.0*SR)],0.9),0.5)],length=int(1.4*SR),db=-2,fo=0.2)
    V('husk_shatter_'+l,[(0,pit(trim(ic),0.9+0.1*i),1.0),(0,g(ken('im_glass_heavy_00%d'%i),-2),1.0),(0.05,g(ken('im_plate_heavy_00%d'%(i+1)),-6),1.0)],length=int(2.4*SR),db=-1,fo=0.4)
    st=int((10+i*22)*SR); wl=fade(gw[st:st+int(3.6*SR)],0.4,0.8)
    V('siren_hum_'+l,[(0,pit(wl,1.0),0.9),(0,g(hum_voice(3.6,[300,340,380][i],5.5,0.012,i),-4),1.0),(0,g(hum_voice(3.6,[450,510,570][i],5.5,0.012,i+5),-9),1.0)],length=int(3.8*SR),db=-3,fo=1.0)
print('extra done')
