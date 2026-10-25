#!/usr/bin/env python3
"""Procedural flesh / gore sound effects (numpy only, our own work, CC0).
Run:  python3 -I tools/gen_gore_audio.py      -> audio/gore_*.wav   (16-bit mono 44.1 kHz)

  gore_hit_[a-c]    bullet / blade into flesh: dull thud + wet slap
  gore_splat_[a-c]  a gib or a spray hitting floor / wall
  gore_pop          head burst: heavy thud, bone crack, wet burst, drip tail
  gore_tear_[a-b]   limb torn off: wet rip + crunch
"""
import os, wave
import numpy as np

SR = 44100
OUT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio"))
rng = np.random.default_rng(1313)


def _lp(x, fc, order=2):
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(X / np.sqrt(1 + (f / fc) ** (2 * order)), len(x))


def _hp(x, fc, order=2):
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(X / np.sqrt(1 + (fc / np.maximum(f, 1e-9)) ** (2 * order)), len(x))


def env(n, a, d, shape=3.0):
    t = np.arange(n) / SR
    e = np.minimum(t / max(a, 1e-4), 1.0) * np.exp(-t / d * shape / 3.0)
    return e


def thud(n, f0, f1, d):
    t = np.arange(n) / SR
    ph = 2 * np.pi * np.cumsum(f1 + (f0 - f1) * np.exp(-t / 0.03)) / SR
    return np.sin(ph) * np.exp(-t / d)


def noise(n):
    return rng.standard_normal(n)


def wet(n, rate=38.0, depth=0.8):
    """crackly wet texture: band noise amplitude-modulated by random bubble pops"""
    t = np.arange(n) / SR
    bubbles = np.maximum(0, np.sin(2 * np.pi * rate * t + rng.uniform(0, 6) + 3 * np.sin(2 * np.pi * 7 * t))) ** 3
    return _hp(_lp(noise(n), 3500), 300) * (1 - depth + depth * bubbles)


def norm(x, peak=0.8):
    return x / (np.max(np.abs(x)) + 1e-9) * peak


def save(name, x):
    x = np.clip(x, -1, 1)
    with wave.open(f"{OUT}/{name}.wav", "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    print("wrote", name, len(x) / SR)


def hit(i):
    n = int(0.32 * SR)
    x = 0.9 * thud(n, 140 - 10 * i, 55, 0.07)
    x += 0.5 * _lp(noise(n), 1800 + 300 * i) * env(n, 0.001, 0.05)
    x += 0.45 * wet(n, 30 + 8 * i) * env(n, 0.004, 0.11)
    return norm(x, 0.85)


def splat(i):
    n = int(0.42 * SR)
    x = 0.7 * thud(n, 110, 45, 0.05)
    x += 0.8 * wet(n, 24 + 6 * i, 0.9) * env(n, 0.003, 0.14)
    x += 0.35 * _hp(noise(n), 2500) * env(n, 0.001, 0.02)
    return norm(x, 0.8)


def pop():
    n = int(1.1 * SR)
    t = np.arange(n) / SR
    x = 1.0 * thud(n, 95, 38, 0.16)
    crack = _hp(noise(n), 1800) * env(n, 0.0005, 0.012)
    x += 0.7 * crack
    x += 0.9 * wet(n, 20, 0.9) * env(n, 0.006, 0.28)
    x += 0.4 * _lp(noise(n), 700) * env(n, 0.004, 0.2)
    # drip tail
    for k in range(7):
        t0 = 0.35 + k * 0.09 + rng.uniform(0, 0.04)
        i0 = int(t0 * SR)
        m = min(int(0.05 * SR), n - i0)
        if m > 0:
            x[i0:i0 + m] += 0.18 * thud(m, 900 + 100 * k, 300, 0.01) * (1 - k / 9)
    return norm(x, 0.9)


def tear(i):
    n = int(0.7 * SR)
    t = np.arange(n) / SR
    x = 0.8 * wet(n, 16 + 4 * i, 1.0) * env(n, 0.02, 0.22) * (0.6 + 0.4 * np.sin(2 * np.pi * 5 * t))
    for k in range(5):
        i0 = int((0.05 + k * 0.07 + rng.uniform(0, 0.03)) * SR)
        m = int(0.03 * SR)
        x[i0:i0 + m] += 0.9 * _hp(noise(m), 1500) * np.exp(-np.arange(m) / SR / 0.006)
    x += 0.6 * thud(n, 80, 40, 0.1)
    return norm(x, 0.85)


if __name__ == "__main__":
    for i, s in enumerate("abc"):
        save(f"gore_hit_{s}", hit(i))
        save(f"gore_splat_{s}", splat(i))
    save("gore_pop", pop())
    for i, s in enumerate("ab"):
        save(f"gore_tear_{s}", tear(i))
