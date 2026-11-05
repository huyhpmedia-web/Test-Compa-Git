import json,subprocess,sys,os
from concurrent.futures import ThreadPoolExecutor
ROOT=os.path.abspath("ph")
def get(u):
    return json.loads(subprocess.check_output(["curl","-s","-m","60",u]))
def fetch(n):
    out=f"{ROOT}/{n}"
    if os.path.exists(out+"/.done"): return n,"cached"
    try:
        d=get(f"https://api.polyhaven.com/files/{n}")
        g=d['gltf']['1k']['gltf']
    except Exception as e:
        return n,"ERR api "+repr(e)[:60]
    os.makedirs(out,exist_ok=True)
    jobs=[(g['url'],f"{out}/{n}_1k.gltf")]
    for k,v in g['include'].items():
        jobs.append((v['url'],f"{out}/{k}"))
    for u,p in jobs:
        os.makedirs(os.path.dirname(p),exist_ok=True)
        if os.path.exists(p) and os.path.getsize(p)>0: continue
        r=subprocess.call(["curl","-s","-f","-m","900","--retry","3","-o",p,u])
        if r!=0: return n,f"ERR dl {u}"
    open(out+"/.done","w").write("1")
    return n,"ok"
names=sys.argv[1:]
with ThreadPoolExecutor(6) as ex:
    for n,s in ex.map(fetch,names):
        print(n,s,flush=True)
