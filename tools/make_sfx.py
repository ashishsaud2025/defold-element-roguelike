#!/usr/bin/env python3
"""Generate placeholder sounds for every id in src/core/sfx.lua (MASTER_PROMPT 2.3).

Standard library only. Mono 16-bit 22050 Hz WAV.

    python tools/make_sfx.py                 # write missing files only
    python tools/make_sfx.py --force         # overwrite everything
    python tools/make_sfx.py --only sig_steam cast_bolt

Files are deterministic (RNG seeded from the id), idempotent, and never overwrite a
file that already exists unless --force is passed (the human may have dropped a real
sound in by name). Music goes to assets/music/, everything else to assets/sfx/.
The table in assets/sfx/SFX_MAP.md is regenerated from this script's metadata.
"""
import argparse
import math
import os
import random
import struct
import wave
import zlib
from pathlib import Path

SR = 22050
ROOT = Path(__file__).resolve().parent.parent
SFX_DIR = ROOT / "assets" / "sfx"
MUSIC_DIR = ROOT / "assets" / "music"
MAP_PATH = SFX_DIR / "SFX_MAP.md"

# Note frequencies used by the pitch language.
NOTE = {
    "C3": 130.81, "D3": 146.83, "E3": 164.81, "F3": 174.61, "G3": 196.00, "A3": 220.00, "B3": 246.94,
    "C4": 261.63, "D4": 293.66, "E4": 329.63, "F4": 349.23, "G4": 392.00, "A4": 440.00, "B4": 493.88,
    "C5": 523.25, "D5": 587.33, "E5": 659.25, "F5": 698.46, "G5": 783.99, "A5": 880.00,
}
ROOT_OF = {"fire": NOTE["D4"], "water": NOTE["F4"], "wind": NOTE["A4"], "earth": NOTE["C4"]}
COMPOUND_ELEMENTS = {
    "inferno": ("fire", "fire"), "tide": ("water", "water"), "gale": ("wind", "wind"),
    "quake": ("earth", "earth"), "steam": ("fire", "water"), "ember": ("fire", "wind"),
    "magma": ("fire", "earth"), "mist": ("water", "wind"), "mud": ("water", "earth"),
    "dust": ("wind", "earth"),
}

SPECS = {}


def spec(sid, desc, where, build, bus="sfx", loop=False, peak=0.82):
    SPECS[sid] = {
        "desc": desc, "where": where, "build": build, "bus": bus,
        "loop": loop, "peak": peak,
    }


# ---------------------------------------------------------------- primitives

def n_of(dur):
    return max(1, int(SR * dur))


def silence(dur):
    return [0.0] * n_of(dur)


def mix_into(buf, start, src, gain=1.0):
    i0 = int(start * SR)
    for i, v in enumerate(src):
        j = i0 + i
        if 0 <= j < len(buf):
            buf[j] += v * gain
    return buf


def tone(freq, dur, kind="sine", amp=1.0, sweep=None, phase=0.0):
    """sweep = (f0, f1): frequency glides exponentially over the note."""
    n = n_of(dur)
    out = [0.0] * n
    ph = phase
    for i in range(n):
        t = i / n
        f = freq if sweep is None else sweep[0] * ((sweep[1] / sweep[0]) ** t)
        ph = (ph + f / SR) % 1.0
        if kind == "sine":
            v = math.sin(2 * math.pi * ph)
        elif kind == "triangle":
            v = 4 * abs(ph - 0.5) - 1
        elif kind == "saw":
            v = 2 * ph - 1
        elif kind == "square":
            v = 1.0 if ph < 0.5 else -1.0
        else:
            v = math.sin(2 * math.pi * ph)
        out[i] = v * amp
    return out


def noise(dur, rng, amp=1.0):
    return [(rng.random() * 2 - 1) * amp for _ in range(n_of(dur))]


def lowpass(buf, cutoff):
    """One-pole low pass; cutoff may be a number or a callable t->Hz."""
    y = 0.0
    out = []
    n = len(buf)
    for i, x in enumerate(buf):
        c = cutoff(i / n) if callable(cutoff) else cutoff
        a = 1 - math.exp(-2 * math.pi * c / SR)
        y += a * (x - y)
        out.append(y)
    return out


def highpass(buf, cutoff):
    lp = lowpass(buf, cutoff)
    return [x - l for x, l in zip(buf, lp)]


def bandpass(buf, lo, hi):
    return lowpass(highpass(buf, lo), hi)


def env_exp(buf, tau):
    n = len(buf)
    k = max(1e-4, tau) * SR
    return [v * math.exp(-i / k) for i, v in enumerate(buf)]


def env_adsr(buf, attack=0.005, release=0.02):
    n = len(buf)
    a = max(1, int(attack * SR))
    r = max(1, int(release * SR))
    out = list(buf)
    for i in range(min(a, n)):
        out[i] *= i / a
    for i in range(min(r, n)):
        out[-1 - i] *= i / r
    return out


