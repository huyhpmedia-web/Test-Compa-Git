from PIL import Image, ImageDraw, ImageFont, ImageFilter
import random, os
O = "/tmp/claude-0/-home-user-Test-Compa-Git/b7d788c3-cd16-57ba-98fb-70cb388fdafd/scratchpad/e_tex/"
F = "/usr/share/fonts/truetype/dejavu/"
def font(n, s): return ImageFont.truetype(F + n, s)
def grunge(im, amt=22, seed=1):
    random.seed(seed)
    px = im.load(); w, h = im.size
    n = Image.effect_noise((w, h), 40).convert("L").filter(ImageFilter.GaussianBlur(1.2))
    npx = n.load()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y][:3]
            d = int((npx[x, y] - 128) * amt / 60)
            px[x, y] = (max(0, min(255, r + d)), max(0, min(255, g + d)), max(0, min(255, b + d)))
    return im
def ctext(d, xy, t, f, fill):
    w = d.textlength(t, font=f); d.text((xy[0] - w / 2, xy[1]), t, font=f, fill=fill)

# manila tag (control house key) 256x420 (aspect w:h = 0.6)
def tag(name, lines, base=(214, 196, 150), ink=(30, 24, 20), seed=2, hand=False):
    im = Image.new("RGB", (512, 800), base)
    im = grunge(im, 26, seed)
    d = ImageDraw.Draw(im)
    d.ellipse((226, 40, 286, 100), fill=(60, 50, 40))
    d.ellipse((238, 52, 274, 88), fill=(120, 105, 80))
    y = 190
    for t, sz, bold in lines:
        f = font("DejaVuSans-Bold.ttf" if bold else ("../crosextra/Caladea-Italic.ttf" if hand else "DejaVuSans.ttf"), sz)
        ctext(d, (256, y), t, f, ink)
        y += int(sz * 1.5)
    d.rectangle((10, 10, 502, 790), outline=tuple(max(0, c - 70) for c in base), width=6)
    im = im.filter(ImageFilter.GaussianBlur(0.6))
    im.save(O + name + ".png")
tag("tag_control", [("KF SUBSTATION", 52, True), ("— — —", 40, False), ("CONTROL", 64, True), ("HOUSE", 64, True), ("", 20, False), ("No. 2", 44, False)])
tag("tag_school", [("KFCS", 80, True), ("— — —", 40, False), ("CUSTODIAL", 52, True), ("", 20, False), ("Main Hall", 40, False), ("Boiler Rm", 40, False)], base=(196, 60, 50), ink=(250, 240, 230), seed=4)
tag("tag_church", [("side", 110, False), ("door", 110, False)], base=(224, 214, 186), ink=(40, 30, 90), seed=7, hand=True)

# fuse tube label 512x256 (wrap)
im = Image.new("RGB", (512, 256), (170, 40, 30)); im = grunge(im, 20, 11)
d = ImageDraw.Draw(im)
d.rectangle((0, 70, 512, 190), fill=(226, 222, 206))
ctext(d, (256, 76), "60 AMP  250 VOLTS", font("DejaVuSans-Bold.ttf", 38), (20, 20, 20))
ctext(d, (256, 122), "CLASS H  CARTRIDGE FUSE", font("DejaVuSans.ttf", 26), (20, 20, 20))
ctext(d, (256, 156), "KF-2 SUBSTATION  UL", font("DejaVuSans.ttf", 22), (40, 40, 40))
im = grunge(im, 14, 12).filter(ImageFilter.GaussianBlur(0.5)); im.save(O + "fuse_label.png")

