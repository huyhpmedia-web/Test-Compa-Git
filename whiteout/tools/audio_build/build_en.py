import sys; sys.path.insert(0,'.')
exec(open('build_sfx.py').read().split('# ---------- footsteps')[0])
sw=[T('stn/swing.ogg',i) for i in (1,2,3)]
ic=L('fd/frostwrithe_icicle_collapse_cc0.mp3')
mg=L('fd/resonant_metal_groan_cc0.mp3')
ifr=L('fd/resonant_ice_fracture_cc0.mp3')
def sl(p,thr=-35,gap=0.15,minlen=0.08,lo=0.2,hi=3.0):
    x=L(p); return [x[a:b] for a,b in slices(x,thr,gap,minlen) if lo<=(b-a)/SR<=hi]
def win(p,a,d): return seg(p,a,d)
def ice_bits():
    pl=[]
    for p in ('fd/resonant_ice_fracture_cc0.mp3','fd/frostwrithe_organic_ice_cc0.mp3'):
        x=L(p); pl+=[x[a:b] for a,b in slices(x,-30,0.12,0.12) if 0.08<(b-a)/SR<0.8]
    return pl
IB=ice_bits()
def crackle(i,dur,gain=-14):
    y=np.zeros(int(dur*SR)); r=np.random.default_rng(100+i)
    for k in range(int(dur*7)):
        b=IB[r.integers(len(IB))]; b=hp(b,2500)*0.5 if len(b)>100 else b
        o=r.integers(0,max(1,len(y)-len(b)-1)); n=min(len(b),len(y)-o); y[o:o+n]+=b[:n]*r.uniform(0.3,1)
    return g(peak_norm(y),gain)
def V(name,parts,length=None,db=-2,fo=0.15):
    x=mix(*parts,length=length); W(name,pk(x,db),fo=fo)
def hum_voice(dur,f0=380,vib=5.5,amt=0.012,seed=0):
    t=np.arange(int(dur*SR))/SR; r=np.random.default_rng(seed)
    ph=2*np.pi*np.cumsum(f0*(1+amt*np.sin(2*np.pi*vib*t))/SR)
    y=sum(np.sin(ph*k+r.uniform(0,6))*a for k,a in ((1,1),(2,.4),(3,.25),(4,.12)))
    return y*np.sin(np.pi*t/dur)**1.5
gw=L('fd/remnant_ghost_wails_cc0.mp3')
# ---- zombie
zg=sl('stn/zv_growl.ogg',lo=1.5); zp=sl('stn/zv_pain.ogg',lo=0.3); zd=sl('stn/zv_death.ogg',lo=0.8); za=sl('stn/zv_attack.ogg',lo=0.5)
oz=[trim(L('oga/oga-zombies__zombies__zombie-%d.wav'%i)) for i in (16,17,18,19,21)]
print(len(zg),len(zp),len(zd),len(za))
for i,l in enumerate('abc'):
    V('zombie_groan_'+l,[(0,pit(zg[i],0.95),1.0),(0.1,crackle(i,len(zg[i])/SR),1.0)],db=-4,fo=0.3)
    V('zombie_hit_'+l,[(0,zp[[0,3,4][i]%len(zp)],1.0),(0,g(ken('im_soft_heavy_00%d'%i),-6),1.0)],db=-3)
    V('zombie_death_'+l,[(0,zd[i%len(zd)],1.0),(0.2,crackle(i+5,1.2,-16),1.0),(0.5,g(ken('im_soft_heavy_00%d'%(i+2)),-4),1.0)],db=-3,fo=0.3)
    V('zombie_attack_'+l,[(0,pit(za[[0,2,5][i]%len(za)],0.9),1.0),(0,g(oz[i],-4),1.0)],db=-3)
# ---- husk (armoured; giants/ogres + ice grinding)
gi=[trim(L('oga/oga-rpg-pack__RPG_Sound_Pack__NPC__giant__giant%d.wav'%i)) for i in range(1,6)]
og=[trim(L('oga/oga-rpg-pack__RPG_Sound_Pack__NPC__ogre__ogre%d.wav'%i)) for i in range(1,6)]
grind=L('fd/frostwrithe_ice_grind_cc0.mp3')
for i,l in enumerate('abc'):
    V('husk_groan_'+l,[(0,pit(lp(gi[i],2500),0.85),1.0),(0.1,g(grind[int(i*2*SR):int((i*2+1.6)*SR)],-6),1.0)],db=-3,fo=0.3)
    V('husk_hit_'+l,[(0,ken('im_plate_heavy_00%d'%i),1.0),(0,g(IB[(i*4)%len(IB)],-4),1.0),(0,g(ken('im_metal_heavy_00%d'%i),-6),1.0)],length=int(0.9*SR),db=-2)
    V('husk_death_'+l,[(0,pit(gi[3+i%2],0.8),1.0),(0.3,trim(ic),0.9),(0.2,g(ken('im_plate_heavy_00%d'%(i+2)),-4),1.0)],length=int(2.6*SR),db=-2,fo=0.5)
    V('husk_attack_'+l,[(0,pit(og[i],0.85),1.0),(0.05,g(grind[int((6-i)*0.5*SR):int(((6-i)*0.5+0.9)*SR)],-6),1.0),(0.3,g(ken('im_punch_heavy_00%d'%i),-3),1.0)],length=int(1.4*SR),db=-2)
