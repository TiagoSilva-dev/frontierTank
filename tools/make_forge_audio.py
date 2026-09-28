"""Original forge stingers. Rebuild with Python, numpy and soundfile (libsndfile).

The charge lasts 1.05 s and the result starts at the ForgeOutcome reveal.
"""
from pathlib import Path
import numpy as np
import soundfile as sf

SR = 44100
OUT = Path(__file__).resolve().parents[1] / 'assets/audio/sfx'
RNG = np.random.default_rng(917)


def tone(freq, duration, metal=False):
    t = np.arange(round(duration * SR)) / SR
    ratios = [1, 2.76, 5.4, 8.93] if metal else [1, 2, 3, 4, 5]
    return sum(np.sin(2 * np.pi * freq * r * t) * np.exp(-t * (1.5 + i)) / (i + 1)**1.4
               for i, r in enumerate(ratios)) * np.minimum(t / .008, 1)


def add(out, sound, at=0, gain=1):
    i = round(at * SR)
    n = min(len(sound), len(out) - i)
    out[i:i+n] += sound[:n] * gain


def save(name, x):
    # Early reflections and a stereo tail; fixed peak with soft output fade.
    left = np.pad(x, (0, SR // 2))
    right = left.copy()
    for delay, gain in [(.071, .19), (.139, .12), (.231, .08), (.37, .05)]:
        d = round(delay * SR)
        left[d:d+len(x)] += x * gain
        d += 173
        right[d:d+len(x)] += x * gain
    stereo = np.column_stack((left, right))
    stereo *= .8 / max(.01, float(np.abs(stereo).max()))
    stereo[-2205:] *= np.linspace(1, 0, 2205)[:, None]
    OUT.mkdir(parents=True, exist_ok=True)
    sf.write(OUT / (name + '.ogg'), stereo, SR, format='OGG', subtype='VORBIS')
    print(name, round(len(stereo) / SR, 2), 'seconds, peak', round(float(np.abs(stereo).max()), 3))


def main():
    t = np.arange(round(1.05 * SR)) / SR
    charge = np.sin(2*np.pi*(95*t + 180*t*t)) * (t / 1.05)**1.6 * .35
    for i, note in enumerate([440, 554.37, 659.25, 880, 1108.73, 1318.51]):
        add(charge, tone(note, .5, True), i * .14, .18 + i * .035)
    save('forge_charge', charge)
    t = np.arange(round(2.8 * SR)) / SR
    success = np.sin(2*np.pi*(48*t + 1.5*(1-np.exp(-t*12)))) * np.exp(-t*6) * .8
    add(success, RNG.normal(0, .3, round(.16*SR)) * np.exp(-np.arange(round(.16*SR))/SR*35))
    for i, freq in enumerate([220, 277.18, 329.63, 440]):
        add(success, tone(freq, 2.6), .02 + i*.015, .35)
    for i, freq in enumerate([880, 1108.73, 1318.51, 1760]):
        add(success, tone(freq, 1.8, True), .18 + i*.13, .27)
    save('forge_success', success)
    failure = np.zeros(round(1.6 * SR))
    for i, freq in enumerate([329.63, 293.66, 220]):
        add(failure, tone(freq, 1.1, True), i*.17, .4)
    save('forge_failure', failure)
    loot = np.zeros(round(.9*SR))
    add(loot, tone(880, .7, True), 0, .4)
    add(loot, tone(1318.51, .7, True), .12, .35)
    save('ui_loot', loot)


if __name__ == '__main__':
    main()
