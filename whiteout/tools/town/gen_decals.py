"""Procedural exterior grime decals -> textures/town_decals/<name>_a.png (RGBA albedo) + <name>_n.png (normal).
oil, salt, slush, tyre (tread strip, tiles along V), boots (footprint trail strip), soot, ice_sheen."""
import numpy as np, os
from PIL import Image
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../textures/town_decals")
rng = np.random.default_rng(7)

def vnoise(h, w, cells, seed):
    r = np.random.default_rng(seed).random((cells[0] + 3, cells[1] + 3))
    ys = np.linspace(0, cells[0], h, endpoint=False); xs = np.linspace(0, cells[1], w, endpoint=False)
    yi = ys.astype(int); xi = xs.astype(int); fy = ys - yi; fx = xs - xi
    fy = fy * fy * (3 - 2 * fy); fx = fx * fx * (3 - 2 * fx)
    a = r[yi][:, xi]; b = r[yi][:, xi + 1]; c = r[yi + 1][:, xi]; d = r[yi + 1][:, xi + 1]
    return (a * (1 - fx) + b * fx) * (1 - fy)[:, None] + (c * (1 - fx) + d * fx) * fy[:, None]

def fbm(h, w, base, oct, seed):
    t = np.zeros((h, w)); amp = 1.0; s = 0
    for o in range(oct):
        t += amp * vnoise(h, w, (base[0] * 2 ** o, base[1] * 2 ** o), seed + o); s += amp; amp *= 0.5
    return t / s

def radial(h, w):
    y, x = np.mgrid[0:h, 0:w]
    return np.sqrt(((x + 0.5) / w - 0.5) ** 2 * 4 + ((y + 0.5) / h - 0.5) ** 2 * 4)

def normal_from(hgt, k=4.0):
    gy, gx = np.gradient(hgt)
    n = np.dstack([-gx * k, gy * k, np.ones_like(hgt)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8), "RGB")

def save(name, rgb, alpha, hgt=None, k=4.0):
    a = np.clip(alpha, 0, 1)
    img = np.dstack([np.clip(rgb, 0, 1), a])
    Image.fromarray((img * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, name + "_a.png"))
    if hgt is not None:
        normal_from(hgt, k).save(os.path.join(OUT, name + "_n.png"))
    print("saved", name)

S = 512
# --- oil stain: dark irregular blob, darker core, drips of satellite spots
n = fbm(S, S, (4, 4), 6, 1); r = radial(S, S)
m = np.clip((0.78 - r - (n - 0.5) * 0.7) * 5.0, 0, 1)
spots = np.clip((fbm(S, S, (14, 14), 3, 2) - 0.72) * 8, 0, 1) * (r < 0.95)
a = np.maximum(m * (0.55 + 0.4 * fbm(S, S, (10, 10), 3, 3)), spots * 0.6)
col = np.dstack([0.05 + 0.03 * n, 0.04 + 0.025 * n, 0.03 + 0.02 * n])
save("oil", col, a, a * 0.3, 2.0)
# --- salt crust: white tide-mark rings on asphalt / boots
n = fbm(S, S, (3, 3), 6, 11)
ring = np.exp(-((np.abs((n * 9.0) % 1.0 - 0.5)) * 14) ** 2)
mask = np.clip((0.85 - radial(S, S) - (fbm(S, S, (5, 5), 4, 12) - 0.5) * 0.6) * 4, 0, 1)
a = np.clip(ring * 0.75 + fbm(S, S, (30, 30), 3, 13) * 0.35 - 0.1, 0, 1) * mask
col = np.dstack([np.full((S, S), 0.86), np.full((S, S), 0.86), np.full((S, S), 0.82)])
save("salt", col, a, a * 0.5, 3.0)
# --- slush: grey-brown wet churned snow patch
n = fbm(S, S, (5, 5), 6, 21)
mask = np.clip((0.8 - radial(S, S) - (n - 0.5) * 0.8) * 3, 0, 1)
d = fbm(S, S, (24, 24), 4, 22)
a = mask * (0.5 + 0.5 * d)
col = np.dstack([0.28 + 0.12 * d, 0.26 + 0.1 * d, 0.24 + 0.08 * d])
save("slush", col, a, d * mask, 6.0)
# --- tyre track: one 22 cm tread band, 256 x 2048 (tiles along V), slushy compressed snow, chevron lugs
W, H = 256, 2048
y, x = np.mgrid[0:H, 0:W]
u = (x + 0.5) / W; v = (y + 0.5) / H
band = np.clip((0.5 - np.abs(u - 0.5)) * 14, 0, 1)
chev = ((v * 64 + np.abs(u - 0.5) * 2.2) % 1.0)
lug = (chev < 0.45).astype(float)
groove = np.abs(u - 0.5) < 0.04
hgt = band * (0.4 + 0.6 * lug) * (1 - groove * 0.8)
nb = fbm(H, W, (64, 8), 4, 31)
a = band * np.clip(0.55 + 0.35 * nb + 0.15 * lug, 0, 1)
col = np.dstack([0.33 + 0.1 * nb - 0.06 * lug, 0.33 + 0.1 * nb - 0.06 * lug, 0.34 + 0.1 * nb - 0.05 * lug])
save("tyre", col, a, -hgt + nb * 0.3, 10.0)
# --- boot trail: 6 alternating prints along a 256 x 1024 strip (4.8 m when the decal is 0.8 x 4.8)
W, H = 256, 1024
hgt = np.zeros((H, W)); y, x = np.mgrid[0:H, 0:W]
for i in range(6):
    cx = 0.36 if i % 2 == 0 else 0.64; cy = (i + 0.5) / 6
    px = ((x + 0.5) / W - cx) / 0.16; py = ((y + 0.5) / H - cy) / 0.055
    sole = (px ** 2 + (py * 0.9) ** 2 < 1.0) & (py < 0.45)
    heel = (px ** 2 / 0.8 + ((py - 0.72) / 0.3) ** 2 < 1.0)
    lugs = ((np.floor(py * 6) + np.floor(px * 3)) % 2 == 0)
    shape = (sole | heel).astype(float)
    hgt -= shape * (0.7 + 0.3 * lugs)
