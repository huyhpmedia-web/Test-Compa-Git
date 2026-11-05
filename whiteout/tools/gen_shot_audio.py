#!/usr/bin/env python3
"""PROCEDURAL shooting-feel audio layers for WHITEOUT (numpy only, no third-party samples):
crack_<weapon> (transient), mech_slide / mech_pump, casing_* / shell_* (+ _snow muffled), impact_*, ricochet, hitmark / killmark,
tail_outdoor (flat slap-back echo) / tail_indoor (room reverb). 16-bit mono 44.1 kHz WAV.
Run: python3 -I tools/gen_shot_audio.py [outdir]"""
import os, sys, wave
import numpy as np
SR = 44100
rng = np.random.default_rng(7)

def hp(x, fc):
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / SR); X *= 1 / np.sqrt(1 + (fc / np.maximum(f, 1e-9)) ** 4); return np.fft.irfft(X, len(x))
def lp(x, fc):
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / SR); X *= 1 / np.sqrt(1 + (f / fc) ** 4); return np.fft.irfft(X, len(x))
def bp(x, lo, hi): return lp(hp(x, lo), hi)
def t(n): return np.arange(int(n * SR)) / SR
def noise(n): return rng.standard_normal(int(n * SR))
def env(n, a, d): tt = t(n); return np.minimum(tt / max(a, 1e-4), 1.0) * np.exp(-tt / d)
def ping(n, f, d, amp=1.0): tt = t(n); return amp * np.sin(2 * np.pi * f * tt) * np.exp(-tt / d)

