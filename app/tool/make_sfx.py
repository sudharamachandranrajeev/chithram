"""Writes the keyboard sound effects in app/assets/sfx (synthesised; no samples).

Run: python3 app/tool/make_sfx.py
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parent.parent / 'assets' / 'sfx'


def env(i, n, attack=0.004, decay=None):
    t = i / RATE
    a = min(1.0, t / attack) if attack else 1.0
    if decay is None:
        return a * (1 - i / n)
    return a * math.exp(-t / decay)


def tone(ms, f0, f1=None, amp=0.3, decay=None, partials=((1, 1.0),), noise=0.0, seed=1):
    rnd = random.Random(seed)
    n = int(RATE * ms / 1000)
    f1 = f0 if f1 is None else f1
    out, phase, lp = [], 0.0, 0.0
    for i in range(n):
        f = f0 * (f1 / f0) ** (i / n)
        phase += 2 * math.pi * f / RATE
        s = sum(w * math.sin(phase * k) for k, w in partials)
        lp += 0.25 * (rnd.uniform(-1, 1) - lp)
        out.append(amp * env(i, n, decay=decay) * (s + noise * lp))
    return out


def swoosh(ms, f0, f1, amp):
    """Band-limited noise whose brightness glides from f0 to f1, under a soft sine."""
    rnd = random.Random(7)
    n = int(RATE * ms / 1000)
    out, lp, bp, phase = [], 0.0, 0.0, 0.0
    for i in range(n):
        x = i / n
        f = f0 * (f1 / f0) ** x
        c = min(0.95, 2 * math.pi * f / RATE)
        lp += c * (rnd.uniform(-1, 1) - lp)
        bp += c * (lp - bp)
        phase += 2 * math.pi * f / RATE
        shape = math.sin(math.pi * x) ** 1.5
        out.append(amp * shape * (1.6 * (lp - bp) + 0.35 * math.sin(phase)))
    return out


def mix(*parts):
    n = max(len(p) for _, p in parts)
    out = [0.0] * n
    for at, p in parts:
        for i, s in enumerate(p):
            if at + i < n:
                out[at + i] += s
    return out


def write(name, samples):
    OUT.mkdir(parents=True, exist_ok=True)
    tail = int(RATE * 0.004)
    samples = samples + [0.0] * tail
    with wave.open(str(OUT / name), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, s)) * 32767)) for s in samples))


bell = ((1, 1.0), (2, 0.35), (3, 0.12))
write('move.wav', tone(22, 2600, 2300, amp=0.16, decay=0.006, noise=0.3))
write('key.wav', tone(45, 1500, 900, amp=0.34, decay=0.012, partials=((1, 1.0), (2, 0.2)), noise=0.5))
write('delete.wav', tone(55, 760, 430, amp=0.34, decay=0.016, noise=0.4))
write('open.wav', mix((0, swoosh(230, 600, 3200, 0.22)), (int(RATE * 0.12), tone(120, 1320, amp=0.12, decay=0.05, partials=bell))))
write('close.wav', swoosh(170, 2800, 500, 0.2))
write('submit.wav', mix((0, tone(140, 988, amp=0.2, decay=0.06, partials=bell)),
                        (int(RATE * 0.07), tone(260, 1480, amp=0.2, decay=0.09, partials=bell))))
