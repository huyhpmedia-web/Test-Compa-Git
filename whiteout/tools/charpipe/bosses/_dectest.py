import sys,os
sys.path.insert(0,'/home/user/Test-Compa-Git/whiteout/tools/charpipe/bosses')
from bosslib import *
reset()
for sz in [(1,1,1),(1,1,1.5)]:
    for st in (2.0,):
        ob=metaball_mesh("m",[((0,0,0),1.0,st,sz)],resolution=0.05,threshold=0.55)
        v=np.array([x.co[:] for x in ob.data.vertices]); print(sz,st,v.min(0),v.max(0))
        delete(ob)
ob=metaball_mesh("m",[((0,0,0),1.0,2.0,(1,1,1)),((0,0,0.5),1.0,2.0,(1,1,1))],resolution=0.05,threshold=0.55)
v=np.array([x.co[:] for x in ob.data.vertices]); print('two',v.min(0),v.max(0))
