"""Original stingers of the Casa dos Mascotes (0.19): the egg shaking, cracking and the
reveal of each rarity. Rebuild with the venv that has numpy and scipy (ffmpeg with
libvorbis turns the wavs into the ogg files):

    python tools/make_pet_audio.py

The shake lasts 1.9 s and the crack 0.5 s (HatchOutcome times them), the reveals start
at the flash.
"""
from pathlib import Path
import subprocess
import tempfile
import numpy as np
from scipy.io import wavfile

SR = 44100
OUT = Path(__file__).resolve().parents[1] / 'assets/audio/sfx'
RNG = np.random.default_rng(1905)


def tone(freq, duration, metal=False, decay=1.5):
    t = np.arange(round(duration * SR)) / SR
    ratios = [1, 2.76, 5.4, 8.93] if metal else [1, 2, 3, 4, 5]
    return sum(np.sin(2 * np.pi * freq * r * t) * np.exp(-t * (decay + i)) / (i + 1)**1.4
               for i, r in enumerate(ratios)) * np.minimum(t / .008, 1)


def add(out, sound, at=0.0, gain=1.0):
    i = round(at * SR)
    n = min(len(sound), len(out) - i)
    if n > 0:
        out[i:i+n] += sound[:n] * gain


def noise(duration, rate):
    n = round(duration * SR)
    return RNG.normal(0, 1, n) * np.exp(-np.arange(n) / SR * rate)


def thump(freq):
    t = np.arange(round(.22 * SR)) / SR
    return np.sin(2 * np.pi * (freq * t - 40 * t * t / .22 * .5)) * np.exp(-t * 16) * np.minimum(t / .004, 1)


def save(name, x):
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
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / (name + '.wav')
        wavfile.write(wav, SR, (stereo * 32767).astype(np.int16))
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', str(wav), '-c:a', 'libvorbis', '-q:a', '5', str(OUT / (name + '.ogg'))], check=True)
    print(name, round(len(stereo) / SR, 2), 'seconds, peak', round(float(np.abs(stereo).max()), 3))


def main():
    # The egg shakes: thumps that speed up and rise, with a faint tremble under them.
    shake = np.zeros(round(1.9 * SR))
    at, gap, i = 0.05, .46, 0
    while at < 1.75:
        add(shake, thump(78 + i * 5), at, .55 + min(i * .05, .35))
        add(shake, noise(.05, 60), at, .06)
        at += gap
        gap = max(.13, gap * .83)
        i += 1
    t = np.arange(len(shake)) / SR
    add(shake, np.sin(2 * np.pi * (140 + 220 * t / 1.9) * t) * (t / 1.9)**2 * .08)
    save('pet_shake', shake)
    # The shell cracks: dry snaps.
    crack = np.zeros(round(.5 * SR))
    for k, at in enumerate([0, .09, .17, .3]):
        add(crack, noise(.07, 55) * np.sin(2 * np.pi * (1800 + k * 400) * np.arange(round(.07 * SR)) / SR), at, .55)
        add(crack, tone(1400 + k * 330, .12, True, 14), at, .12)
    save('pet_crack', crack)
    # Reveals, from a soft chirp to a full fanfare.
    common = np.zeros(round(1.2 * SR))
    add(common, noise(.4, 9) * .12)
    for i, f in enumerate([523.25, 659.25]):
        add(common, tone(f, .8, True), .02 + i * .1, .4)
    save('pet_hatch_comum', common)
    rare = np.zeros(round(1.8 * SR))
    add(rare, noise(.5, 7) * .15)
    for i, f in enumerate([523.25, 659.25, 783.99, 1046.5]):
        add(rare, tone(f, 1.2, True), .02 + i * .09, .38)
    add(rare, tone(261.63, 1.4), 0, .3)
    save('pet_hatch_raro', rare)
    epic = np.zeros(round(2.4 * SR))
    add(epic, thump(60), 0, .8)
    add(epic, noise(.7, 5) * .18)
    for i, f in enumerate([392, 493.88, 587.33, 783.99, 987.77, 1174.66]):
        add(epic, tone(f, 1.8, True), .03 + i * .1, .32)
    for i, f in enumerate([196, 246.94, 293.66]):
        add(epic, tone(f, 2.0), i * .02, .3)
    save('pet_hatch_epico', epic)
    legend = np.zeros(round(3.4 * SR))
    add(legend, thump(48), 0, 1.0)
    add(legend, noise(1.0, 3.5) * .22)
    t = np.arange(round(1.3 * SR)) / SR
    add(legend, np.sin(2 * np.pi * (70 * t + 90 * t * t)) * np.exp(-t * 1.6) * .35)
    for i, f in enumerate([261.63, 329.63, 392, 523.25, 659.25, 783.99, 1046.5, 1318.51, 1568]):
        add(legend, tone(f, 2.8, True), .04 + i * .11, .3 + i * .012)
    for i, f in enumerate([130.81, 196, 261.63]):
        add(legend, tone(f, 3.0), i * .03, .34)
    for k in range(10):
        add(legend, tone(2093 + RNG.integers(0, 900), .5, True, 8), .5 + k * .19, .1)
    save('pet_hatch_lendario', legend)
    level = np.zeros(round(1.0 * SR))
    for i, f in enumerate([659.25, 783.99, 987.77, 1318.51]):
        add(level, tone(f, .55, True), i * .08, .4)
    save('pet_levelup', level)


if __name__ == '__main__':
    main()