# ---- siren (eerie resonant humming wail)
gw=L('fd/remnant_ghost_wails_cc0.mp3'); ew2=env(gw,0.2)
gsc=trim(L('fd/remnant_ghost_screech_cc0.mp3'))
zs=sl('stn/zv_screech.ogg',lo=1.0,hi=6.5)
for i,l in enumerate('abc'):
    st=int((8+i*17)*SR)
    wl=fade(gw[st:st+int(3.2*SR)],0.4,0.8)
    V('siren_groan_'+l,[(0,wl,1.0),(0,g(hum_voice(3.2,[330,370,415][i],seed=i),-12),1.0)],db=-4,fo=0.8)
    V('siren_hit_'+l,[(0,pit(gsc,[1.0,1.15,0.9][i]),0.8),(0,g(hum_voice(1.0,[420,470,380][i],4,0.02,i),-10),1.0)],length=int(1.2*SR),db=-3,fo=0.2)
    V('siren_death_'+l,[(0,pit(zs[i%len(zs)],1.1),1.0),(0.2,g(fade(gw[int((50+i*8)*SR):int((53+i*8)*SR)],0.2,1.2),-4),1.0)],length=int(3.6*SR),db=-3,fo=1.0)
    V('siren_attack_'+l,[(0,pit(L('stn/zv_scream.ogg')[int(i*1.2*SR):int((i*1.2+2.0)*SR)],1.1),1.0),(0,g(hum_voice(2.0,[520,560,490][i],7,0.03,i),-8),1.0)],length=int(2.2*SR),db=-2,fo=0.4)
# ---- hound
sn=L('stn/dog_snarl.ogg'); br=sl('stn/dog_bark.ogg',-30,0.06,0.1,0.15,1.2); yp=sl('stn/dog_yelp.ogg',lo=0.5,hi=2.0)
print('bark',len(br),'yelp',len(yp))
for i,l in enumerate('abc'):
    V('hound_groan_'+l,[(0,pit(fade(sn[int((i*3)*SR):int((i*3+2.4)*SR)],0.2,0.5),0.92),1.0),(0.2,crackle(10+i,2.0,-20),1.0)],db=-3,fo=0.5)
    V('hound_hit_'+l,[(0,yp[i%len(yp)],1.0)],db=-3,fo=0.1)
    V('hound_death_'+l,[(0,pit(yp[(i+1)%len(yp)],0.8),1.0),(0.3,g(ken('im_soft_heavy_00%d'%i),-5),1.0)],length=int(1.6*SR),db=-3,fo=0.3)
    V('hound_attack_'+l,[(0,pit(br[i%len(br)],0.92),1.0),(0.25,pit(br[(i+3)%len(br)],0.9),0.9),(0,g(crackle(20+i,1.0,-18),0),1.0)],length=int(1.2*SR),db=-2,fo=0.1)
# ---- burster
gu=L('stn/zv_gurgle.ogg'); sm=[trim(L('oga/oga-rpg-pack__RPG_Sound_Pack__NPC__slime__slime%d.wav'%i)) for i in range(1,11)]
gas=trim(L('ia/sfx_gas.ogg'))
for i,l in enumerate('abc'):
    V('burster_groan_'+l,[(0,fade(pit(gu[int((i*4)*SR):int((i*4+2.2)*SR)],0.95),0.2,0.4),1.0)],db=-4,fo=0.4)
    V('burster_hit_'+l,[(0,sm[i],1.0),(0,g(pit(zs[0][:int(0.4*SR)],0.9),-8),1.0)],length=int(0.8*SR),db=-3)
    V('burster_death_'+l,[(0,g(lp(pit(sm[3+i],0.8),3000),0),1.0),(0.15,g(trim(L('stn/hit_bullet.ogg')),-5),1.0),(0.15,g(ken('im_soft_heavy_00%d'%i),0),1.0),(0.2,g(gas,-2),1.0),(0.3,g(hp(noise(1.2),1200)*np.exp(-np.arange(int(1.2*SR))/SR*3),-12),1.0)],length=int(2.0*SR),db=-2,fo=0.5)
    V('burster_attack_'+l,[(0,pit(trim(L('stn/zv_spit.ogg')),[1.0,0.9,1.1][i]),1.0),(0.2,sm[6+i],0.8)],length=int(1.4*SR),db=-3)
