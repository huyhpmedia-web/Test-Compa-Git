#!/usr/bin/env python3
"""Sketchfab helper (CC-BY / CC0 only). Token: env SKETCHFAB_TOKEN or the file named by env SKETCHFAB_TOKEN_FILE.
Never commit the token.

  sf.py search "query words" [--n 24] [--max-faces 150000] [--sheet out.jpg]   -> table (+ thumbnail contact sheet)
  sf.py get <uid> <out.glb>                                                    -> downloads glb, records credit
  sf.py info <uid>

Credits are appended to assets/CREDITS_SKETCHFAB.json (title, author, url, license) and shown in the game credits.
Allowed licences: CC Attribution (CC BY 4.0) and CC0. NonCommercial, NoDerivs and ShareAlike are rejected.
"""
import json, os, sys, urllib.request, urllib.parse, io

API = "https://api.sketchfab.com/v3"
HERE = os.path.dirname(os.path.abspath(__file__))
CREDITS = os.path.join(HERE, "..", "..", "assets", "CREDITS_SKETCHFAB.json")
OK_LIC = {"CC Attribution", "CC0 Public Domain"}


def token():
    t = os.environ.get("SKETCHFAB_TOKEN", "")
    if not t and os.environ.get("SKETCHFAB_TOKEN_FILE"):
        t = open(os.environ["SKETCHFAB_TOKEN_FILE"]).read().strip()
    if not t:
        sys.exit("set SKETCHFAB_TOKEN or SKETCHFAB_TOKEN_FILE")
    return t


def call(url):
    req = urllib.request.Request(url, headers={"Authorization": "Token " + token()})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def lic(m):
    l = m.get("license") or {}
    return l.get("label", "") if isinstance(l, dict) else str(l)


def search(q, n=24, max_faces=150000, sheet=None):
    out, url = [], API + "/search?" + urllib.parse.urlencode({"type": "models", "q": q, "downloadable": "true", "count": 24, "sort_by": "-likeCount"})
    while url and len(out) < n:
        d = call(url)
        for m in d["results"]:
            if lic(m) in OK_LIC and (m.get("faceCount") or 0) <= max_faces:
                out.append(m)
        url = d.get("next")
        if len(out) >= n or not d["results"]:
            break
    out = out[:n]
    for i, m in enumerate(out):
        print("%2d %s %-45s faces=%-7s likes=%-5s %s | %s" % (i, m["uid"], m["name"][:45], m.get("faceCount"), m.get("likeCount"), lic(m), m["user"]["username"]))
    if sheet and out:
        from PIL import Image, ImageDraw
        W = 6; S = 256
        img = Image.new("RGB", (W * S, ((len(out) + W - 1) // W) * (S + 20)), "white")
        dr = ImageDraw.Draw(img)
        for i, m in enumerate(out):
            th = sorted(m["thumbnails"]["images"], key=lambda t: abs(t["width"] - 256))[0]["url"]
            try:
                with urllib.request.urlopen(th, timeout=30) as r:
                    t = Image.open(io.BytesIO(r.read())).convert("RGB")
                t.thumbnail((S, S))
                x, y = (i % W) * S, (i // W) * (S + 20)
                img.paste(t, (x, y + 20))
                dr.text((x + 3, y + 3), "%d %s" % (i, m["name"][:30]), fill="black")
            except Exception as e:
                print("thumb fail", i, e)
        img.save(sheet, quality=82)
        print("sheet:", sheet)
    return out


def get(uid, out):
    m = call(API + "/models/" + uid)
    if lic(m) not in OK_LIC:
        sys.exit("licence not allowed: " + lic(m))
    d = call(API + "/models/" + uid + "/download")
    url = d["glb"]["url"]
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with urllib.request.urlopen(url, timeout=600) as r, open(out, "wb") as f:
        f.write(r.read())
    cr = json.load(open(CREDITS)) if os.path.exists(CREDITS) else []
    if not any(c["uid"] == uid for c in cr):
        cr.append({"uid": uid, "title": m["name"], "author": m["user"].get("displayName") or m["user"]["username"],
                   "url": m.get("viewerUrl", "https://sketchfab.com/3d-models/" + uid), "license": lic(m)})
        json.dump(cr, open(CREDITS, "w"), indent=1, ensure_ascii=False)
    print("saved", out, os.path.getsize(out), "|", m["name"], "by", m["user"]["username"], "|", lic(m))


if __name__ == "__main__":
    a = sys.argv[1:]
    if not a:
        sys.exit(__doc__)
    if a[0] == "search":
        kw = {"n": 24, "max_faces": 150000, "sheet": None}
        q = []
        i = 1
        while i < len(a):
            if a[i] == "--n": kw["n"] = int(a[i + 1]); i += 2
            elif a[i] == "--max-faces": kw["max_faces"] = int(a[i + 1]); i += 2
            elif a[i] == "--sheet": kw["sheet"] = a[i + 1]; i += 2
            else: q.append(a[i]); i += 1
        search(" ".join(q), **kw)
    elif a[0] == "get":
        get(a[1], a[2])
    elif a[0] == "info":
        print(json.dumps(call(API + "/models/" + a[1]), indent=1)[:2000])
