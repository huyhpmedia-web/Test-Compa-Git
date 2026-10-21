#!/usr/bin/env python3
"""Procedural audio for WHITEOUT: KETTLE FALLS (numpy only, no samples).

Run:  python3 -I tools/gen_audio.py [outdir]     (default outdir: <project>/audio)

Everything here is PROCEDURAL (no third-party material). It covers the sounds that
could not be sourced as real CC0/CC-BY recordings:
  phone_ring, radio_static, radio_squelch, hum, generator, foreman_lamp
and exposes synth helpers (crystal_chimes, server_hum, periodic_noise) that the
(offline) ambience build re-uses as thin layers on top of real field recordings.
WAV: 16-bit mono 44.1 kHz.  Loops: OGG Vorbis (ffmpeg libvorbis -q:a 4), exactly periodic
so they loop seamlessly (partials have an integer number of cycles in the loop length).
"""
import os, sys, wave, subprocess
import numpy as np

SR = 44100


def _hp(x, fc, order=2):
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / SR)
    X *= 1 / np.sqrt(1 + (fc / np.maximum(f, 1e-9)) ** (2 * order))
    return np.fft.irfft(X, len(x))


def _lp(x, fc, order=2):
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / SR)
    X *= 1 / np.sqrt(1 + (f / fc) ** (2 * order))
    return np.fft.irfft(X, len(x))


def periodic_noise(dur, lo, hi, seed=0, slope=0.0):
    """Noise that is exactly periodic over `dur` seconds (random-phase spectrum)."""
    n = int(round(dur * SR)); rng = np.random.default_rng(seed)
    f = np.fft.rfftfreq(n, 1 / SR)
    mag = ((f >= lo) & (f <= hi)).astype(float) * (np.maximum(f, 1.0) ** slope)
    spec = mag * np.exp(1j * rng.uniform(0, 2 * np.pi, len(f)))
    x = np.fft.irfft(spec, n)
    return x / (np.abs(x).max() + 1e-12)


def crystal_chimes(dur, seed=0, density=0.35):
    """Sparse inharmonic glassy partials with long decays, placed at random."""
    rng = np.random.default_rng(seed); n = int(dur * SR); y = np.zeros(n)
    for _ in range(max(1, int(dur * density))):
        f0 = rng.uniform(900, 3200); o = rng.integers(0, n)
        L = int(rng.uniform(2.5, 6.0) * SR); t = np.arange(L) / SR
        s = sum(np.sin(2 * np.pi * f0 * r * t + rng.uniform(0, 6)) * a * np.exp(-t * d)
                for r, a, d in ((1, 1, 1.0), (2.76, .5, 1.6), (5.4, .25, 2.4), (8.93, .12, 3.5)))
        s *= np.minimum(t / 0.004, 1)
        m = min(L, n - o); y[o:o + m] += s[:m] * rng.uniform(0.15, 0.6)
    return y


def server_hum(dur, seed=0):
    """Periodic mains hum + fan whoosh + chiller rumble (exact loop)."""
    t = np.arange(int(round(dur * SR))) / SR
    y = sum(np.sin(2 * np.pi * f * t + p) * a for f, a, p in
            ((60, 1.0, 0), (120, .7, 1), (180, .35, 2), (240, .18, 3), (300, .08, 4)))
    y *= 1 + 0.03 * np.sin(2 * np.pi * (1 / dur) * np.round(0.35 * dur) * t)
    fans = periodic_noise(dur, 150, 2500, seed, slope=-0.5) * 0.7
    rum = periodic_noise(dur, 25, 140, seed + 1) * 1.2
    return y * 0.25 + fans * 0.25 + rum * 0.35


# --------------------------------------------------------------------- output
def wav_out(p, x, db=-1.0):
    x = x - x.mean()
    x = x * 10 ** (db / 20) / (np.abs(x).max() + 1e-12)
    with wave.open(p, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype('<i2').tobytes())


def ogg_out(p, x, db=-3.0):
    x = x - x.mean()
    x = x * 10 ** (db / 20) / (np.abs(x).max() + 1e-12)
    subprocess.run(['ffmpeg', '-y', '-v', 'error', '-f', 'f32le', '-ar', str(SR), '-ac', '1', '-i', '-',
                    '-c:a', 'libvorbis', '-q:a', '4', p], input=x.astype('<f4').tobytes(), check=True)


# --------------------------------------------------------------------- sounds
def phone_ring():
    t = np.arange(int(2.4 * SR)) / SR; y = np.zeros_like(t)
    for o in (0.0, 0.5):  # two bursts of the classic 440+480 Hz bell-ish ring, 20 Hz warble
        m = (t >= o) & (t < o + 0.38)
        tt = t[m] - o
        s = (np.sin(2 * np.pi * 440 * tt) + np.sin(2 * np.pi * 480 * tt)) * (0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 20 * tt)))
        s *= np.minimum(tt / 0.01, 1) * np.minimum((0.38 - tt) / 0.02, 1)
        y[m] += s
    y = _lp(_hp(y, 300), 3200)  # small handset/speaker band-limit
    return y