# ---- hanger (creaking crystalline filaments)
tc=L('stn/tree_creak.ogg'); hc1=trim(L('bo/ambient_house_creak_01.mp3')); hc2=trim(L('bo/ambient_house_creak_02.mp3'))
for i,l in enumerate('abc'):
    V('hanger_groan_'+l,[(0,fade(pit(tc[int((3+i*6)*SR):int((3+i*6+3)*SR)],1.1),0.3,0.6),0.9),(0.2,crackle(30+i,2.8,-14),1.0),(0,g(hp(bp(hc1 if i%2==0 else hc2,300,5000),200),-4),1.0)],db=-4,fo=0.7)
    V('hanger_hit_'+l,[(0,IB[(i*5+1)%len(IB)],1.0),(0,g(pit(hc2,1.2),-4),1.0)],length=int(0.9*SR),db=-3,fo=0.15)
    V('hanger_death_'+l,[(0,pit(trim(ic),[0.9,1.0,1.1][i]),1.0),(0.1,g(pit(hc1,0.8),-3),1.0)],length=int(2.4*SR),db=-2,fo=0.5)
    V('hanger_attack_'+l,[(0,g(pit(hc2,1.0+i*0.1),0),1.0),(0.05,sw[i],0.9),(0.15,IB[(i*3)%len(IB)],0.8)],length=int(1.0*SR),db=-3,fo=0.15)
# ---- foreman (stalker)
hs=L('fd/aggregate_raw_heavy_stomp.mp3'); bd=L('fd/aggregate_raw_body_drag.mp3'); sb=L('fd/remnant_spirit_breathing_cc0.mp3')
hss=slices(hs,-30,0.2,0.15); print('stomps',[(round(a/SR,2),round((b-a)/SR,2)) for a,b in hss])
for i,l in enumerate('abc'):
    a,b=hss[0]; a=a+int(i*0.75*SR); stomp=lp(trim(hs[a:a+int(0.9*SR)],-30),450)
    V('foreman_step_'+l,[(0,pit(stomp,1.0-0.05*i),1.2),(0.12,g(bp(bd[int(i*1.2*SR):int((i*1.2+0.9)*SR)],80,3000),-3),1.0),(0.05,g(IB[(i*7+2)%len(IB)],-8),1.0)],length=int(1.5*SR),db=-1,fo=0.3)
    V('foreman_groan_'+l,[(0,fade(pit(og[i],0.7),0.1,0.4),1.0),(0,g(hum_voice(1.8,90+10*i,3,0.01,i),-6),1.0)],length=int(2.2*SR),db=-3,fo=0.5)
    V('foreman_hit_'+l,[(0,pit(zp[i%len(zp)],0.7),1.0),(0,g(ken('im_metal_heavy_00%d'%i),-3),1.0)],length=int(1.0*SR),db=-2)
    V('foreman_death_'+l,[(0,pit(gi[4],0.7),1.0),(0.5,g(L('stn/imp_body.ogg')[:int(1.2*SR)],-2),1.0),(0.3,trim(ic),0.8)],length=int(4.0*SR),db=-2,fo=1.0)
    V('foreman_attack_'+l,[(0,pit(L('stn/zv_roar.ogg')[int(i*2.6*SR):int((i*2.6+2.2)*SR)],0.8),1.0),(0.1,g(grind[:int(1.5*SR)],-8),1.0)],length=int(2.0*SR),db=-2,fo=0.4)
for i,l in enumerate('ab'):
    V('foreman_breath_'+l,[(0,fade(lp(pit(sb[int((2+i*8)*SR):int((2+i*8+3.5)*SR)],0.8),2500),0.5,0.8),1.0)],db=-8,fo=0.8)
# ---- bosses
wa=L('stn/zv_boss.ogg'); ag=L('fd/aggregate_raw_agony_roar.mp3'); an=L('fd/aggregate_raw_animal_groan.mp3'); dy=L('fd/aggregate_raw_dragon_dying_breath.mp3'); ph=L('fd/aggregate_raw_phantom_groan.mp3')
mo=L('stn/zv_moan.ogg'); bc=L('fd/resonant_building_collapse_cc0.mp3'); ifx=ifr
mnst=[trim(L('oga/oga-rpg-pack__RPG_Sound_Pack__NPC__gutteral_beast__mnstr%d.wav'%i)) for i in range(1,16)]
def choir(src,st,d,rates):
    parts=[(0,fade(pit(src[int(st*SR):int((st+d)*SR)],r),0.3,0.6),1.0/len(rates)**0.5) for r in rates]
    return parts