def fade(buf, ms=5.0):
    n = max(1, int(SR * ms / 1000.0))
    n = min(n, len(buf) // 2)
    for i in range(n):
        g = i / n
        buf[i] *= g
        buf[-1 - i] *= g
    return buf


def finish(buf, peak=0.82):
    out = [math.tanh(v * 1.1) for v in buf]
    m = max((abs(v) for v in out), default=0.0)
    if m > 0:
        g = peak / m
        out = [v * g for v in out]
    fade(out)
    return out


def chord(root, intervals, dur, amp=0.35, kind="sine", detune=0.0):
    buf = silence(dur)
    for k, mult in enumerate(intervals):
        f = root * mult
        if detune:
            f *= 1 + detune * (k - 1)
        mix_into(buf, 0, tone(f, dur, kind=kind, amp=amp))
        mix_into(buf, 0, tone(f * 1.003, dur, kind=kind, amp=amp * 0.5))
    return env_adsr(buf, 0.02, 0.08)


def bell(freq, dur, amp=0.5):
    buf = silence(dur)
    for mult, g in ((1.0, 1.0), (2.01, 0.5), (3.03, 0.26), (4.7, 0.12)):
        mix_into(buf, 0, env_exp(tone(freq * mult, dur, amp=amp * g), dur * 0.45))
    return buf


def click(dur=0.04, freq=1800, amp=0.7):
    n = n_of(dur)
    return env_exp([amp if (i % max(1, int(SR / freq))) == 0 else 0.0 for i in range(n)], dur * 0.15)


# ---------------------------------------------------------------- shape gestures

def b_cast_projectile(rng):
    d = 0.15
    nz = noise(d, rng)
    nz = lowpass(nz, lambda t: 500 + 3200 * t)
    nz = highpass(nz, 300)
    out = env_exp(nz, 0.06)
    mix_into(out, 0, tone(900, 0.06, sweep=(900, 2200), amp=0.25))
    return out


def b_cast_puddle(rng):
    out = tone(90, 0.5, sweep=(120, 45), amp=0.5)
    shimmer = noise(0.5, rng)
    shimmer = bandpass(shimmer, 900, 4000)
    shimmer = [v * (0.15 + 0.6 * (i / len(shimmer))) for i, v in enumerate(shimmer)]
    mix_into(out, 0.04, env_exp(shimmer, 0.22), 0.5)
    return out


def b_cast_orbit(rng):
    out = silence(0.4)
    for k, f in enumerate((NOTE["A4"], NOTE["C5"], NOTE["E5"])):
        mix_into(out, k * 0.045, bell(f, 0.3, amp=0.35))
    return out


def b_cast_cone(rng):
    out = noise(0.35, rng)
    out = lowpass(out, lambda t: 2200 - 1400 * abs(2 * t - 1))
    out = highpass(out, 400)
    return env_adsr(out, 0.04, 0.08)


def b_cast_burst(rng):
    out = silence(0.7)
    riser = noise(0.2, rng)
    riser = highpass(riser, 500)
    riser = [v * (i / len(riser)) ** 2 for i, v in enumerate(riser)]
    mix_into(out, 0, riser, 0.6)
    boom = tone(95, 0.5, sweep=(130, 40), amp=0.7)
    mix_into(out, 0.2, env_exp(boom, 0.18))
    burst = lowpass(noise(0.4, rng), 900)
    mix_into(out, 0.2, env_exp(burst, 0.1), 0.5)
    return out


# ---------------------------------------------------------------- element layers

def b_fire_cast(rng):
    out = silence(0.45)
    for _ in range(24):
        t = rng.random() * 0.4
        mix_into(out, t, click(0.02, 2400, 0.25 * rng.random()))
    hiss = highpass(noise(0.45, rng), 1800)
    mix_into(out, 0.02, env_adsr(hiss, 0.03, 0.2), 0.35)
    return out


def b_water_cast(rng):
    out = silence(0.45)
    for k in range(2):
        f0 = 300 + 80 * k
        bloop = tone(f0, 0.2, sweep=(f0, f0 * 2.4), amp=0.6)
        mix_into(out, 0.03 + 0.16 * k, env_exp(bloop, 0.09))
        mix_into(out, 0.03 + 0.16 * k, env_exp(tone(f0 * 2, 0.1, amp=0.15), 0.05))
    return out


def b_wind_cast(rng):
    out = noise(0.5, rng)
    out = bandpass(out, 500, 2600)
    out = [v * (0.55 + 0.45 * math.sin(2 * math.pi * 5 * i / SR)) for i, v in enumerate(out)]
    return env_adsr(out, 0.06, 0.15)


def b_earth_cast(rng):
    out = silence(0.55)
    rumble = tone(58, 0.55, sweep=(62, 48), amp=0.7)
    mix_into(out, 0, env_adsr(rumble, 0.02, 0.2))
    dull = lowpass(noise(0.55, rng), 220)
    mix_into(out, 0.02, env_exp(dull, 0.25), 0.5)
    return out


def b_fire_hit(rng):
    out = silence(0.12)
    mix_into(out, 0, env_exp(tone(220, 0.12, sweep=(260, 90), amp=0.6), 0.05))
    sizzle = highpass(noise(0.12, rng), 2400)
    mix_into(out, 0, env_exp(sizzle, 0.04), 0.55)
    return out


def b_water_hit(rng):
    out = silence(0.13)
    mix_into(out, 0, env_exp(tone(420, 0.13, sweep=(420, 160), amp=0.55), 0.05))
    splash = bandpass(noise(0.13, rng), 800, 4200)
    mix_into(out, 0, env_exp(splash, 0.03), 0.4)
    return out


def b_wind_hit(rng):
    out = noise(0.12, rng)
    out = bandpass(out, 900, 5200)
    return env_exp(out, 0.035)


def b_earth_hit(rng):
    out = silence(0.14)
    mix_into(out, 0, env_exp(tone(75, 0.14, sweep=(95, 45), amp=0.8), 0.055))
    mix_into(out, 0, env_exp(lowpass(noise(0.14, rng), 260), 0.04), 0.4)
    return out


# ---------------------------------------------------------------- compounds

def b_signature(compound):
    ea, eb = COMPOUND_ELEMENTS[compound]

    def build(rng):
        ra, rb = ROOT_OF[ea], ROOT_OF[eb]
        dur = 0.55
        out = silence(dur)
        if ea == eb:
            tones = [(ra, 1.0), (ra * 2.0, 0.55), (ra * 1.5, 0.35)]
        else:
            tones = [(ra, 0.8), (rb, 0.8), (ra * 1.5, 0.35), (rb * 1.5, 0.3)]
        for f, g in tones:
            mix_into(out, 0.02, env_adsr(tone(f, dur, amp=0.4 * g), 0.03, 0.18))
            mix_into(out, 0.02, env_adsr(tone(f * 0.997, dur, amp=0.2 * g), 0.03, 0.18))
        mix_into(out, 0.0, env_exp(bell(ra * 2, 0.3, amp=0.18), 0.12))
        return out

    return build


# ---------------------------------------------------------------- status cues

def b_st_burn(rng):
    out = highpass(noise(0.35, rng), 1400)
    out = [v * (0.3 + 0.7 * (i / len(out))) for i, v in enumerate(out)]
    return env_adsr(out, 0.02, 0.16)


def b_st_slow(rng):
    out = tone(520, 0.35, sweep=(520, 170), amp=0.55)
    out = lowpass(out, lambda t: 3000 - 2400 * t)
    return env_adsr(out, 0.01, 0.12)


def b_st_stun(rng):
    out = silence(0.32)
    mix_into(out, 0, env_exp(bell(1760, 0.32, amp=0.4), 0.12))
    mix_into(out, 0.02, env_exp(tone(85, 0.3, sweep=(110, 55), amp=0.7), 0.12))
    return out


def b_st_root(rng):
    out = tone(70, 0.4, sweep=(80, 55), kind="triangle", amp=0.55)
    out = lowpass(out, 500)
    return env_adsr(out, 0.03, 0.15)


def b_st_blind(rng):
    out = noise(0.25, rng)
    out = [v if (i // 90) % 2 == 0 else v * 0.15 for i, v in enumerate(out)]
    return env_adsr(out, 0.005, 0.06)


def b_st_confuse(rng):
    out = silence(0.4)
    mix_into(out, 0, env_adsr(tone(360, 0.4, sweep=(360, 520), amp=0.35), 0.02, 0.1))
    mix_into(out, 0, env_adsr(tone(385, 0.4, sweep=(385, 470), amp=0.3), 0.02, 0.1))
    return out


def b_st_push(rng):
    out = noise(0.16, rng)
    out = bandpass(out, 500, 3200)
    return env_exp(tone(300, 0.16, sweep=(300, 900), amp=0.2) + out, 0.06)


def b_st_pull(rng):
    out = noise(0.16, rng)
    out = bandpass(out, 400, 2400)
    return env_exp(tone(800, 0.16, sweep=(800, 220), amp=0.2) + out, 0.06)


def b_st_hide(rng):
    out = lowpass(noise(0.35, rng), 1200)
    return env_adsr(out, 0.08, 0.12)


# ---------------------------------------------------------------- quirks

def b_qk_split(rng):
    out = silence(0.2)
    mix_into(out, 0, click(0.03, 1800, 0.7))
    mix_into(out, 0.09, click(0.03, 2400, 0.7))
    return out


def b_qk_repeat(rng):
    out = silence(0.3)
    mix_into(out, 0, env_exp(tone(520, 0.12, amp=0.5), 0.05))
    mix_into(out, 0.14, env_exp(tone(520, 0.14, amp=0.22), 0.06))
    return out


def b_qk_trail(rng):
    out = bandpass(noise(0.3, rng), 1200, 5000)
    return env_adsr(out, 0.02, 0.12)


def b_qk_big(rng):
    out = silence(0.3)
    mix_into(out, 0, env_exp(tone(120, 0.3, sweep=(140, 55), amp=0.8), 0.12))
    mix_into(out, 0, env_exp(lowpass(noise(0.2, rng), 300), 0.06))
    return out


def b_qk_cost(rng):
    out = silence(0.4)
    for t in (0.0, 0.17):
        mix_into(out, t, env_exp(tone(58, 0.16, sweep=(70, 42), amp=0.8), 0.07))
    return out


# ---------------------------------------------------------------- loops

def b_loop_pool(rng):
    dur = 1.6
    out = silence(dur)
    hum = tone(70, dur, amp=0.25)
    out = [v * (0.7 + 0.3 * math.sin(2 * math.pi * 2 * i / SR)) for i, v in enumerate(hum)]
    for k in range(10):
        t = k * dur / 10.0
        f = 260 + rng.random() * 320
        mix_into(out, t, env_exp(tone(f, 0.18, sweep=(f, f * 1.8), amp=0.18), 0.06))
    return out


def b_loop_orbit(rng):
    dur = 1.5
    out = silence(dur)
    for k, f in enumerate((NOTE["A4"], NOTE["C5"], NOTE["E5"])):
        ph = k * 0.11
        for i in range(len(out)):
            t = i / SR
            g = 0.5 + 0.5 * math.sin(2 * math.pi * (0.7 + 0.1 * k) * t + ph)
            out[i] += 0.09 * math.sin(2 * math.pi * f * t) * g
    return out


def b_pl_lowhp(rng):
    dur = 1.25
    out = silence(dur)
    for t, a in ((0.0, 0.9), (0.22, 0.55)):
        mix_into(out, t, env_exp(tone(55, 0.2, sweep=(65, 40), amp=a), 0.09))
    return out


def b_ui_cauldron_loop(rng):
    dur = 1.8
    out = silence(dur)
    for k in range(14):
        t = k * dur / 14.0
        f = 180 + rng.random() * 260
        mix_into(out, t, env_exp(tone(f, 0.16, sweep=(f, f * 1.5), amp=0.12), 0.05))
    hum = tone(90, dur, amp=0.12)
    mix_into(out, 0, hum)
    return out


# ---------------------------------------------------------------- player

def b_pl_hurt(rng):
    out = silence(0.3)
    mix_into(out, 0, env_exp(tone(180, 0.3, sweep=(220, 90), kind="saw", amp=0.45), 0.09))
    mix_into(out, 0, env_exp(bandpass(noise(0.16, rng), 300, 1800), 0.05), 0.4)
    return out


def b_pl_dash(rng):
    out = noise(0.22, rng)
    out = bandpass(out, 600, 4200)
    out = [v * (1 - i / len(out)) for i, v in enumerate(out)]
    return env_adsr(out, 0.005, 0.08)


def b_pl_die(rng):
    out = silence(0.9)
    mix_into(out, 0, env_adsr(tone(220, 0.9, sweep=(220, 55), kind="triangle", amp=0.55), 0.01, 0.3))
    mix_into(out, 0.1, env_exp(lowpass(noise(0.7, rng), 700), 0.25), 0.3)
    return out


def b_pl_heal(rng):
    out = silence(0.6)
    for k, f in enumerate((NOTE["C5"], NOTE["E5"], NOTE["G5"])):
        mix_into(out, k * 0.07, env_exp(bell(f, 0.3, amp=0.3), 0.15))
    return out


# ---------------------------------------------------------------- enemies

def b_en_spawn(rng):
    out = silence(0.4)
    mix_into(out, 0, env_adsr(tone(140, 0.4, sweep=(90, 220), amp=0.4), 0.05, 0.12))
    mix_into(out, 0, env_exp(bandpass(noise(0.3, rng), 500, 2600), 0.1), 0.3)
    return out


def b_en_hit(rng):
    out = silence(0.15)
    mix_into(out, 0, env_exp(tone(120, 0.15, sweep=(160, 70), amp=0.6), 0.05))
    mix_into(out, 0, env_exp(lowpass(noise(0.1, rng), 900), 0.03), 0.35)
    return out


def b_en_die(rng):
    out = silence(0.45)
    mix_into(out, 0, env_adsr(tone(300, 0.45, sweep=(300, 60), kind="square", amp=0.35), 0.01, 0.15))
    mix_into(out, 0.05, env_exp(bandpass(noise(0.35, rng), 400, 2400), 0.12), 0.4)
    return out


def b_en_charge_windup(rng):
    out = tone(90, 0.45, sweep=(70, 240), kind="saw", amp=0.35)
    return env_adsr(lowpass(out, 900), 0.02, 0.06)


def b_en_charge(rng):
    out = noise(0.32, rng)
    out = bandpass(out, 300, 2600)
    out = [v * (i / len(out)) for i, v in enumerate(out)]
    return env_adsr(out, 0.01, 0.1)


def b_en_slinger_shot(rng):
    out = silence(0.2)
    mix_into(out, 0, env_exp(tone(1200, 0.18, sweep=(1300, 400), amp=0.5), 0.06))
    mix_into(out, 0, env_exp(highpass(noise(0.1, rng), 2000), 0.03), 0.25)
    return out


def b_en_brute_stomp(rng):
    out = silence(0.4)
    mix_into(out, 0, env_exp(tone(60, 0.4, sweep=(80, 35), amp=0.9), 0.14))
    mix_into(out, 0, env_exp(lowpass(noise(0.25, rng), 220), 0.08), 0.45)
    return out


def b_en_splitter_pop(rng):
    out = silence(0.28)
    mix_into(out, 0, env_exp(tone(320, 0.28, sweep=(340, 110), amp=0.5), 0.07))
    mix_into(out, 0.04, env_exp(bandpass(noise(0.2, rng), 600, 3600), 0.05), 0.4)
    return out


def b_en_wall_stun(rng):
    out = silence(0.35)
    mix_into(out, 0, env_exp(bell(880, 0.3, amp=0.35), 0.1))
    mix_into(out, 0.01, env_exp(tone(70, 0.3, amp=0.6), 0.1))
    return out


def b_boss_roar(rng):
    out = silence(1.1)
    growl = tone(70, 1.1, sweep=(60, 45), kind="saw", amp=0.5)
    growl = lowpass(growl, 400)
    growl = [v * (0.6 + 0.4 * math.sin(2 * math.pi * 8 * i / SR)) for i, v in enumerate(growl)]
    mix_into(out, 0, env_adsr(growl, 0.05, 0.3))
    mix_into(out, 0, env_exp(lowpass(noise(0.7, rng), 900), 0.25), 0.3)
    return out


def b_boss_ring(rng):
    out = silence(0.55)
    for k, f in enumerate((NOTE["A4"], NOTE["C5"], NOTE["E5"], NOTE["A5"])):
        mix_into(out, k * 0.03, bell(f, 0.4, amp=0.25))
    return out


def b_boss_charge(rng):
    out = noise(0.65, rng)
    out = bandpass(out, 200, 2200)
    out = [v * (i / len(out)) for i, v in enumerate(out)]
    return env_adsr(out, 0.02, 0.2)


def b_boss_summon(rng):
    out = tone(60, 0.9, sweep=(50, 120), kind="saw", amp=0.35)
    out = lowpass(out, 600)
    swirl = bandpass(noise(0.9, rng), 400, 2400)
    return env_adsr([a + 0.3 * b for a, b in zip(out, swirl)], 0.08, 0.25)


def b_boss_die(rng):
    out = silence(1.6)
    mix_into(out, 0, env_adsr(tone(180, 1.5, sweep=(180, 35), kind="saw", amp=0.4), 0.02, 0.5))
    mix_into(out, 0.2, env_exp(lowpass(noise(1.2, rng), 800), 0.4), 0.45)
    mix_into(out, 0.7, env_exp(tone(55, 0.8, sweep=(70, 30), amp=0.6), 0.3))
    return out


# ---------------------------------------------------------------- UI / flow

def b_ui_hover(rng):
    return env_exp(tone(1600, 0.06, amp=0.35), 0.02)


def b_ui_click(rng):
    out = silence(0.1)
    mix_into(out, 0, click(0.02, 1400, 0.7))
    mix_into(out, 0, env_exp(tone(800, 0.08, amp=0.25), 0.03))
    return out


def b_ui_card(rng):
    out = bandpass(noise(0.2, rng), 1400, 5000)
    return env_adsr(out, 0.01, 0.07)


def b_ui_pick(rng):
    out = silence(0.25)
    mix_into(out, 0, env_exp(bell(1046, 0.25, amp=0.4), 0.09))
    mix_into(out, 0.04, env_exp(bell(1568, 0.2, amp=0.25), 0.08))
    return out


def b_ui_craft(rng):
    out = silence(0.55)
    for k, f in enumerate((NOTE["C5"], NOTE["E5"], NOTE["G5"], NOTE["C5"] * 2)):
        mix_into(out, k * 0.06, env_exp(bell(f, 0.35, amp=0.3), 0.15))
    return out


def b_ui_craft_bad(rng):
    out = silence(0.28)
    mix_into(out, 0, env_adsr(tone(140, 0.28, kind="square", amp=0.25), 0.005, 0.05))
    mix_into(out, 0, env_adsr(tone(131, 0.28, kind="square", amp=0.2), 0.005, 0.05))
    return out


def b_room_clear(rng):
    out = silence(1.0)
    for k, f in enumerate((NOTE["C5"], NOTE["E5"], NOTE["G5"])):
        mix_into(out, k * 0.12, env_exp(bell(f, 0.6, amp=0.3), 0.25))
    return out


def b_state_win(rng):
    out = silence(3.6)
    for k, f in enumerate((NOTE["C4"], NOTE["E4"], NOTE["G4"], NOTE["C5"], NOTE["E5"])):
        mix_into(out, k * 0.18, env_adsr(tone(f, 3.0, amp=0.22), 0.05, 0.6))
    for k, f in enumerate((NOTE["C5"], NOTE["E5"], NOTE["G5"], NOTE["C5"] * 2)):
        mix_into(out, 0.4 + k * 0.22, env_exp(bell(f, 1.4, amp=0.22), 0.4))
    return out


def b_state_dead(rng):
    out = silence(3.6)
    for k, f in enumerate((NOTE["A3"], NOTE["F3"], NOTE["D3"], NOTE["A3"] / 2)):
        mix_into(out, k * 0.35, env_adsr(tone(f, 2.4, kind="triangle", amp=0.24), 0.06, 0.7))
    return out


def b_state_title(rng):
    out = silence(0.8)
    mix_into(out, 0, env_exp(bell(NOTE["A4"], 0.8, amp=0.35), 0.3))
    mix_into(out, 0.12, env_exp(bell(NOTE["E5"], 0.6, amp=0.2), 0.25))
    return out


# ---------------------------------------------------------------- later-phase ids

def b_rx_steam(rng):
    out = highpass(noise(0.45, rng), 1600)
    return env_adsr(out, 0.02, 0.2)


def b_rx_shatter(rng):
    out = silence(0.45)
    for _ in range(12):
        t = rng.random() * 0.3
        mix_into(out, t, env_exp(bell(1200 + rng.random() * 2600, 0.15, amp=0.18), 0.04))
    return out


def b_rx_flare(rng):
    out = bandpass(noise(0.45, rng), 600, 4200)
    out = [v * (i / len(out)) for i, v in enumerate(out)]
    return env_adsr(out, 0.01, 0.15)


def b_rx_bog(rng):
    out = silence(0.55)
    for k in range(4):
        f = 180 + 40 * k
        mix_into(out, k * 0.1, env_exp(tone(f, 0.16, sweep=(f, f * 0.7), amp=0.3), 0.06))
    return out


def b_rx_whirl(rng):
    out = silence(0.55)
    for k, f in enumerate((NOTE["D4"], NOTE["F4"], NOTE["A4"], NOTE["D5"])):
        mix_into(out, k * 0.05, env_exp(tone(f, 0.4, amp=0.22), 0.16))
    return out


def b_combo_up(rng):
    out = silence(0.55)
    for k, f in enumerate((NOTE["C5"], NOTE["E5"], NOTE["G5"], NOTE["C5"] * 2)):
        mix_into(out, k * 0.08, env_exp(tone(f, 0.25, amp=0.3), 0.1))
    return out


def b_fusion(rng):
    out = silence(0.75)
    for f in (NOTE["D4"], NOTE["F4"], NOTE["A4"], NOTE["D5"]):
        mix_into(out, 0, env_adsr(tone(f, 0.7, amp=0.2), 0.03, 0.25))
    return out


def b_hit_weak(rng):
    return env_exp(lowpass(noise(0.12, rng), 700), 0.03)


def b_hit_resist(rng):
    out = silence(0.2)
    mix_into(out, 0, env_exp(bell(520, 0.2, amp=0.3), 0.06))
    mix_into(out, 0, env_exp(noise(0.08, rng), 0.02), 0.2)
    return out


def b_crit_streak(rng):
    out = silence(0.3)
    mix_into(out, 0, env_exp(bell(1760, 0.3, amp=0.3), 0.1))
    mix_into(out, 0.03, env_exp(bell(2637, 0.2, amp=0.2), 0.07))
    return out


def b_relic_get(rng):
    out = silence(0.7)
    for k, f in enumerate((NOTE["G4"], NOTE["B4"], NOTE["D5"], NOTE["G5"])):
        mix_into(out, k * 0.07, env_exp(bell(f, 0.5, amp=0.25), 0.2))
    return out


def b_shrine(rng):
    out = silence(0.9)
    for f in (NOTE["C4"], NOTE["G4"], NOTE["C5"]):
        mix_into(out, 0, env_adsr(tone(f, 0.9, amp=0.18), 0.08, 0.3))
    return out


def b_shop_buy(rng):
    out = silence(0.35)
    mix_into(out, 0, env_exp(bell(1568, 0.25, amp=0.3), 0.08))
    mix_into(out, 0.05, env_exp(bell(2093, 0.2, amp=0.25), 0.07))
    return out


# ---------------------------------------------------------------- music

BPM = 100
BEATS_BAR = 4
BARS = 8
BAR_SECONDS = BEATS_BAR * 60.0 / BPM
ROOM_LEN = BARS * BAR_SECONDS  # 19.2 s


def b_mus_room_pad(rng):
    dur = ROOM_LEN
    out = silence(dur)
    # D minor pentatonic, slow swell; same length for every room stem.
    for k, f in enumerate((NOTE["D3"], NOTE["F3"], NOTE["A3"], NOTE["C4"], NOTE["D4"])):
        seg = tone(f, dur, amp=0.10)
        seg = [v * (0.55 + 0.45 * math.sin(2 * math.pi * 0.06 * i / SR + k)) for i, v in enumerate(seg)]
        out = [a + b for a, b in zip(out, seg)]
    return env_adsr(out, 0.5, 0.8)


def b_mus_room_rhythm(rng):
    dur = ROOM_LEN
    out = silence(dur)
    beat = 60.0 / BPM
    nbeats = int(dur / beat)
    for b in range(nbeats):
        t = b * beat
        if b % 4 in (0, 2):
            mix_into(out, t, env_exp(tone(55, 0.18, sweep=(70, 40), amp=0.55), 0.06))
        hat = highpass(noise(0.05, rng), 6000)
        mix_into(out, t + beat / 2, env_exp(hat, 0.015), 0.18)
    return out


def b_mus_room_lead(rng):
    dur = ROOM_LEN
    out = silence(dur)
    notes = [NOTE["D4"], NOTE["F4"], NOTE["A4"], NOTE["C5"], NOTE["A4"], NOTE["F4"]]
    step = BAR_SECONDS / 2
    for k in range(int(dur / step)):
        if k % 3 == 2:
            continue
        f = notes[k % len(notes)]
        mix_into(out, k * step, env_exp(tone(f, 0.45, amp=0.14), 0.18))
    return env_adsr(out, 0.02, 0.2)


def b_mus_boss(rng):
    dur = ROOM_LEN
    out = silence(dur)
    beat = 60.0 / BPM
    # Driving low ostinato in D minor plus faster hats.
    for b in range(int(dur / beat)):
        f = NOTE["D3"] if b % 4 in (0, 1) else NOTE["A3"] / 2
        mix_into(out, b * beat, env_exp(tone(f, 0.22, kind="saw", amp=0.22), 0.08))
        mix_into(out, b * beat, env_exp(tone(55, 0.16, amp=0.5), 0.05))
        hat = highpass(noise(0.04, rng), 6500)
        mix_into(out, b * beat + beat / 2, env_exp(hat, 0.012), 0.16)
    for f in (NOTE["D4"], NOTE["F4"], NOTE["A4"]):
        mix_into(out, 0, env_adsr(tone(f, dur, amp=0.06), 0.4, 0.6))
    return out


def b_mus_title(rng):
    dur = ROOM_LEN
    out = silence(dur)
    for k, f in enumerate((NOTE["A3"], NOTE["C4"], NOTE["E4"])):
        mix_into(out, 0, env_adsr(tone(f, dur, amp=0.08), 0.5, 0.6))
    for k in range(8):
        if k % 2 == 0:
            mix_into(out, k * BAR_SECONDS / 2, env_exp(bell(NOTE["A5"], 1.0, amp=0.12), 0.4))
    return out


def b_mus_win(rng):
    out = silence(4.0)
    for k, f in enumerate((NOTE["C4"], NOTE["E4"], NOTE["G4"], NOTE["C5"])):
        mix_into(out, 0, env_adsr(tone(f, 4.0, amp=0.12), 0.1, 0.8))
    for k, f in enumerate((NOTE["C5"], NOTE["E5"], NOTE["G5"], NOTE["C5"] * 2)):
        mix_into(out, k * 0.2, env_exp(bell(f, 1.2, amp=0.2), 0.35))
    return out


def b_mus_dead(rng):
    out = silence(4.0)
    for k, f in enumerate((NOTE["A3"], NOTE["F3"], NOTE["D3"], NOTE["A3"] / 2)):
        mix_into(out, k * 0.4, env_adsr(tone(f, 3.2, kind="triangle", amp=0.18), 0.08, 0.9))
    return out


# ---------------------------------------------------------------- spec table

def build_specs():
    # Shapes
    spec("cast_projectile", "short noise zip sweeping up", "every Bolt cast", b_cast_projectile)
    spec("cast_puddle", "low thump plus rising shimmer", "every Pool cast", b_cast_puddle)
    spec("cast_orbit", "bell cluster", "every Orbit cast", b_cast_orbit)
    spec("cast_cone", "breathy noise sweep down then up", "every Spray cast", b_cast_cone)
    spec("cast_burst", "riser then boom", "every Nova cast", b_cast_burst)

    # Element layers
    spec("el_fire_cast", "crackle and hiss", "Fire layer of a cast (element A)", b_fire_cast)
    spec("el_water_cast", "two rising bloops", "Water layer of a cast", b_water_cast)
    spec("el_wind_cast", "filtered gust with a slow LFO", "Wind layer of a cast", b_wind_cast)
    spec("el_earth_cast", "50-70 Hz rumble plus dull noise", "Earth layer of a cast", b_earth_cast)
    spec("el_fire_hit", "sizzle pop", "Fire hit (element B)", b_fire_hit)
    spec("el_water_hit", "splash tick", "Water hit", b_water_hit)
    spec("el_wind_hit", "whoosh snip", "Wind hit", b_wind_hit)
    spec("el_earth_hit", "low thud", "Earth hit", b_earth_hit)

    # Compounds
    for c in COMPOUND_ELEMENTS:
        ea, eb = COMPOUND_ELEMENTS[c]
        if ea == eb:
            what = f"two-note {ea} chord (root + octave + fifth)"
        else:
            what = f"{ea} + {eb} chord (both roots + fifth)"
        spec("sig_" + c, what, f"{c.title()} cast signature", b_signature(c))

    # Statuses
    spec("st_burn", "ignite whoosh", "first Burn application", b_st_burn)
    spec("st_slow", "descending sine with a closing filter", "first Slow application", b_st_slow)
    spec("st_stun", "high ring plus thump", "first Stun application", b_st_stun)
    spec("st_root", "low creak", "first Root application", b_st_root)
    spec("st_blind", "gated static burst", "first Blind application", b_st_blind)
    spec("st_confuse", "warbling detuned pair", "first Confuse application", b_st_confuse)
    spec("st_push", "short pitch-up whoosh", "first Push application", b_st_push)
    spec("st_pull", "short pitch-down whoosh", "first Pull application", b_st_pull)
    spec("st_hide", "soft airy hush", "hide_self applied to the player", b_st_hide)

    # Quirks
    spec("qk_split", "two rapid clicks", "quirk: splits in two", b_qk_split)
    spec("qk_repeat", "soft echo tap", "quirk: repeats once", b_qk_repeat)
    spec("qk_trail", "hiss", "quirk: leaves a trail", b_qk_trail)
    spec("qk_big", "pitch-dropped thump", "quirk: bigger but slower", b_qk_big)
    spec("qk_cost", "heartbeat double thump", "quirk: costs 5% health", b_qk_cost)

    # Loops
    spec("loop_pool", "bubbling hum, seamless", "while one or more Pools are active", b_loop_pool, loop=True)
    spec("loop_orbit", "airy shimmer, seamless", "while one or more Orbits are active", b_loop_orbit, loop=True)

    # Player
    spec("pl_hurt", "short pained grunt", "player takes damage", b_pl_hurt)
    spec("pl_dash", "quick whoosh", "dash start", b_pl_dash)
    spec("pl_lowhp", "lub-dub heartbeat loop", "HP below 30% in a room", b_pl_lowhp, loop=True)
    spec("pl_die", "descending tone", "player death", b_pl_die)
    spec("pl_heal", "rising shimmer", "heal on room clear", b_pl_heal)

    # Enemies
    spec("en_spawn", "wisp pulse", "telegraph resolves into an enemy", b_en_spawn)
    spec("en_hit", "generic thud", "enemy bolt hits the player", b_en_hit)
    spec("en_die", "descending pop", "enemy killed", b_en_die)
    spec("en_charge_windup", "rising saw windup", "charger telegraph", b_en_charge_windup)
    spec("en_charge", "fast whoosh", "charger dash start", b_en_charge)
    spec("en_slinger_shot", "plasma pew", "slinger fires", b_en_slinger_shot)
    spec("en_brute_stomp", "low boom", "brute stomp", b_en_brute_stomp)
    spec("en_splitter_pop", "wet pop", "splitter splits", b_en_splitter_pop)
    spec("en_wall_stun", "clang plus thud", "charger slams a wall", b_en_wall_stun)
    spec("boss_roar", "low growl", "boss spawn / phase change", b_boss_roar)
    spec("boss_ring", "chime cluster", "boss 8-bullet ring", b_boss_ring)
    spec("boss_charge", "big whoosh", "boss charge", b_boss_charge)
    spec("boss_summon", "dark swell", "boss summons wisps", b_boss_summon)
    spec("boss_die", "long fall", "boss death", b_boss_die)

    # UI / flow
    spec("ui_hover", "tiny tick", "pointer enters a button (throttled)", b_ui_hover)
    spec("ui_click", "click", "button press", b_ui_click)
    spec("ui_card", "paper swish", "reward card appears", b_ui_card)
    spec("ui_pick", "bright ding", "element picked", b_ui_pick)
    spec("ui_craft", "sparkle chord", "successful cauldron craft", b_ui_craft)
    spec("ui_craft_bad", "low buzz", "invalid cauldron attempt", b_ui_craft_bad)
    spec("ui_cauldron_loop", "bubbling loop", "while in CAULDRON", b_ui_cauldron_loop, loop=True)
    spec("room_clear", "short fanfare", "room cleared", b_room_clear)
    spec("state_win", "major chord swells", "WIN screen", b_state_win)
    spec("state_dead", "minor descent", "DEAD screen", b_state_dead)
    spec("state_title", "soft bell", "TITLE screen", b_state_title)

    # Later phases
    spec("rx_steam", "steam hiss", "reaction: Steam", b_rx_steam)
    spec("rx_shatter", "glass shards", "reaction: Shatter", b_rx_shatter)
    spec("rx_flare", "flare whoosh", "reaction: Flare", b_rx_flare)
    spec("rx_bog", "bog blubs", "reaction: Bog", b_rx_bog)
    spec("rx_whirl", "whirl chord", "reaction: Whirl", b_rx_whirl)
    spec("combo_up", "rising arpeggio", "combo streak increases", b_combo_up)
    spec("fusion", "four-note chord", "Resonance fusion", b_fusion)
    spec("hit_weak", "dull tap", "hit a resistant/weak enemy (weak)", b_hit_weak)
    spec("hit_resist", "metallic tick", "hit a resistant enemy", b_hit_resist)
    spec("crit_streak", "high ping", "critical streak", b_crit_streak)
    spec("relic_get", "relic sparkle", "relic acquired", b_relic_get)
    spec("shrine", "soft hum", "shrine interaction", b_shrine)
    spec("shop_buy", "coin chime", "shop purchase", b_shop_buy)

    # Music (loops share the 8-bar 100 BPM room length)
    spec("mus_room_pad", "sustained D-minor pentatonic pad (8 bars, 100 BPM)", "ROOM bed; always audible", b_mus_room_pad, bus="music", loop=True, peak=0.7)
    spec("mus_room_rhythm", "soft kick and noise hat (same length)", "ROOM; fades in above intensity 0.25", b_mus_room_rhythm, bus="music", loop=True, peak=0.7)
    spec("mus_room_lead", "sparse arpeggio (same length)", "ROOM; fades in above intensity 0.6", b_mus_room_lead, bus="music", loop=True, peak=0.7)
    spec("mus_boss", "faster minor ostinato, all layers", "BOSS room", b_mus_boss, bus="music", loop=True, peak=0.7)
    spec("mus_title", "pad plus occasional bell", "TITLE screen", b_mus_title, bus="music", loop=True, peak=0.7)
    spec("mus_win", "major chord fanfare", "WIN screen sting (non-looping)", b_mus_win, bus="music", peak=0.7)
    spec("mus_dead", "minor descent", "DEAD screen sting (non-looping)", b_mus_dead, bus="music", peak=0.7)


# ---------------------------------------------------------------- output

def wav_path(sid, bus):
    folder = MUSIC_DIR if bus == "music" else SFX_DIR
    return folder / (sid + ".wav")


def write_wav(path, samples):
    path.parent.mkdir(parents=True, exist_ok=True)
    frames = bytearray()
    for v in samples:
        v = max(-1.0, min(1.0, v))
        frames += struct.pack("<h", int(round(v * 32767)))
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(frames))


def write_map():
    rows = []
    rows.append("| id | file | what it should sound like | where it plays | bus | loop | status |")
    rows.append("|---|---|---|---|---|---|---|")
    for sid in sorted(SPECS):
        s = SPECS[sid]
        path = wav_path(sid, s["bus"])
        rel = path.relative_to(ROOT).as_posix()
        rows.append("| `%s` | `%s` | %s | %s | %s | %s | placeholder |" % (
            sid, rel, s["desc"], s["where"], s["bus"], "yes" if s["loop"] else "no"))
    header = 0
    lines = MAP_PATH.read_text(encoding="utf-8").splitlines() if MAP_PATH.exists() else []
    for i, line in enumerate(lines):
        if line.startswith("| id |"):
            header = i
            break
    if header == 0:
        lines = lines[:0]
    out = lines[:header] + rows + [""]
    MAP_PATH.parent.mkdir(parents=True, exist_ok=True)
    MAP_PATH.write_text("\n".join(out), encoding="utf-8", newline="\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--force", action="store_true", help="overwrite existing files")
    ap.add_argument("--only", nargs="*", help="only these ids")
    ap.add_argument("--no-map", action="store_true", help="do not rewrite SFX_MAP.md")
    args = ap.parse_args()

    build_specs()
    wanted = args.only or sorted(SPECS)
    wrote, skipped, unknown = 0, 0, []
    print("%-22s %-8s %s" % ("id", "action", "file"))
    for sid in wanted:
        s = SPECS.get(sid)
        if not s:
            unknown.append(sid)
            continue
        path = wav_path(sid, s["bus"])
        if path.exists() and not args.force:
            print("%-22s %-8s %s" % (sid, "skip", path.relative_to(ROOT).as_posix()))
            skipped += 1
            continue
        rng = random.Random(zlib.crc32(sid.encode("utf-8")))
        samples = s["build"](rng)
        samples = finish(samples, s["peak"])
        write_wav(path, samples)
        print("%-22s %-8s %s" % (sid, "write", path.relative_to(ROOT).as_posix()))
        wrote += 1
    if not args.no_map:
        write_map()
        print("map: wrote %s" % MAP_PATH.relative_to(ROOT).as_posix())
    print("\n%d written, %d skipped, %d unknown" % (wrote, skipped, len(unknown)))
    for sid in unknown:
        print("  unknown id: %s" % sid)
    return 0 if not unknown else 2


if __name__ == "__main__":
    raise SystemExit(main())
