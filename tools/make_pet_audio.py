"""Original stingers of the Casa dos Mascotes (0.19): the egg shaking, cracking and the
reveal of each rarity; and (0.20) the Caçada: a soft hit, a skill, a win jingle, the
warning of a Lendário and the capture. Rebuild with the venv that has numpy and scipy (ffmpeg with
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
from scipy.signal import butter, sosfilt

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
    # Caçada (0.20): short sounds, they repeat for hours.
    hit = np.zeros(round(.22 * SR))
    add(hit, thump(150), 0, .7)
    add(hit, noise(.05, 70), 0, .22)
    save('hunt_hit', hit)
    skill = np.zeros(round(.6 * SR))
    t = np.arange(len(skill)) / SR
    add(skill, np.sin(2 * np.pi * (500 + 1800 * t) * t) * np.exp(-t * 6) * .3)
    add(skill, noise(.25, 14), 0, .12)
    for i, f in enumerate([880, 1318.51]):
        add(skill, tone(f, .4, True), .05 + i * .07, .25)
    save('hunt_skill', skill)
    win = np.zeros(round(.9 * SR))
    for i, f in enumerate([523.25, 659.25, 783.99]):
        add(win, tone(f, .6, True), i * .09, .4)
    save('hunt_win', win)
    boss = np.zeros(round(1.8 * SR))
    add(boss, thump(52), 0, 1.0)
    add(boss, thump(46), .55, .9)
    t = np.arange(round(1.4 * SR)) / SR
    add(boss, np.sin(2 * np.pi * (110 + 60 * t) * t) * np.minimum(t / .3, 1) * np.exp(-t * 1.4) * .4, .2)
    for i, f in enumerate([220, 261.63, 329.63]):
        add(boss, tone(f, 1.5), .9 + i * .08, .3)
    save('hunt_boss', boss)
    capture = np.zeros(round(2.0 * SR))
    for i, f in enumerate([392, 523.25, 659.25, 783.99, 1046.5, 1318.51]):
        add(capture, tone(f, 1.6, True), i * .1, .34)
    add(capture, noise(.6, 6) * .14)
    for k in range(6):
        add(capture, tone(2093 + RNG.integers(0, 900), .45, True, 9), .35 + k * .17, .1)
    save('hunt_capture', capture)


def band(x, low, high):
    return sosfilt(butter(2, [low, high], btype='band', fs=SR, output='sos'), x)


def field_attacks():
    """Attack sounds of the top-down field (0.21), one per kind of move:
    fire (bolt and breath of the sun), ice, a claw swipe and a spark for the other orbs."""
    t = np.arange(round(.5 * SR)) / SR
    fire = np.zeros(len(t))
    # A whoosh: rushing noise that opens up and dies away, over a low rumble.
    env = np.minimum(t / .06, 1) * np.exp(-t * 5.5)
    add(fire, band(RNG.normal(0, 1, len(t)), 300, 2600) * env, 0, .55)
    add(fire, np.sin(2 * np.pi * (90 - 40 * t) * t) * np.exp(-t * 7), 0, .5)
    add(fire, band(RNG.normal(0, 1, len(t)), 3000, 7000) * np.exp(-t * 14), 0, .12)
    save('hunt_fire', fire)
    ice = np.zeros(round(.55 * SR))
    ti = np.arange(len(ice)) / SR
    # A frozen crack and glass pings.
    add(ice, band(RNG.normal(0, 1, len(ti)), 2500, 9000) * np.exp(-ti * 22), 0, .45)
    for k, f in enumerate([2093, 2637, 3136, 3951]):
        add(ice, tone(f, .35, True, 9), .02 + k * .045, .22)
    add(ice, band(RNG.normal(0, 1, len(ti)), 600, 2000) * np.exp(-ti * 9), 0, .25)
    save('hunt_ice', ice)
    claw = np.zeros(round(.3 * SR))
    tc = np.arange(len(claw)) / SR
    # Three quick swipes of filtered noise rising in pitch.
    for k in range(3):
        n = band(RNG.normal(0, 1, len(tc)), 1400 + k * 500, 6500)
        add(claw, n * np.exp(-(tc - .0) * 26) * np.minimum(tc / .004, 1), k * .035, .38)
    add(claw, thump(120), .06, .35)
    save('hunt_claw', claw)
    zap = np.zeros(round(.45 * SR))
    tz = np.arange(len(zap)) / SR
    add(zap, np.sin(2 * np.pi * (300 + 2400 * tz) * tz) * np.exp(-tz * 7) * np.minimum(tz / .005, 1), 0, .38)
    add(zap, band(RNG.normal(0, 1, len(tz)), 1500, 6000) * np.exp(-tz * 18), 0, .2)
    save('hunt_zap', zap)


if __name__ == '__main__':
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == 'field':
        field_attacks()
    else:
        main()
        field_attacks()
