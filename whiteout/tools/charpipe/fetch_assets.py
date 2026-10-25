"""Fetch the CC0 MakeHuman system assets + CMU BVH clips used by build_characters.py (raw.githubusercontent.com only).
usage: python3 -I fetch_assets.py assets <outdir>        (clothes/hair/eyes/skins listed in ASSETS)
       python3 -I fetch_assets.py bvh <outdir> 35_01 09_01
"""
import sys, os, re, urllib.request
MH = "https://raw.githubusercontent.com/vidya-hub/makehuman-core/main/data/"
CMU = "https://raw.githubusercontent.com/una-dinosauria/cmu-mocap/master/data/"
ASSETS = ["clothes/male_casualsuit03", "clothes/male_casualsuit05", "clothes/male_worksuit01", "clothes/female_casualsuit01",
          "clothes/female_elegantsuit01", "clothes/shoes02", "clothes/shoes04", "clothes/shoes05", "clothes/shoes06",
          "hair/short02", "hair/short03", "hair/short04", "hair/bob01", "hair/bob02", "hair/ponytail01",
          "eyebrows/eyebrow001", "eyebrows/eyebrow002", "eyelashes/eyelashes01", "eyes/low-poly",
          "skins/middleage_caucasian_male", "skins/young_caucasian_female", "skins/middleage_caucasian_female", "skins/old_caucasian_female"]
def get(out, rel):
    dst = os.path.join(out, rel)
    if os.path.exists(dst) and os.path.getsize(dst) > 0: return open(dst, "rb").read()
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    try: d = urllib.request.urlopen(MH + rel, timeout=60).read()
    except Exception as e: print("FAIL", rel, e); return None
    open(dst, "wb").write(d); return d
if sys.argv[1] == "assets":
    out = sys.argv[2]
    for it in ASSETS:
        kind, name = it.split("/")
        ext = "mhmat" if kind == "skins" else "mhclo"
        main = get(out, f"{kind}/{name}/{name}.{ext}")
        if main is None: continue
        t = main.decode("latin1")
        for m in re.finditer(r"^(obj_file|material)\s+(\S+)", t, re.M):
            d = get(out, f"{kind}/{name}/{m.group(2)}")
            if m.group(2).endswith(".mhmat") and d:
                for tm in re.finditer(r"^\w*[Tt]exture\s+(\S+)", d.decode("latin1"), re.M): get(out, f"{kind}/{name}/{tm.group(1)}")
        if ext == "mhmat":
            for tm in re.finditer(r"^\w*[Tt]exture\s+(\S+)", t, re.M): get(out, f"{kind}/{name}/{tm.group(1)}")
elif sys.argv[1] == "bvh":
    out = sys.argv[2]; os.makedirs(out, exist_ok=True)
    for c in sys.argv[3:]:
        s, k = c.split("_")
        dst = os.path.join(out, c + ".bvh")
        if not os.path.exists(dst): open(dst, "wb").write(urllib.request.urlopen(f"{CMU}{int(s):03d}/{c}.bvh", timeout=60).read())