# badge card 1024x640 (CR80: 85.6 x 54 mm)
def card(name, band, title, sub, who, id_, seed):
    W, H = 1024, 646
    im = Image.new("RGB", (W, H), (236, 238, 240)); im = grunge(im, 10, seed)
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, W, 150), fill=band)
    d.text((40, 30), title, font=font("DejaVuSans-Bold.ttf", 54), fill=(255, 255, 255))
    d.text((40, 100), sub, font=font("DejaVuSans.ttf", 28), fill=(235, 235, 235))
    d.rectangle((50, 190, 330, 520), fill=(150, 160, 170), outline=(60, 60, 60), width=4)
    d.ellipse((130, 230, 250, 350), fill=(110, 118, 126)); d.rectangle((105, 365, 275, 520), fill=(110, 118, 126))
    for i, t in enumerate(who):
        d.text((370, 200 + i * 62), t, font=font("DejaVuSans-Bold.ttf" if i == 0 else "DejaVuSans.ttf", 44 if i == 0 else 34), fill=(25, 25, 30))
    for i in range(34):
        d.rectangle((370 + i * 18, 520, 370 + i * 18 + (6 if i % 3 else 10), 590), fill=(20, 20, 20))
    d.text((50, 560), id_, font=font("DejaVuSansMono.ttf", 30), fill=(40, 40, 40))
    # scuffs
    for _ in range(40):
        x = random.randint(0, W); y = random.randint(0, H)
        d.line((x, y, x + random.randint(-40, 40), y + random.randint(-10, 10)), fill=(190, 190, 192), width=1)
    im.save(O + name + ".png")
random.seed(3)
card("card_badge", (24, 92, 150), "CORVANE SYSTEMS", "MERIDIAN SITE  -  CONTRACTOR", ["I. KESTREL", "Dept: THERMAL OPS", "Access: L2  B-WING"], "ID 0447-2291-C", 5)
card("card_pipeline", (214, 120, 20), "PIPELINE OVERRIDE", "HEAT RECOVERY  -  SERVICE TUNNEL", ["IMOGEN V.", "Clearance: OVERRIDE", "Valid: SERVICE ONLY"], "OVR 0001-HR", 6)
print("ok")

# tinted PBR bases from the repo textures
T = "/home/user/Test-Compa-Git/whiteout/textures/"
import numpy as np
def tint(src, rgb, out, gain=1.0, size=512, gamma=1.0):
    im = Image.open(T + src).convert("RGB").resize((size, size))
    a = np.asarray(im).astype(np.float32) / 255.0
    lum = (a[..., 0] * .3 + a[..., 1] * .59 + a[..., 2] * .11) ** gamma
    lum = lum / max(lum.mean(), 1e-3) * 0.55 * gain
    o = np.clip(lum[..., None] * np.array(rgb, dtype=np.float32), 0, 1)
    Image.fromarray((o * 255).astype(np.uint8)).save(O + out)
def plain(src, out, size=512):
    Image.open(T + src).convert("RGB").resize((size, size)).save(O + out)
tint("metal_albedo.png", (0.95, 0.72, 0.28), "brass_a.png", 1.0)
tint("metal_albedo.png", (0.82, 0.83, 0.86), "chrome_a.png", 1.1)
tint("metal_painted_albedo.png", (0.95, 0.66, 0.08), "fiberglass_a.png", 1.0)
tint("fabric_albedo.png", (0.62, 0.52, 0.36), "hemp_a.png", 1.2)
tint("fabric_albedo.png", (0.35, 0.37, 0.28), "webbing_a.png", 1.0)
plain("metal_rust_albedo.png", "rust_a.png"); plain("metal_rust_rough.png", "rust_r.png"); plain("metal_rust_normal.png", "rust_n.png")
plain("metal_rough.png", "metal_r.png"); plain("metal_normal.png", "metal_n.png")
plain("wood_albedo.png", "wood_a.png"); plain("wood_rough.png", "wood_r.png"); plain("wood_normal.png", "wood_n.png")
print("tex ok")

# gunpowder tin label (wraps a cylinder: 1024x256)
im = Image.new("RGB", (1024, 256), (222, 205, 160)); im = grunge(im, 22, 21)
d = ImageDraw.Draw(im)
d.rectangle((0, 0, 1024, 18), fill=(150, 30, 25)); d.rectangle((0, 238, 1024, 256), fill=(150, 30, 25))
ctext(d, (512, 30), "BLACK POWDER", font("DejaVuSerif-Bold.ttf", 70), (30, 22, 18))
ctext(d, (512, 118), "FFFg  -  SPORTING GRADE", font("DejaVuSans-Bold.ttf", 34), (30, 22, 18))
ctext(d, (512, 168), "NORTHLINE MINING SUPPLY CO.  -  1 LB NET", font("DejaVuSans.ttf", 26), (40, 30, 24))
ctext(d, (512, 204), "DANGER  EXTREMELY FLAMMABLE", font("DejaVuSans-Bold.ttf", 22), (150, 30, 25))
im = grunge(im, 16, 22).filter(ImageFilter.GaussianBlur(0.5)); im.save(O + "powder_label.png")