def radio_static():
    d = 3.0
    base = periodic_noise(d, 300, 3500, 3)
    t = np.arange(len(base)) / SR
    am = 0.75 + 0.25 * np.sin(2 * np.pi * (1 / d) * 2 * t) + 0.12 * np.sin(2 * np.pi * (1 / d) * 7 * t + 1)
    rng = np.random.default_rng(5); cr = np.zeros(len(base))
    for _ in range(26):  # crackle ticks (periodic placement irrelevant: they are short)
        o = rng.integers(0, len(base) - 400); k = np.exp(-np.arange(400) / 40.0) * rng.standard_normal(400)
        cr[o:o + 400] += k * rng.uniform(0.5, 1.5)
    y = base * am * 0.6 + _hp(cr, 1200) * 0.5
    return y


def radio_squelch():
    n = int(0.45 * SR); t = np.arange(n) / SR; rng = np.random.default_rng(11)
    click = np.exp(-t / 0.0015) * np.sin(2 * np.pi * 1800 * t)
    burst = rng.standard_normal(n) * np.exp(-t / 0.07)
    burst = _lp(_hp(burst, 600), 3500) * 0.9
    tail = rng.standard_normal(n) * np.exp(-t / 0.18) * (t > 0.06)
    tail = _lp(_hp(tail, 900), 2800) * 0.25
    return click * 0.8 + burst + tail


def hum():
    """Colony hum: 19 Hz fundamental + beating overtones (exact 20 s loop)."""
    d = 20.0; t = np.arange(int(d * SR)) / SR; y = np.zeros_like(t)
    # (freq Hz, amp, beat partner offset Hz) - all multiples of 1/20 Hz => periodic
    for f, a, b in ((19.0, 1.0, 0.5), (38.0, .8, 0.65), (57.0, .55, 0.8), (76.0, .45, 0.7), (114.0, .35, 1.1),
                    (133.0, .3, 0.9), (190.0, .22, 1.3), (228.0, .16, 1.15), (380.0, .08, 1.7)):
        y += a * (np.sin(2 * np.pi * f * t) + 0.8 * np.sin(2 * np.pi * (f + b) * t + 0.7))
    y *= 1 + 0.22 * np.sin(2 * np.pi * 0.15 * t) + 0.1 * np.sin(2 * np.pi * 0.35 * t + 2)
    # faint "voice-like" formant noise, periodic, swelling slowly
    v = _lp(_hp(periodic_noise(d, 250, 1100, 21), 250), 1100) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.1 * t))
    return y / np.abs(y).max() + 0.12 * v


def generator():
    """Diesel genset: firing pulses + harmonics + mechanical clatter (exact 6 s loop)."""
    d = 6.0; t = np.arange(int(d * SR)) / SR
    f = 24.0  # 144 pulses in 6 s
    pulse = np.maximum(0, np.sin(2 * np.pi * f * t)) ** 3
    y = sum(np.sin(2 * np.pi * f * k * t + k) * a for k, a in ((1, 1), (2, .8), (3, .6), (4, .35), (6, .2), (8, .1)))
    y = y * (0.55 + 0.45 * pulse) * (1 + 0.06 * np.sin(2 * np.pi * (1 / d) * 3 * t))
    alt = np.sin(2 * np.pi * 120 * t) * 0.25 + np.sin(2 * np.pi * 240 * t) * 0.1  # alternator
    clat = _hp(periodic_noise(d, 800, 6000, 31), 800) * (0.2 + 0.8 * pulse) * 0.35
    low = periodic_noise(d, 30, 200, 32) * 0.5
    return y / np.abs(y).max() + alt + clat + low


def foreman_lamp():
    """Failing mining-helmet lamp: 100 Hz buzz with irregular flicker (exact 2 s loop)."""
    d = 2.0; t = np.arange(int(d * SR)) / SR
    saw = sum(np.sin(2 * np.pi * 100 * k * t) / k for k in range(1, 14))
    fl = periodic_noise(d, 0.5, 14, 41)
    gate = np.clip(0.75 + 0.6 * _lp(fl, 14), 0.15, 1.0) ** 2
    hiss = _hp(periodic_noise(d, 2000, 9000, 42), 2000) * 0.15
    return (saw * 0.8 + hiss) * gate


def main(out):
    os.makedirs(out, exist_ok=True)
    wav_out(os.path.join(out, 'phone_ring.wav'), phone_ring(), -4)
    wav_out(os.path.join(out, 'radio_static.wav'), radio_static(), -6)
    wav_out(os.path.join(out, 'radio_squelch.wav'), radio_squelch(), -4)
    ogg_out(os.path.join(out, 'hum.ogg'), hum(), -4)
    ogg_out(os.path.join(out, 'generator.ogg'), generator(), -4)
    ogg_out(os.path.join(out, 'foreman_lamp.ogg'), foreman_lamp(), -8)


if __name__ == '__main__':
    here = os.path.dirname(os.path.abspath(__file__))
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, '..', 'audio'))
    print('gen_audio: procedural sounds written')
