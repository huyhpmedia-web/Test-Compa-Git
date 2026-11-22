#!/usr/bin/env python3
"""R8-C: PROCEDURAL positional-ambience one-shots (numpy only, no third-party samples).

Run:  python3 -I tools/gen_amb_oneshots.py [outdir]   (default <project>/audio)
  amb_creak_a/b/c     wood / timber creak (stick-slip impulse train through wood body resonances)
  amb_radiator_a/b/c  radiator / steam-pipe knocks (inharmonic metal partials, 2-4 knocks + ticks)
  amb_pipe_groan_a/b  long low metal stress groan (pipe contracting in the cold)
  amb_server_fan      seamless 4 s loop: fan noise + blade-pass tone + 120 Hz mains (OGG)
WAV: 16-bit mono 44.1 kHz.
"""
import os, sys, wave, subprocess
import numpy as np

SR = 44100
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio")


def lp(x, fc, order=2):
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / SR)
    X *= 1 / np.sqrt(1 + (f / fc) ** (2 * order))
    return np.fft.irfft(X, len(x))


def hp(x, fc, order=2):
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / SR)
    X *= 1 / np.sqrt(1 + (fc / np.maximum(f, 1e-9)) ** (2 * order))
    return np.fft.irfft(X, len(x))


def norm(x, peak=0.85):
    return x * (peak / (np.abs(x).max() + 1e-12))


def fade(x, a=0.004, b=0.08):
    n = len(x); ia = int(a * SR); ib = int(b * SR)
    x = x.copy()
    x[:ia] *= np.linspace(0, 1, ia)
    x[n - ib:] *= np.linspace(1, 0, ib)
    return x


def save_wav(name, x):
    path = os.path.join(OUT, name + ".wav")
    d = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(d.tobytes())
    print("wrote", path)


def save_ogg(name, x):
    tmp = os.path.join(OUT, name + "_tmp.wav")
    d = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(tmp, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(d.tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "4",
                    os.path.join(OUT, name + ".ogg")], check=True)
    os.remove(tmp)
    print("wrote", os.path.join(OUT, name + ".ogg"))


def resonator(freqs, decays, gains, dur):
    t = np.arange(int(dur * SR)) / SR
    y = np.zeros_like(t)
    for f, d, g in zip(freqs, decays, gains):
        y += g * np.sin(2 * np.pi * f * t) * np.exp(-t / d)
    return y


def creak(seed, dur):
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    t = np.arange(n) / SR
    # stick-slip rate wanders 25..140 Hz along a slow curve
    knots = rng.uniform(25, 140, 6)
    rate = np.interp(t, np.linspace(0, dur, 6), knots)
    rate *= 1 + 0.08 * np.sin(2 * np.pi * rng.uniform(2, 6) * t)
    phase = np.cumsum(rate / SR)
    imp = np.zeros(n)
    idx = np.nonzero(np.diff(np.floor(phase)) > 0)[0]
    imp[idx] = rng.uniform(0.5, 1.0, len(idx))
    env = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 0.7 * np.interp(t, np.linspace(0, dur, 5), rng.uniform(0.3, 1.0, 5))
    imp *= env
    body = resonator([310, 640, 1180, 1900, 2750], [0.012, 0.009, 0.006, 0.004, 0.003], [1.0, 0.7, 0.5, 0.3, 0.15], 0.05)
    y = np.convolve(imp, body)[:n]
    y += 0.04 * hp(rng.standard_normal(n), 2500) * env
    return fade(norm(hp(y, 120)), 0.01, 0.15)


def knocks(seed):
    rng = np.random.default_rng(seed)
    dur = 2.6
    n = int(dur * SR)
    y = np.zeros(n)
    t0 = 0.05
    for k in range(rng.integers(2, 5)):
        base = rng.uniform(150, 230)
        parts = base * np.array([1.0, 2.71, 5.12, 8.3, 12.1])
        hit = resonator(parts, [0.35, 0.18, 0.09, 0.05, 0.03], [1.0, 0.6, 0.45, 0.3, 0.2], 1.0)
        tr = rng.standard_normal(int(0.006 * SR)) * np.linspace(1, 0, int(0.006 * SR))
        hit[:len(tr)] += 1.5 * tr
        g = rng.uniform(0.5, 1.0)
        i = int(t0 * SR)
        m = min(len(hit), n - i)
        y[i:i + m] += g * hit[:m]
        t0 += rng.uniform(0.18, 0.55)
        if t0 > dur - 0.9:
            break
    # expansion ticks afterwards
    for k in range(rng.integers(3, 8)):
        i = int(rng.uniform(t0, dur - 0.1) * SR)
        tick = resonator([rng.uniform(1800, 3200)], [0.01], [1.0], 0.04)
        m = min(len(tick), n - i)
        y[i:i + m] += 0.25 * tick[:m]
    y = lp(y, 5000)
    return fade(norm(y), 0.001, 0.3)


def pipe_groan(seed, dur):
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    t = np.arange(n) / SR
    f0 = np.interp(t, [0, dur * 0.4, dur], [rng.uniform(55, 70), rng.uniform(80, 95), rng.uniform(48, 60)])
    ph = 2 * np.pi * np.cumsum(f0 / SR)
    y = np.zeros(n)
    for h, g in [(1, 1.0), (2.3, 0.5), (3.9, 0.35), (6.2, 0.2)]:
        y += g * np.sin(ph * h + rng.uniform(0, 6))
    rough = 1 + 0.6 * lp(rng.standard_normal(n), 30)
    env = np.sin(np.pi * t / dur) ** 1.5
    y = y * rough * env
    y += 0.15 * lp(hp(rng.standard_normal(n), 300), 1500) * env
    return fade(norm(lp(y, 1800)), 0.05, 0.4)


def server_fan():
    dur = 4.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    rng = np.random.default_rng(7)
    f = np.fft.rfftfreq(n, 1 / SR)
    mag = np.where((f > 40) & (f < 9000), 1.0 / np.maximum(f, 40) ** 0.45, 0.0)
    noise = np.fft.irfft(mag * np.exp(1j * rng.uniform(0, 2 * np.pi, len(f))), n)
    noise = norm(lp(noise, 3500))
    tone = np.zeros(n)
    for fr, g in [(120, 0.25), (240, 0.12), (220, 0.18), (440, 0.08), (660, 0.04), (1320, 0.02)]:
        tone += g * np.sin(2 * np.pi * fr * t)    # integer cycles in 4 s -> seamless loop
    y = 0.75 * noise + tone * (1 + 0.1 * np.sin(2 * np.pi * 0.5 * t))
    return norm(y, 0.6)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for i, s in enumerate("abc"):
        save_wav("amb_creak_" + s, creak(11 + i, [1.4, 2.1, 1.0][i]))
        save_wav("amb_radiator_" + s, knocks(21 + i))
    for i, s in enumerate("ab"):
        save_wav("amb_pipe_groan_" + s, pipe_groan(31 + i, [3.0, 4.2][i]))
    save_ogg("amb_server_fan", server_fan())