from PIL import ImageFilter
hb = np.array(Image.fromarray(((hgt + 1) * 127).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3))) / 127.0 - 1
a = np.clip(-hb * 1.4, 0, 1) * 0.9
col = np.dstack([np.full((H, W), 0.62), np.full((H, W), 0.68), np.full((H, W), 0.78)])
save("boots", col, a, hb, 12.0)
# --- soot / grime streak (wall base, above vents): vertical gradient with drip streaks
W, H = 512, 512
n = fbm(H, W, (2, 20), 5, 41)
y = np.linspace(0, 1, H)[:, None]
a = np.clip((y * 1.2 - 0.25) * (0.6 + 0.6 * n), 0, 1) * np.clip((0.5 - np.abs(np.linspace(-0.5, 0.5, W)[None, :])) * 5, 0, 1)
col = np.dstack([0.1 + 0.05 * n, 0.09 + 0.05 * n, 0.08 + 0.05 * n])
save("grime", col, a * 0.85, None)

# ---------------------------------------------------------------- signage textures (tape, posters, awning stripes)
from PIL import ImageDraw, ImageFont
FB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../fonts/BeVietnamPro-Bold.ttf")
FR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../fonts/BeVietnamPro-Regular.ttf")
def font(sz, bold=True):
    return ImageFont.truetype(FB if bold else FR, sz)
# police tape: 2048 x 96, tiles along U
W, H = 2048, 96
im = Image.new("RGB", (W, H), (236, 196, 18)); d = ImageDraw.Draw(im)
d.rectangle([0, 0, W, 8], fill=(20, 20, 20)); d.rectangle([0, H - 8, W, H], fill=(20, 20, 20))
x = 20
while x < W:
    d.text((x, 16), "POLICE LINE  DO NOT CROSS", font=font(52), fill=(15, 15, 15)); x += 1020
n = (fbm(H, W, (2, 40), 3, 51) * 40 - 20)[..., None]
im = Image.fromarray(np.clip(np.array(im).astype(float) + n, 0, 255).astype(np.uint8)); im.save(os.path.join(OUT, "tape.png"))

def paper(w, h, seed, tint=(232, 228, 214)):
    n = fbm(h, w, (6, 6), 5, seed)
    a = np.dstack([np.full((h, w), c, float) for c in tint]) * (0.86 + 0.18 * n[..., None])
    # water stain + crease
    st = np.clip((fbm(h, w, (3, 3), 4, seed + 5) - 0.62) * 4, 0, 1)[..., None]
    a = a * (1 - st * 0.18) + np.array([150, 120, 70]) * st * 0.12
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))

