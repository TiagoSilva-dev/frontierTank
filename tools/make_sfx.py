"""Generate every sound effect of Frontier Tank into assets/audio/sfx/*.ogg.

Each weapon has its own firing sound (fire_<weapon id>) and a flavour layer played
with the explosion (impact_<weapon id>); then explosions, POW, skills 1–9, tools,
battle cues, stingers and UI clicks. Run from the project root:

    python tools/make_sfx.py [name ...]      (no names = everything)
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
from synth import *  # noqa: E402,F401,F403

OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "sfx"
SOUNDS: dict = {}


LOOPS = {"charge_loop"}


def sound(name: str, level: float = -16.0, verb: float = 0.0):
    """Register a recipe: RMS target (dBFS over the loud part) and optional room."""
    def wrap(fn):
        SOUNDS[name] = (fn, level, verb)
        return fn
    return wrap


def rng(seed: int) -> np.random.Generator:
    return np.random.default_rng(seed)


# ---------------------------------------------------------------- building blocks

def whoosh(dur: float, f0: float, f1: float, width: float = 0.8, attack: float = 0.25, r=None) -> np.ndarray:
    """Air rushing past: band-passed noise with a moving centre and a swell."""
    n = samples(dur)
    tt = timeline(n)
    body = sweep(white(n, r), "bandpass", f0, f1, width)
    env = np.sin(np.clip(tt / (dur * attack), 0, 1) * np.pi / 2) ** 2 * np.exp(-np.maximum(0, tt - dur * attack) / (dur * 0.35))
    return body * env


def boom(dur: float = 0.8, f0: float = 110.0, f1: float = 38.0, tau: float = 0.35, r=None) -> np.ndarray:
    n = samples(dur)
    tt = timeline(n)
    body = sine(glide(f0, f1, n, 3.0), n) * np.exp(-tt / tau)
    rumble = lp(white(n, r), 260) * np.exp(-tt / (tau * 1.2)) * 1.4
    return drive(body + rumble, 1.5)


def thump(dur: float = 0.18, f0: float = 150.0, f1: float = 55.0, r=None) -> np.ndarray:
    n = samples(dur)
    tt = timeline(n)
    return sine(glide(f0, f1, n, 4.0), n) * np.exp(-tt / (dur * 0.35)) + lp(white(n, r), 900) * np.exp(-tt / 0.01) * 0.5


def crackle(dur: float, density: float = 60.0, low: float = 1500.0, high: float = 9000.0, decay: float | None = None, r=None) -> np.ndarray:
    """Sparse random clicks (fire, gravel, electricity)."""
    r = r or RNG
    n = samples(dur)
    clicks = np.zeros(n)
    count = int(density * dur)
    idx = r.integers(0, n, count)
    clicks[idx] = r.uniform(-1, 1, count) * r.uniform(0.3, 1.0, count) ** 2
    out = bp(clicks, low, high)
    out = np.convolve(out, np.exp(-np.arange(samples(0.003)) / samples(0.0008)), mode="same")
    if decay:
        out *= np.exp(-timeline(n) / decay)
    return out


def chime(notes: list[str], step: float, dur: float = 1.2, vel: float = 0.6, detune: float = 6.0) -> np.ndarray:
    out = canvas(step * len(notes) + dur)
    for i, name in enumerate(notes):
        f = hz(note(name))
        tone = bell(f, dur, vel) + bell(f * cents(detune), dur, vel * 0.6)
        place(out, tone, i * step)
    return out


def sparkle(dur: float, density: float = 30.0, low: float = 2500.0, high: float = 7000.0, r=None) -> np.ndarray:
    """Twinkles: short high sine pings at random pitches."""
    r = r or RNG
    out = canvas(dur + 0.2)
    for _ in range(int(density * dur)):
        f = r.uniform(low, high)
        n = samples(r.uniform(0.04, 0.12))
        ping = sine(f, n) * np.exp(-timeline(n) / (n / SR / 4)) * r.uniform(0.2, 0.6)
        place(out, ping, r.uniform(0, dur))
    return out


def zap(dur: float, low: float = 180.0, high: float = 1400.0, hop: float = 0.008, r=None) -> np.ndarray:
    """Electric arc: saw that jumps between random pitches, driven hard."""
    r = r or RNG
    n = samples(dur)
    hops = max(2, int(dur / hop))
    steps = np.exp(r.uniform(np.log(low), np.log(high), hops))
    freq = np.repeat(steps, int(np.ceil(n / hops)))[:n]
    return hp(drive(saw(freq, n) + square(freq * 1.01, n) * 0.5, 3.0), 300)


def metal(freq: float, dur: float, ratios=(1.0, 2.41, 3.87, 5.12, 6.9), decay: float = 0.5, r=None) -> np.ndarray:
    """Struck metal: inharmonic partials with a bright strike."""
    n = samples(dur)
    tt = timeline(n)
    out = np.zeros(n)
    for i, ratio in enumerate(ratios):
        out += sine(freq * ratio, n) * np.exp(-tt / (decay / (1 + i * 0.6))) / (1 + i * 0.5)
    out += hp(white(n, r), 3000) * np.exp(-tt / 0.006) * 0.8
    return out


def slide_whistle(dur: float, f0: float, f1: float, vibrato: float = 6.0) -> np.ndarray:
    n = samples(dur)
    tt = timeline(n)
    freq = glide(f0, f1, n) * (1 + 0.012 * np.sin(2 * np.pi * vibrato * tt))
    return (sine(freq, n) + 0.2 * sine(freq * 2, n)) * np.sin(np.clip(tt / dur, 0, 1) * np.pi) ** 0.6


def bubble(f0: float = 450.0, dur: float = 0.06) -> np.ndarray:
    n = samples(dur)
    tt = timeline(n)
    return sine(glide(f0, f0 * 2.2, n), n) * np.exp(-tt / (dur * 0.4))


def fire_roar(dur: float, r=None) -> np.ndarray:
    r = r or RNG
    n = samples(dur)
    flicker = lp(r.standard_normal(n), 14)
    flicker = 0.55 + 0.45 * flicker / (np.max(np.abs(flicker)) + 1e-9)
    body = bp(white(n, r), 180, 1400) * flicker
    return body + crackle(dur, 70, 2000, 8000, r=r) * 0.8


def stack(*parts: tuple) -> np.ndarray:
    """Mix (signal, start seconds, gain) layers into one buffer."""
    length = max(start + p.shape[-1] / SR for p, start, _ in parts)
    stereo_out = any(p.ndim == 2 for p, _, _ in parts)
    out = canvas(length + 0.01, 2 if stereo_out else 1)
    for p, start, gain in parts:
        # Every layer fades out over its last stretch so no component stops dead.
        place(out, fades(p, 0.0, min(0.25, 0.3 * p.shape[-1] / SR)), start, gain)
    return out


# ---------------------------------------------------------------- weapons: firing

@sound("fire_quebra_tijolos", -15, 0.12)
def fire_brick():
    r = rng(11)
    whack = bp(white(samples(0.09), r), 250, 1400) * env_exp(samples(0.09), 0.02)
    spin = whoosh(0.6, 420, 700, 0.7, 0.15, r) * (0.6 + 0.4 * np.sin(2 * np.pi * 9 * timeline(samples(0.6))))
    return stack((thump(0.22, 130, 50, r), 0, 1.0), (whack, 0, 0.9), (crackle(0.16, 220, 1500, 6000, 0.05, r), 0.005, 0.7), (spin, 0.05, 0.5))


@sound("fire_fogo_intenso", -14, 0.15)
def fire_flame():
    r = rng(12)
    n = samples(0.75)
    ignite = sweep(white(n, r), "bandpass", 300, 2600, 1.0, curve=3.0) * env_ar(n, 0.02, 0.22)
    return stack((thump(0.2, 170, 60, r), 0, 0.8), (ignite, 0, 1.0), (fire_roar(0.8, r) * env_ar(samples(0.8), 0.04, 0.3), 0.02, 0.8),
                 (hp(white(samples(0.02), r), 2000), 0, 0.6))


@sound("fire_canhao_arco_iris", -15, 0.3)
def fire_rainbow():
    r = rng(13)
    arp = chime(["C6", "E6", "G6", "C7", "E7", "G7"], 0.045, 0.7, 0.5)
    shimmer = sparkle(0.6, 45, 3000, 9000, r)
    return stack((boom(0.45, 150, 55, 0.12, r), 0, 0.9), (arp, 0.03, 0.9), (shimmer, 0.05, 0.5),
                 (whoosh(0.5, 900, 3500, 0.8, 0.2, r), 0, 0.35))


@sound("fire_vento_de_deus", -15, 0.18)
def fire_wind():
    r = rng(14)
    n = samples(0.85)
    tt = timeline(n)
    spin = 0.55 + 0.45 * np.sin(2 * np.pi * 16 * tt)
    gust = sweep(white(n, r), "bandpass", 700, 2400, 0.9, path=np.interp(tt, [0, 0.25, 0.85], [700, 2400, 900])) * spin
    gust *= env_ar(n, 0.08, 0.35)
    shing = metal(2300, 0.5, (1.0, 1.34, 2.03, 2.71), 0.2, r)
    return stack((gust, 0, 1.0), (shing, 0, 0.55), (thump(0.12, 200, 90, r), 0, 0.4))


@sound("fire_cesto_newton", -16, 0.1)
def fire_apple():
    r = rng(15)
    pop = sine(glide(700, 180, samples(0.05)), samples(0.05)) * env_exp(samples(0.05), 0.02)
    rustle = bp(white(samples(0.35), r), 2500, 7000) * (lp(np.abs(r.standard_normal(samples(0.35))), 40) * 3) * env_exp(samples(0.35), 0.12)
    whistle = slide_whistle(0.4, 520, 1250, 7)
    return stack((thump(0.15, 140, 70, r), 0, 0.7), (pop, 0, 0.9), (rustle, 0.02, 0.5), (whistle, 0.04, 0.35))


@sound("fire_kit_medico", -16, 0.2)
def fire_medkit():
    r = rng(16)
    n = samples(0.14)
    pssht = hp(white(n, r), 2500) * env_ar(n, 0.005, 0.04)
    heal = chime(["E6", "B6", "E7"], 0.07, 0.8, 0.45)
    return stack((thump(0.16, 160, 70, r), 0, 0.7), (pssht, 0, 0.8), (heal, 0.04, 0.7), (sparkle(0.4, 25, 4000, 8000, r), 0.08, 0.3))


@sound("fire_eletrodomestico", -15, 0.12)
def fire_tv():
    r = rng(17)
    n = samples(0.4)
    tt = timeline(n)
    hum = lp(saw(60, n) + saw(120, n) * 0.5 + square(180, n) * 0.3, 1500) * env_ar(n, 0.01, 0.15)
    static = bp(white(samples(0.3), r), 1500, 7000) * env_ar(samples(0.3), 0.01, 0.1)
    whine = sine(glide(6500, 7800, n), n) * env_ar(n, 0.02, 0.1) * 0.15
    clunk = metal(180, 0.3, (1.0, 1.7, 2.9), 0.1, r)
    return stack((boom(0.35, 120, 50, 0.1, r), 0, 0.8), (clunk, 0, 0.5), (hum, 0.01, 0.6), (static, 0.03, 0.6), (whine, 0.02, 1.0))


@sound("fire_trovao", -14, 0.2)
def fire_thunder_orb():
    r = rng(18)
    arc = zap(0.35, 150, 1500, 0.007, r) * env_ar(samples(0.35), 0.003, 0.1)
    rumble = lp(white(samples(0.9), r), 220) * shape(samples(0.9), [(0, 0), (0.05, 1), (0.2, 0.5), (0.35, 0.8), (0.9, 0)])
    return stack((arc, 0, 0.8), (crackle(0.4, 260, 2000, 9000, 0.12, r), 0, 0.9), (rumble, 0.03, 1.4), (thump(0.15, 180, 60, r), 0, 0.5))


@sound("fire_desentupidor", -15, 0.1)
def fire_plunger():
    r = rng(19)
    n = samples(0.12)
    suction = sweep(white(n, r), "bandpass", 1400, 260, 0.35) * env_ar(n, 0.004, 0.05) * 3
    plop = sine(glide(480, 140, samples(0.09)), samples(0.09)) * env_exp(samples(0.09), 0.035)
    m = samples(0.45)
    boing = sine(250 * (1 + 0.08 * np.sin(2 * np.pi * 17 * timeline(m)) * env_exp(m, 0.2)), m) * env_ar(m, 0.01, 0.15)
    bubbles = stack(*[(bubble(r.uniform(350, 700)), 0.12 + i * 0.05, 0.4) for i in range(5)])
    return stack((suction, 0, 0.8), (plop, 0.02, 1.0), (boing, 0.06, 0.35), (bubbles, 0, 1.0))


@sound("fire_cabeca_de_boi", -13, 0.2)
def fire_bull():
    r = rng(20)
    n = samples(0.95)
    tt = timeline(n)
    pitch = np.interp(tt, [0, 0.15, 0.6, 0.95], [85, 118, 100, 70])
    growl = 1 + 0.35 * np.sin(2 * np.pi * 31 * tt)
    voice = saw(pitch, n) * growl + saw(pitch * 1.01, n) * 0.6
    bellow = formant(voice, "o", 0.2) * env_ar(n, 0.06, 0.35)
    snort = bp(white(samples(0.1), r), 900, 3200) * env_ar(samples(0.1), 0.005, 0.03)
    return stack((snort, 0, 0.6), (drive(bellow * 2.5, 2.0), 0.05, 0.9), (boom(0.6, 90, 38, 0.25, r), 0, 1.0))


@sound("fire_bumerangue_amor", -16, 0.25)
def fire_boomerang():
    r = rng(21)
    n = samples(0.8)
    tt = timeline(n)
    whup = 0.5 + 0.5 * np.sin(2 * np.pi * np.cumsum(np.interp(tt, [0, 0.8], [13, 8])) / SR) ** 2
    whirl = sweep(white(n, r), "bandpass", 1100, 600, 0.6) * whup * env_ar(n, 0.05, 0.35)
    love = chime(["A6", "C#7", "E7", "A7"], 0.06, 0.6, 0.4)
    return stack((whirl, 0, 1.0), (love, 0.05, 0.6), (thump(0.12, 170, 80, r), 0, 0.5), (sparkle(0.5, 20, 4000, 8000, r), 0.1, 0.3))


@sound("fire_lanca_antiga", -14, 0.25)
def fire_spear():
    r = rng(22)
    swish = whoosh(0.45, 500, 2800, 0.9, 0.12, r)
    ring = metal(620, 0.9, (1.0, 2.4, 3.9, 5.3), 0.45, r)
    jade = stack(*[(bell(hz(note(x)), 0.8, 0.3), 0.05 + i * 0.03, 1.0) for i, x in enumerate(["B6", "E7", "F#7"])])
    return stack((thump(0.2, 140, 55, r), 0, 0.7), (swish, 0, 1.1), (ring, 0.01, 0.4), (jade, 0.05, 0.4))


@sound("fire_boss", -13, 0.3)
def fire_boss():
    r = rng(23)
    roar = fire_roar(1.1, r) * env_ar(samples(1.1), 0.05, 0.45)
    blast = braam(note("D2"), 0.7, 1.0, r)
    return stack((mono(blast), 0, 0.5), (roar, 0, 1.0), (boom(0.9, 90, 32, 0.35, r), 0, 1.0))


@sound("fire_plane", -18, 0.1)
def fire_plane():
    r = rng(24)
    n = samples(0.7)
    flutter = 0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 26 * timeline(n)))
    paper = bp(white(n, r), 1500, 5000) * flutter * env_ar(n, 0.03, 0.2)
    return stack((whoosh(0.7, 600, 1600, 0.8, 0.3, r), 0, 0.9), (paper, 0, 0.4))


# ---------------------------------------------------------------- weapons: impact flavour

@sound("impact_quebra_tijolos", -18)
def impact_brick():
    r = rng(31)
    return stack((crackle(0.7, 180, 400, 4000, 0.18, r), 0, 1.0), (crackle(0.5, 90, 150, 1200, 0.2, r), 0.05, 1.0))


@sound("impact_fogo_intenso", -17)
def impact_flame():
    r = rng(32)
    return fire_roar(0.9, r) * env_ar(samples(0.9), 0.01, 0.3)


@sound("impact_canhao_arco_iris", -19, 0.3)
def impact_rainbow():
    r = rng(33)
    return stack((chime(["G7", "E7", "C7", "G6"], 0.04, 0.7, 0.4), 0, 1.0), (sparkle(0.6, 50, 3500, 9000, r), 0, 0.6))


@sound("impact_vento_de_deus", -19)
def impact_wind():
    r = rng(34)
    return whoosh(0.8, 1800, 500, 0.9, 0.1, r)


@sound("impact_cesto_newton", -18)
def impact_apple():
    r = rng(35)
    n = samples(0.25)
    splat = bp(white(n, r), 600, 3500) * env_ar(n, 0.002, 0.05)
    squish = sweep(white(n, r), "bandpass", 900, 250, 0.5) * env_ar(n, 0.01, 0.08)
    return stack((splat, 0, 1.0), (squish, 0.01, 1.0), (thump(0.15, 120, 60, r), 0, 0.6))


@sound("impact_kit_medico", -19, 0.2)
def impact_medkit():
    r = rng(36)
    fizz = hp(white(samples(0.6), r), 3000) * env_ar(samples(0.6), 0.01, 0.2) * (0.5 + 0.5 * np.abs(np.sin(2 * np.pi * 23 * timeline(samples(0.6)))))
    return stack((metal(2600, 0.4, (1.0, 1.5, 2.2), 0.15, r), 0, 0.6), (fizz, 0.02, 0.6), (chime(["B6", "E7"], 0.06, 0.6, 0.3), 0.05, 1.0))


@sound("impact_eletrodomestico", -17)
def impact_tv():
    r = rng(37)
    glass = stack(*[(metal(r.uniform(2500, 6000), 0.3, (1.0, 1.61, 2.37), 0.08, r), r.uniform(0, 0.25), r.uniform(0.2, 0.5)) for _ in range(14)])
    spark = zap(0.25, 300, 2000, 0.01, r) * env_ar(samples(0.25), 0.002, 0.07)
    return stack((glass, 0, 1.0), (spark, 0.01, 0.4))


@sound("impact_trovao", -16)
def impact_thunder():
    r = rng(38)
    return stack((zap(0.2, 200, 2500, 0.005, r) * env_ar(samples(0.2), 0.001, 0.05), 0, 0.8), (crackle(0.5, 300, 1500, 9000, 0.15, r), 0, 1.0))


@sound("impact_desentupidor", -17)
def impact_plunger():
    r = rng(39)
    n = samples(0.5)
    splash = sweep(white(n, r), "bandpass", 3000, 700, 0.9) * env_ar(n, 0.005, 0.12)
    bubbles = stack(*[(bubble(r.uniform(300, 900), 0.05), r.uniform(0.02, 0.4), r.uniform(0.3, 0.6)) for _ in range(9)])
    return stack((splash, 0, 0.8), (bubbles, 0, 1.0), (sine(glide(300, 90, samples(0.2)), samples(0.2)) * env_exp(samples(0.2), 0.06), 0, 0.8))


@sound("impact_cabeca_de_boi", -15)
def impact_bull():
    r = rng(40)
    stomps = stack(*[(thump(0.2, 110, 45, r), i * 0.09, 1.0 - i * 0.15) for i in range(4)])
    return stack((stomps, 0, 1.0), (crackle(0.5, 120, 200, 2500, 0.2, r), 0.02, 0.8))


@sound("impact_bumerangue_amor", -19, 0.25)
def impact_boomerang():
    return stack((chime(["E7", "C#7", "A6"], 0.05, 0.6, 0.45), 0, 1.0), (bubble(900, 0.05), 0, 0.5))


@sound("impact_lanca_antiga", -16)
def impact_spear():
    r = rng(42)
    return stack((metal(420, 1.0, (1.0, 2.2, 3.6, 5.1), 0.4, r), 0, 0.7), (thump(0.3, 120, 40, r), 0, 1.0), (crackle(0.4, 100, 300, 3000, 0.15, r), 0.02, 0.6))


# ---------------------------------------------------------------- explosions

def explosion(size: float, seed: int) -> np.ndarray:
    r = rng(seed)
    dur = 1.0 + size * 0.9
    n = samples(dur)
    tt = timeline(n)
    crack = hp(white(samples(0.03), r), 1200) * env_exp(samples(0.03), 0.008)
    body = lp(white(n, r), 700 + 500 * size) * (0.6 * np.exp(-tt / (0.12 + size * 0.1)) + 0.4 * np.exp(-tt / (0.4 + size * 0.35)))
    sub = sine(glide(95 - size * 20, 32, n, 2.0), n) * np.exp(-tt / (0.25 + size * 0.2))
    debris = crackle(dur * 0.8, 70, 500, 5000, 0.35 + size * 0.2, r) * 0.6
    mix = stack((crack, 0, 0.9), (drive(body * 1.8, 1.6), 0, 1.0), (sub, 0, 1.3), (debris, 0.04, 1.0))
    return stereo(mix)


@sound("explosion_small", -15, 0.15)
def explosion_small():
    return explosion(0.0, 51)


@sound("explosion_medium", -14, 0.2)
def explosion_medium():
    return explosion(0.5, 52)


@sound("explosion_big", -13, 0.25)
def explosion_big():
    return explosion(1.0, 53)


# ---------------------------------------------------------------- POW and weapon specials

@sound("pow_activate", -15, 0.35)
def pow_activate():
    r = rng(61)
    dur = 1.25
    n = samples(dur)
    tt = timeline(n)
    riser = sweep(white(n, r), "bandpass", 300, 5000, 0.7, curve=0.8) * (tt / dur) ** 1.5
    tone = np.zeros(n)
    for k, ratio in enumerate([1.0, 1.5, 2.0, 3.0]):
        tone += saw(glide(110 * ratio, 330 * ratio, n, 0.9), n) / (1 + k)
    tone = lp(tone, 2500) * (tt / dur) ** 2
    shing = metal(1800, 0.8, (1.0, 1.5, 2.0, 2.5, 3.0), 0.35, r)
    return stack((riser, 0, 0.8), (tone, 0, 0.35), (shing, dur - 0.05, 0.5), (sparkle(0.6, 40, 3000, 9000, r), dur - 0.1, 0.6))


@sound("pow_fire", -12, 0.45)
def pow_fire():
    r = rng(62)
    hit = braam(note("D2"), 1.4, 1.0, r)
    choir = formant(choir_voice(note("D4"), 1.0, 0.9, 0.04, 0.6, 5, r) + choir_voice(note("A4"), 1.0, 0.8, 0.04, 0.6, 5, r)
                    + choir_voice(note("F#5"), 1.0, 0.6, 0.04, 0.6, 5, r), "a")
    return stack((stereo(taiko(1.0, 1.1, 1.6, r)), 0, 1.0), (hit, 0, 0.6), (choir, 0.01, 0.7), (cymbal(0.7, 2.5, r), 0, 0.5),
                 (stereo(boom(1.2, 80, 30, 0.45, r)), 0, 0.8))


@sound("special_beam", -15, 0.4)
def special_beam():
    r = rng(63)
    dur = 1.3
    n = samples(dur)
    tt = timeline(n)
    chord = sum(saw(hz(note(x)) * (1 + 0.004 * np.sin(2 * np.pi * 6 * tt)), n) for x in ["C5", "E5", "G5", "C6"])
    laser = sweep(chord, "bandpass", 500, 4000, 0.5, path=900 + 700 * np.sin(2 * np.pi * 2.5 * tt) ** 2 + 2000 * tt / dur)
    laser *= env_ar(n, 0.05, 0.5)
    return stack((laser, 0, 0.9), (sparkle(1.1, 60, 3000, 9000, r), 0, 0.5), (boom(0.8, 120, 40, 0.3, r), 0, 0.7))


@sound("special_lightning", -12, 0.3)
def special_lightning():
    r = rng(64)
    crack = hp(white(samples(0.06), r), 900) * env_exp(samples(0.06), 0.015)
    rumble = lp(white(samples(2.0), r), 180) * shape(samples(2.0), [(0, 0), (0.05, 1), (0.3, 0.55), (0.5, 0.8), (0.9, 0.3), (2.0, 0)])
    return stack((crack, 0, 1.2), (zap(0.3, 300, 3000, 0.004, r) * env_ar(samples(0.3), 0.001, 0.08), 0, 0.6),
                 (crackle(0.6, 350, 1500, 9000, 0.2, r), 0, 1.0), (rumble, 0.03, 2.2))


@sound("special_bull", -12, 0.3)
def special_bull():
    r = rng(65)
    roar = fire_bull()
    hooves = stack(*[(thump(0.18, 120, 50, r), i * 0.11, 0.9) for i in range(8)])
    return stack((roar, 0, 1.0), (hooves, 0.1, 0.8), (whoosh(0.9, 400, 1500, 0.9, 0.5, r), 0, 0.5))


@sound("special_heal", -16, 0.45)
def special_heal():
    r = rng(66)
    harp = stack(*[(pluck(note(x), 1.4, 0.6, 1.2, rng=r), i * 0.06, 1.0) for i, x in enumerate(["C5", "E5", "G5", "C6", "E6", "G6", "C7"])])
    choir = formant(choir_voice(note("C5"), 0.9, 0.5, 0.2, 0.6, 4, r) + choir_voice(note("G5"), 0.9, 0.4, 0.2, 0.6, 4, r), "o")
    return stack((harp, 0, 0.9), (choir, 0.05, 0.6), (sparkle(1.0, 25, 4000, 9000, r), 0.1, 0.35))


@sound("special_hearts", -17, 0.35)
def special_hearts():
    r = rng(67)
    return stack((chime(["A6", "C#7", "E7", "A6", "E7", "A7"], 0.08, 0.7, 0.5), 0, 1.0), (bubble(700, 0.05), 0, 0.6), (bubble(900, 0.05), 0.16, 0.6))


@sound("special_tornado", -15, 0.2)
def special_tornado():
    r = rng(68)
    n = samples(1.4)
    tt = timeline(n)
    swirl = sweep(white(n, r), "bandpass", 400, 1600, 0.7, path=700 + 500 * np.sin(2 * np.pi * 3 * tt) + 600 * tt)
    return stack((swirl * env_ar(n, 0.2, 0.6), 0, 1.0), (lp(white(n, r), 150) * env_ar(n, 0.3, 0.5), 0, 1.2))


@sound("special_freeze", -16, 0.35)
def special_freeze():
    r = rng(69)
    crystals = stack(*[(bell(r.uniform(2500, 5500), 0.9, 0.4, (1.0, 2.1, 3.3), (1, 0.4, 0.2), (1, 0.5, 0.3)), i * 0.035, 1.0) for i in range(10)])
    crack = hp(white(samples(0.05), r), 2000) * env_exp(samples(0.05), 0.01)
    return stack((crack, 0, 0.9), (crystals, 0, 0.6), (whoosh(0.8, 3000, 6000, 0.5, 0.2, r), 0, 0.3))


@sound("drop_whistle", -20)
def drop_whistle():
    n = samples(0.9)
    tt = timeline(n)
    return sine(glide(1900, 900, n), n) * np.minimum(1, tt / 0.1) * np.exp(-np.maximum(0, tt - 0.6) / 0.1)


@sound("split_pop", -18)
def split_pop():
    r = rng(71)
    return stack((sine(glide(900, 300, samples(0.06)), samples(0.06)) * env_exp(samples(0.06), 0.02), 0, 1.0), (crackle(0.15, 200, 1000, 5000, 0.05, r), 0, 0.7))


@sound("boomerang_return", -18)
def boomerang_return():
    r = rng(72)
    n = samples(0.7)
    tt = timeline(n)
    whup = 0.5 + 0.5 * np.sin(2 * np.pi * 10 * tt) ** 2
    return sweep(white(n, r), "bandpass", 500, 1300, 0.6) * whup * env_ar(n, 0.2, 0.3)


# ---------------------------------------------------------------- skills 1–9, tools, auxiliaries

@sound("skill_multi", -16, 0.25)
def skill_multi():
    r = rng(81)
    arp = stack(*[(brass(note(x), 0.12, 0.8, "trumpet", 0.1, r), i * 0.07, 1.0) for i, x in enumerate(["G4", "C5", "E5", "G5"])])
    return stack((mono(arp), 0, 0.8), (sparkle(0.4, 40, 3000, 8000, r), 0.15, 0.5), (whoosh(0.35, 800, 3000, 0.8, 0.6, r), 0, 0.4))


@sound("skill_power", -15, 0.25)
def skill_power():
    r = rng(82)
    hit = mono(brass(note("C3"), 0.35, 1.0, "trombone", 0.2, r) + brass(note("G3"), 0.35, 0.9, "trombone", 0.2, r))
    return stack((whoosh(0.35, 400, 2500, 0.8, 0.9, r), 0, 0.6), (thump(0.2, 160, 60, r), 0.3, 0.8), (hit, 0.3, 0.8), (sparkle(0.3, 30, 3000, 7000, r), 0.32, 0.4))


@sound("skill_powmax", -16, 0.35)
def skill_powmax():
    r = rng(83)
    n = samples(0.6)
    rise = sine(glide(300, 1500, n), n) * env_ar(n, 0.4, 0.3) * 0.5
    return stack((rise, 0, 0.8), (chime(["C6", "G6", "C7", "E7"], 0.05, 0.8, 0.5), 0.45, 1.0), (sparkle(0.5, 40, 3000, 9000, r), 0.45, 0.4))


@sound("tool_heal", -17, 0.2)
def tool_heal():
    r = rng(84)
    gulps = stack(*[(bubble(r.uniform(250, 420), 0.07), i * 0.1, 0.8) for i in range(3)])
    return stack((gulps, 0, 1.0), (chime(["E6", "G#6", "B6", "E7"], 0.06, 0.8, 0.45), 0.3, 1.0), (sparkle(0.5, 20, 4000, 8000, r), 0.35, 0.3))


@sound("tool_energy", -16, 0.2)
def tool_energy():
    r = rng(85)
    n = samples(0.6)
    charge = zap(0.6, 200, 900, 0.02, r) * (timeline(n) / 0.6) * 0.3
    rise = saw(glide(200, 900, n), n) * env_ar(n, 0.5, 0.1)
    return stack((lp(rise, 2500), 0, 0.5), (charge, 0, 0.6), (metal(1500, 0.4, (1.0, 2.0, 3.0), 0.2, r), 0.55, 0.3))


@sound("tool_shield", -16, 0.3)
def tool_shield():
    r = rng(86)
    n = samples(0.9)
    hum = lp(saw(110, n) + saw(165, n), 700) * env_ar(n, 0.05, 0.4) * 0.4
    return stack((metal(1200, 0.8, (1.0, 1.5, 2.0, 2.5), 0.3, r), 0, 0.7), (hum, 0, 0.6), (whoosh(0.4, 2000, 800, 0.8, 0.2, r), 0, 0.3))


@sound("aux_angel", -16, 0.5)
def aux_angel():
    r = rng(87)
    choir = formant(choir_voice(note("F4"), 1.1, 0.5, 0.15, 0.8, 4, r) + choir_voice(note("A4"), 1.1, 0.5, 0.15, 0.8, 4, r)
                    + choir_voice(note("C5"), 1.1, 0.45, 0.15, 0.8, 4, r), "a")
    harp = stack(*[(pluck(note(x), 1.2, 0.5, 1.2, rng=r), i * 0.05, 1.0) for i, x in enumerate(["F5", "A5", "C6", "F6", "A6"])])
    return stack((choir, 0, 0.8), (harp, 0.05, 0.9), (sparkle(1.0, 20, 4000, 9000, r), 0.1, 0.3))


# ---------------------------------------------------------------- battle cues

@sound("battle_start", -13, 0.4)
def battle_start():
    r = rng(91)
    roll = stack(*[(timpani(note("D2"), 0.25 + 0.5 * i / 16, 0.6, r), i * 0.05, 1.0) for i in range(16)])
    hit = braam(note("D2"), 2.0, 1.0, r)
    return stack((stereo(roll), 0, 0.8), (swell(0.8, 0.6, r), 0, 0.5), (hit, 0.8, 0.7), (stereo(taiko(1.0, 1.1, 1.6, r)), 0.8, 1.0), (cymbal(0.8, 3.0, r), 0.8, 0.5))


@sound("your_turn", -16, 0.35)
def your_turn():
    r = rng(92)
    notes = [("G4", 0.0, 0.14), ("C5", 0.15, 0.14), ("G5", 0.3, 0.45)]
    parts = [(brass(note(x), d, 0.85, "trumpet", 0.2, r), s, 1.0) for x, s, d in notes]
    parts += [(brass(note(x) - 12, d, 0.7, "horn", 0.2, r), s, 0.7) for x, s, d in notes]
    return stack(*parts, (stereo(timpani(note("C3"), 0.6, 1.2, r)), 0.3, 0.6))


@sound("tick", -22)
def tick():
    r = rng(93)
    n = samples(0.08)
    return resonator(white(n, r) * env_exp(n, 0.004), 1800, 12) * 2 + sine(1200, n) * env_exp(n, 0.015) * 0.4


@sound("critical", -14, 0.2)
def critical():
    r = rng(94)
    return stack((metal(1700, 0.8, (1.0, 2.76, 5.4), 0.3, r), 0, 0.8), (thump(0.2, 200, 60, r), 0, 0.9), (sparkle(0.3, 50, 4000, 9000, r), 0.02, 0.5))


@sound("fighter_down", -16, 0.3)
def fighter_down():
    r = rng(95)
    parts = [(brass(note(x), 0.22, 0.6, "trombone", 0.25, r), i * 0.22, 1.0) for i, x in enumerate(["D3", "C#3", "C3"])]
    parts.append((brass(note("B2"), 0.7, 0.6, "trombone", 0.4, r), 0.66, 1.0))
    return stack(*parts, (stereo(thump(0.3, 120, 45, r)), 0.66, 1.2))


@sound("charge_loop", -20)
def charge_loop():
    """Seamless 1 s hum; the game raises its pitch with the force bar. Rendered for 2 s
    so the filter settles, then the last (periodic) second is kept."""
    n = samples(2.0)
    tt = timeline(n)
    tone = saw(220, n) * 0.5 + saw(330, n) * 0.3 + sine(440, n) * 0.4
    wobble = 0.8 + 0.2 * np.sin(2 * np.pi * 8 * tt)
    return (lp(tone, 1800) * wobble)[samples(1.0):]


@sound("victory", -13, 0.45)
def victory():
    r = rng(96)
    beat = 0.2
    line = [("C5", 0, 1), ("C5", 1, 0.5), ("C5", 1.5, 0.5), ("G5", 2, 2), ("E5", 4, 1), ("G5", 5, 1), ("C6", 6, 4)]
    parts = [(brass(note(x), d * beat, 0.9, "trumpet", 0.25, r), s * beat, 1.0) for x, s, d in line]
    parts += [(brass(note(x) - 12, d * beat, 0.8, "horn", 0.3, r), s * beat, 0.8) for x, s, d in line]
    for name, start, length in [("C", 0, 2), ("G", 2, 2), ("Em", 4, 2), ("C", 6, 4)]:
        for m in voicing(name, 60, 4):
            parts.append((strings(m, length * beat + 0.3, 0.5, 0.05, 0.6, 4, rng=r), start * beat, 0.5))
        parts.append((bass(bass_note(name, 2), length * beat, 0.8, rng=r), start * beat, 0.8))
    parts += [(stereo(timpani(note("C3"), 0.9, 1.5, r)), s * beat, 0.8) for s in (0, 2, 6)]
    parts.append((cymbal(0.8, 3.0, r), 6 * beat, 0.6))
    choir = formant(sum(choir_voice(note(x), 4 * beat + 0.4, 0.6, 0.1, 0.8, 4, r) for x in ["C4", "E4", "G4", "C5"]), "a")
    parts.append((choir, 6 * beat, 0.6))
    return stack(*parts)


@sound("defeat", -15, 0.5)
def defeat():
    r = rng(97)
    beat = 0.32
    line = [("A4", 0, 1), ("G4", 1, 1), ("F4", 2, 1), ("E4", 3, 4)]
    parts = [(brass(note(x), d * beat, 0.6, "horn", 0.4, r), s * beat, 1.0) for x, s, d in line]
    for name, start, length in [("Dm", 0, 2), ("Bb", 2, 1), ("A", 3, 4)]:
        for m in voicing(name, 57, 3):
            parts.append((strings(m, length * beat + 0.3, 0.45, 0.2, 0.8, 5, rng=r), start * beat, 0.6))
        parts.append((bass(bass_note(name, 2), length * beat, 0.7, 500, rng=r), start * beat, 0.8))
    parts.append((stereo(timpani(note("A2"), 0.6, 2.0, r)), 3 * beat, 0.7))
    return stack(*parts)


# ---------------------------------------------------------------- interface

@sound("ui_click", -22)
def ui_click():
    r = rng(101)
    n = samples(0.06)
    return resonator(white(n, r) * env_exp(n, 0.003), 1100, 6) * 1.5 + sine(glide(900, 500, n), n) * env_exp(n, 0.012) * 0.5


@sound("ui_open", -22)
def ui_open():
    r = rng(102)
    return stack((whoosh(0.25, 700, 2400, 0.8, 0.5, r), 0, 1.0), (ui_click(), 0.12, 0.6))


@sound("ui_confirm", -19, 0.2)
def ui_confirm():
    return chime(["E6", "B6"], 0.07, 0.5, 0.5)


@sound("ui_error", -19)
def ui_error():
    n = samples(0.22)
    return lp(square(140, n) + square(147, n), 1200) * env_ar(n, 0.005, 0.08)


@sound("ui_coin", -19, 0.15)
def ui_coin():
    r = rng(105)
    return stack((metal(2100, 0.4, (1.0, 1.51, 2.3), 0.12, r), 0, 0.7), (metal(2800, 0.5, (1.0, 1.49, 2.2), 0.15, r), 0.07, 0.7))


@sound("ui_forge", -16, 0.25)
def ui_forge():
    r = rng(106)
    clang = metal(720, 1.1, (1.0, 2.31, 3.72, 5.18, 6.6), 0.4, r)
    return stack((clang, 0, 0.9), (thump(0.15, 180, 80, r), 0, 0.6), (sparkle(0.5, 60, 2500, 7000, r), 0.02, 0.5), (chime(["C6", "G6", "C7"], 0.06, 0.8, 0.4), 0.25, 0.7))


@sound("ui_card", -18, 0.2)
def ui_card():
    r = rng(107)
    flip = whoosh(0.18, 1500, 4000, 0.9, 0.5, r)
    return stack((flip, 0, 0.8), (ui_click(), 0.08, 0.6), (chime(["G6", "D7"], 0.05, 0.6, 0.4), 0.12, 0.7))


# ---------------------------------------------------------------- render

def render(name: str) -> None:
    fn, level, verb = SOUNDS[name]
    x = np.asarray(fn(), dtype=float)
    if name in LOOPS:
        x = x * db(level - rms_db(x))
        write_ogg(str(OUT / f"{name}.ogg"), x, 5)
        print(f"{name:26s} loop {x.shape[-1] / SR:5.2f}s")
        return
    x = fades(x, 0.0005, 0.03)
    if verb > 0:
        x = reverb(x, verb, 1.4, 0.4, 0.01)
    x = trim_silence(x, -62.0)
    x = fades(x, 0.0, 0.05)
    # Level by the loud part only, so long tails do not inflate the gain.
    loud = np.abs(mono(x))
    body = x[..., : max(samples(0.05), int(np.argmax(np.cumsum(loud ** 2) >= 0.9 * np.sum(loud ** 2))))]
    x = x * db(level - rms_db(body))
    x = limiter(x, -1.0) if peak_db(x) > -1.0 else x
    write_ogg(str(OUT / f"{name}.ogg"), x, 5 if x.ndim == 2 else 4)
    print(f"{name:26s} {x.shape[-1] / SR:5.2f}s  peak {peak_db(x):6.1f} dB  rms {rms_db(body * db(level - rms_db(body))):6.1f} dB  {'stereo' if x.ndim == 2 else 'mono'}")


if __name__ == "__main__":
    wanted = sys.argv[1:] or list(SOUNDS)
    for key in wanted:
        render(key)