def save(name, x, outdir, gain=0.9):
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    with wave.open(os.path.join(outdir, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((x * 32767).astype("<i2").tobytes())

def crack(dur, body_f, bright, snap):
    n = noise(dur)
    x = hp(n, 1500) * env(dur, 0.0003, 0.006 * bright) * 1.2
    x += lp(n, body_f) * env(dur, 0.0005, 0.03) * 0.8
    x += ping(dur, 60 + body_f * 0.1, 0.05, 0.6) * snap
    return x

def reverb(src, rt, wet_lp, pre=0.0, taps=40):
    n = int((rt + 0.3) * SR); out = np.zeros(n + len(src))
    ir = noise(rt + 0.3) * np.exp(-t(rt + 0.3) / (rt / 4.5)); ir = lp(ir, wet_lp)
    ir[: int(pre * SR)] = 0
    full = np.fft.irfft(np.fft.rfft(src, len(out)) * np.fft.rfft(ir, len(out)), len(out))
    return full

def build(outdir):
    os.makedirs(outdir, exist_ok=True)
    save("crack_handgun", crack(0.25, 900, 1.0, 0.6), outdir)
    save("crack_magnum", crack(0.4, 500, 1.5, 1.0), outdir)
    save("crack_shotgun", crack(0.4, 380, 1.8, 1.0), outdir)
    save("crack_launcher", lp(noise(0.35), 700) * env(0.35, 0.002, 0.08) + ping(0.35, 90, 0.12), outdir)
    # mechanical: slide clack and pump rack
    s = hp(noise(0.12), 2500) * env(0.12, 0.0004, 0.006) + ping(0.12, 3200, 0.01, 0.4)
    s2 = np.zeros(int(0.22 * SR)); s2[: len(s)] += s; s3 = (hp(noise(0.1), 1800) * env(0.1, 0.0005, 0.012)); s2[int(0.09 * SR): int(0.09 * SR) + len(s3)] += s3 * 0.8
    save("mech_slide", s2, outdir, 0.7)
    p1 = bp(noise(0.14), 300, 3000) * env(0.14, 0.001, 0.02) + ping(0.14, 900, 0.015, 0.4)
    p = np.zeros(int(0.5 * SR)); p[: len(p1)] += p1
    p2 = bp(noise(0.14), 400, 3500) * env(0.14, 0.001, 0.02) + ping(0.14, 1200, 0.012, 0.4)
    p[int(0.24 * SR): int(0.24 * SR) + len(p2)] += p2 * 1.1
    save("mech_pump", p, outdir, 0.8)
    # brass casings on hard floor (3 variants) and muffled in snow
    for i, f in enumerate([4200, 5100, 3600]):
        x = ping(0.45, f, 0.03, 1.0) + ping(0.45, f * 1.52, 0.02, 0.5) + ping(0.45, f * 2.3, 0.012, 0.3)
        b = np.zeros(int(0.5 * SR)); b[: len(x)] += x
        for k, (dly, g) in enumerate([(0.11, 0.5), (0.19, 0.3), (0.24, 0.2)]):
            o = int(dly * SR); y = ping(0.2, f * (1 + 0.04 * k), 0.025, g); b[o: o + len(y)] += y
        save("casing_" + "abc"[i], b, outdir, 0.5)
        sn = lp(noise(0.12), 900) * env(0.12, 0.002, 0.02) + ping(0.12, 520 + 80 * i, 0.012, 0.5)
        save("casing_snow_" + "abc"[i], sn, outdir, 0.35)
    for i, f in enumerate([1400, 1700]):   # shotgun hull: dull plastic thud + clack
        x = ping(0.3, f, 0.02, 1.0) + lp(noise(0.3), 2500) * env(0.3, 0.001, 0.012)
        save("shell_" + "ab"[i], x, outdir, 0.5)
        save("shell_snow_" + "ab"[i], lp(noise(0.15), 700) * env(0.15, 0.002, 0.02), outdir, 0.3)
    # bullet impacts
    save("impact_snow", lp(noise(0.25), 900) * env(0.25, 0.002, 0.05) + ping(0.25, 140, 0.04, 0.5), outdir, 0.6)
    for i in range(2):
        save("impact_concrete_" + "ab"[i], hp(noise(0.3), 700) * env(0.3, 0.0005, 0.02) + ping(0.3, 380 + 90 * i, 0.03, 0.5) + lp(noise(0.3), 400) * env(0.3, 0.001, 0.05), outdir, 0.8)
    save("impact_wood", bp(noise(0.25), 200, 2200) * env(0.25, 0.001, 0.03) + ping(0.25, 240, 0.03, 0.8) + ping(0.25, 520, 0.02, 0.4), outdir, 0.8)
    save("impact_ice", hp(noise(0.3), 2000) * env(0.3, 0.0005, 0.03) + ping(0.3, 2400, 0.05, 0.5) + ping(0.3, 3300, 0.04, 0.4), outdir, 0.7)
    # ricochet: descending zing
    tt = t(0.5); f = 3800 * np.exp(-tt * 5.0) + 900
    ph = 2 * np.pi * np.cumsum(f) / SR
    save("ricochet", np.sin(ph) * np.exp(-tt / 0.12) * 0.6 + hp(noise(0.5), 3000) * env(0.5, 0.0005, 0.01), outdir, 0.6)
    # confirmation
    save("hitmark", ping(0.1, 1900, 0.025, 1.0) + ping(0.1, 3800, 0.012, 0.3), outdir, 0.55)
    km = ping(0.35, 160, 0.09, 1.0) + ping(0.35, 90, 0.12, 0.8) + lp(noise(0.35), 900) * env(0.35, 0.001, 0.03) * 0.5
    km[: int(0.1 * SR)] += ping(0.1, 1500, 0.03, 0.4)
    save("killmark", km, outdir, 0.8)
    # tails: the shot's own energy smeared. outdoor: dull flat slap + faint distant return; indoor: room.
    imp = hp(noise(0.05), 300) * env(0.05, 0.0005, 0.01)
    out = reverb(imp, 0.9, 5500, 0.012)
    out += 0.0
    save("tail_indoor", out * env(len(out) / SR, 0.002, 0.5), outdir, 0.55)
    od = np.zeros(int(1.3 * SR))
    for dly, g, fc in [(0.12, 0.7, 3500), (0.31, 0.35, 2200), (0.62, 0.18, 1400)]:
        y = lp(imp, fc) * g; o = int(dly * SR); od[o: o + len(y)] += y[: len(od) - o]
    od += lp(noise(1.3), 900) * np.exp(-t(1.3) / 0.35) * 0.03
    save("tail_outdoor", od, outdir, 0.4)

if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio"))