def poster(name, lines, w=512, h=680, seed=1, tint=(232, 228, 214), photo=False):
    im = paper(w, h, seed, tint); d = ImageDraw.Draw(im)
    y = 30
    for txt, sz, col, bold in lines:
        if txt == "<photo>":
            d.rectangle([w * 0.22, y, w * 0.78, y + 230], fill=(88, 88, 86))
            pn = (fbm(230, int(w * 0.56), (4, 4), 4, seed + 9) * 70).astype(np.uint8)
            ph = Image.fromarray(np.dstack([pn + 60, pn + 58, pn + 55]))
            mask = Image.new("L", ph.size, 0); md = ImageDraw.Draw(mask)
            md.ellipse([ph.size[0] * 0.3, 30, ph.size[0] * 0.7, 120], fill=255); md.rectangle([ph.size[0] * 0.18, 125, ph.size[0] * 0.82, 230], fill=255)
            dark = Image.new("RGB", ph.size, (40, 38, 36)); ph.paste(dark, (0, 0), mask)
            im.paste(ph, (int(w * 0.22), y)); y += 250; continue
        f = font(sz, bold)
        for ln in txt.split("\n"):
            tw = d.textlength(ln, font=f)
            d.text(((w - tw) / 2, y), ln, font=f, fill=col); y += int(sz * 1.18)
        y += 8
    im.save(os.path.join(OUT, "poster_" + name + ".png"))

INK = (25, 25, 30); RED = (170, 25, 20); BLUE = (25, 50, 130)
poster("closed", [("CLOSED", 110, RED, True), ("NO POWER\nNO HEAT", 54, INK, True), ("Shelter is at the\nSCHOOL GYM.\nKnock at the west door.", 40, INK, False), ("- Dolores", 40, BLUE, False)], seed=3)
poster("missing", [("MISSING", 104, RED, True), ("<photo>", 0, 0, 0), ("MARGARET \"PEG\" OLSEN\nAge 71", 40, INK, True), ("Last seen Dec 18 walking\ntoward the mine road.\nGreen parka. Call 218-555-0143", 30, INK, False)], seed=5, photo=True)
poster("help", [("HELP\nWANTED", 96, INK, True), ("NIGHT COOK\n& DISHWASHER", 44, RED, True), ("ask for Bev", 36, BLUE, False)], seed=7, tint=(240, 232, 200))
poster("flu", [("FLU SHOTS", 84, BLUE, True), ("WALK-INS\nWELCOME", 60, INK, True), ("Medicare Part B\naccepted", 34, INK, False)], seed=9, tint=(225, 235, 240))
poster("icemelt", [("ICE MELT", 90, RED, True), ("$9.99", 120, INK, True), ("50 lb bag\nLIMIT 2 PER CUSTOMER", 36, INK, False)], seed=11, tint=(245, 225, 60))
poster("curfew", [("EMERGENCY\nORDER", 76, RED, True), ("CITY OF KETTLE FALLS", 34, INK, True), ("Curfew 6 PM - 7 AM.\nStay indoors. Do not travel\nto the mine road or the lake.\nReport anyone acting\nconfused or 'humming'.", 32, INK, False), ("- Sheriff R. Dahl", 34, BLUE, False)], seed=13)
poster("meridian", [("MERIDIAN", 92, (20, 60, 110), True), ("NOW HIRING", 62, INK, True), ("Data center techs\nCooling plant operators\n$31/hr + heat bonus", 38, INK, False)], seed=15, tint=(220, 232, 242))
poster("xmas", [("Merry\nChristmas", 96, RED, True), ("from all of us at\nKETTLE FALLS", 40, (20, 100, 40), True)], seed=17, tint=(250, 245, 235))
print("signage done")

# ---------------------------------------------------------------- light spill under a lit window (emission decal)
W = H = 256
y, x = np.mgrid[0:H, 0:W]
u = (x + 0.5) / W; v = (y + 0.5) / H          # v = 0 at the wall
spread = 0.16 + 0.22 * v
b = np.exp(-((u - 0.5) / spread) ** 2 * 2.2) * (1 - v) ** 1.6
b *= 1 - 0.45 * np.exp(-((u - 0.5) / (0.012 + 0.03 * v)) ** 2)        # mullion shadow
b *= 0.85 + 0.15 * fbm(H, W, (8, 8), 3, 61)
img = np.dstack([b, b, b, np.clip(b * 1.4, 0, 1)])
Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "spill_a.png"))
print("spill")