for i,l in enumerate('ab'):
    V('boss_choir_groan_'+l,choir(gw,12+i*20,4.0,[0.75,0.9,1.0,1.12,1.33])+choir(mo,2+i*9,4.0,[0.8,1.0,1.25])+[(0,g(hum_voice(4,95+25*i,0.3,0.004,i),-6),1.0)],length=int(4.2*SR),db=-4,fo=1.0)
    V('boss_choir_hit_'+l,choir(gsc,0,1,[0.7,0.85,1.0])+[(0,g(IB[(i*9)%len(IB)],-6),1.0)],length=int(1.3*SR),db=-3,fo=0.2)
    V('boss_choir_death_'+l,choir(gw,30+i*10,6.0,[0.6,0.75,0.9,1.0])+[(1.0,trim(ic),0.8),(1.5,g(trim(bc),-4),1.0)],length=int(6.5*SR),db=-2,fo=2.0)
    V('boss_choir_attack_'+l,choir(wa,3+i*3,2.5,[0.7,1.0])+[(0,g(pit(gsc,0.6),-4),1.0),(0.2,g(grind[:int(1.5*SR)],-6),1.0)],length=int(2.8*SR),db=-2,fo=0.4)
    V('boss_hauler_groan_'+l,[(0,fade(pit(ag,0.55+0.05*i),0.2,0.6),1.0),(0,g(pit(mg[int(i*3*SR):int((i*3+3)*SR)],0.7),-4),1.0),(0.2,g(crackle(60+i,3,-16),0),1.0)],length=int(3.4*SR),db=-2,fo=0.8)
    V('boss_hauler_hit_'+l,[(0,pit(mnst[i],0.6),1.0),(0,g(ken('im_metal_heavy_00%d'%i),-2),1.0),(0,g(ken('im_plate_heavy_00%d'%i),-4),1.0)],length=int(1.4*SR),db=-2,fo=0.2)
    V('boss_hauler_death_'+l,[(0,pit(dy,0.55),1.0),(0.5,pit(ag,0.5),0.8),(2.0,trim(bc),1.0),(2.0,g(L('fd/resonant_stone_debris_cc0.mp3')[:int(3*SR)],-3),1.0)],length=int(6.0*SR),db=-1,fo=1.5)
    V('boss_hauler_attack_'+l,[(0,pit(wa[int(3*SR):int(6*SR)],0.6),1.0),(0,pit(an,0.6),0.8),(0.3,g(lp(hs[:int(2*SR)],300),0),1.0),(0.3,g(ken('im_metal_heavy_00%d'%(i+2)),-2),1.0)],length=int(3.0*SR),db=-1,fo=0.5)
    # mother: an old(er) voice (breath/wail, pitched to a lower contralto) inside a vast cracking roar
    vo=fade(lp(pit(sb[int((6+i*10)*SR):int((6+i*10+4)*SR)],0.9),3500),0.4,0.8)
    wail=fade(pit(gw[int((20+i*25)*SR):int((20+i*25+4)*SR)],0.85),0.4,0.8)
    V('boss_mother_groan_'+l,[(0,vo,0.8),(0,wail,0.9),(0,g(crackle(70+i,4,-10),0),1.0),(0,g(lp(pit(ifx[int(i*3*SR):int((i*3+4)*SR)],0.5),900),-6),1.0)],length=int(4.2*SR),db=-4,fo=1.0)
    V('boss_mother_hit_'+l,[(0,pit(ph[int(i*1.5*SR):int((i*1.5+1.3)*SR)],0.9),1.0),(0,IB[(i*6+3)%len(IB)],0.9),(0,g(trim(ic)[:int(1.0*SR)],-6),1.0)],length=int(1.5*SR),db=-3,fo=0.2)
    V('boss_mother_death_'+l,[(0,wail,0.9),(0,pit(ag,0.6),0.9),(1.5,trim(ic),1.0),(2.0,g(trim(bc),-3),1.0),(2.5,g(pit(dy,0.7),-3),1.0)],length=int(7.0*SR),db=-1,fo=2.5)
    V('boss_mother_attack_'+l,[(0,pit(ag,0.65+0.05*i),1.0),(0,g(wail,-3),1.0),(0.1,crackle(80+i,3,-8),1.0),(0.2,g(pit(wa[int(9*SR):int(12*SR)],0.7),-3),1.0)],length=int(3.2*SR),db=-1,fo=0.6)
print('enemies done')
