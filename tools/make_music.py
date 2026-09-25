"""Generate the looping music of Frontier Tank into assets/audio/music/*.ogg.

    lobby.ogg     title screen, city, hall and rooms: heroic D major theme, 96 BPM
    battle.ogg    PvP battles: driving D minor with taiko and galloping strings, 140 BPM
    instance.ogg  Instância (Templo do Sol): dark A minor with a Phrygian-dominant colour, 104 BPM

Every track loops seamlessly: the reverb tail after the last bar is folded back into
the first bars. Run from the project root:

    python tools/make_music.py [lobby|battle|instance ...]
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
from synth import *  # noqa: E402,F401,F403

OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "music"


# ---------------------------------------------------------------- song canvas

class Song:
    def __init__(self, bpm: float, bars: int, seed: int):
        self.beat = 60.0 / bpm
        self.bars = bars
        self.length = bars * 4 * self.beat
        self.n = samples(self.length + 8.0)
        self.rng = np.random.default_rng(seed)
        self.buses: dict = {}
        self.cache: dict = {}
        self.round_robin: dict = {}

    def bus(self, name: str, gain: float = 1.0, send: float = 0.25, post=None) -> None:
        self.buses[name] = {"buf": np.zeros((2, self.n)), "gain": gain, "send": send, "post": post}

    def time(self, bar: float, beat: float = 0.0) -> float:
        return (bar * 4 + beat) * self.beat

    def put(self, name: str, audio: np.ndarray, when: float, gain: float = 1.0, human: float = 0.006) -> None:
        when += float(self.rng.uniform(-human, human)) if human else 0.0
        if when < 0:
            when += self.length
        place(self.buses[name]["buf"], stereo(audio) if audio.ndim == 1 else audio, max(0.0, when), gain)

    def sample(self, key: tuple, make, variants: int = 3) -> np.ndarray:
        """Cached one-shots with round robin so repeated hits are not identical."""
        index = self.round_robin.get(key, 0)
        self.round_robin[key] = (index + 1) % variants
        full = key + (index,)
        if full not in self.cache:
            self.cache[full] = make()
        return self.cache[full]

    def render(self, wet: float = 0.3, room: float = 2.6, loud: float = -14.0) -> np.ndarray:
        dry = np.zeros((2, self.n))
        send = np.zeros((2, self.n))
        report = []
        for name, bus in self.buses.items():
            x = bus["buf"]
            if bus["post"] is not None:
                x = bus["post"](x)
            x = x * bus["gain"]
            report.append((name, x))
            dry += x
            send += x * bus["send"]
        wet_signal = reverb(send, 1.0, room, 0.5, 0.02, dry=False)[:, : self.n]
        out = dry + wet_signal * wet
        # Master EQ: tame the sub rumble of taiko and timpani, open up presence and air.
        out = hp(out, 34.0, 3)
        out = peak_eq(out, 55, -4.0, 0.9)
        out = peak_eq(out, 3000, 3.0, 0.7)
        out = peak_eq(out, 8000, 3.5, 0.7)
        # Fold the tail past the last bar into the start so the loop is seamless.
        size = samples(self.length)
        out[:, : self.n - size] += out[:, size:]
        out = out[:, :size]
        # Level by the loud passages (90th percentile of 400 ms windows), then limit.
        window = samples(0.4)
        frames = out[:, : out.shape[1] // window * window].reshape(2, -1, window)
        levels = 10 * np.log10(np.mean(frames ** 2, axis=(0, 2)) + 1e-12)
        gain = db(loud - float(np.percentile(levels, 90)))
        out = limiter(out * gain, -1.2, 0.12)
        for name, x in report:
            # Level while the part plays (400 ms windows above -50 dB of its peak window).
            part = (x * gain)[:, : x.shape[1] // window * window].reshape(2, -1, window)
            energy = np.mean(part ** 2, axis=(0, 2))
            active = energy[energy > np.max(energy) * 1e-5]
            if active.size == 0:
                continue
            print(f"    {name:10s} {10 * np.log10(np.mean(active) + 1e-12):6.1f} dB while playing")
        return out


def chord_events(song: Song, chords: list[str], start_bar: int) -> list[tuple[str, float, float]]:
    """Bars like 'D' or 'G A' (two chords of two beats) -> (name, start s, length s)."""
    events = []
    for i, bar in enumerate(chords):
        names = bar.split()
        size = 4.0 / len(names)
        for k, name in enumerate(names):
            events.append((name, song.time(start_bar + i, k * size), size * song.beat))
    return events


# ---------------------------------------------------------------- parts

def pad(song: Song, bus: str, chords: list[str], start_bar: int, center: int = 62, count: int = 4, vel: float = 0.5,
        attack: float = 0.3, kind: str = "strings", legato: float = 1.02) -> None:
    previous = None
    for name, when, length in chord_events(song, chords, start_bar):
        notes = voicing(name, center, count, previous)
        previous = notes
        for m in notes:
            if kind == "choir":
                tone = choir_voice(m, length * legato, vel, attack, 0.8, 4, song.rng)
            elif kind == "brass":
                tone = brass(m, length * legato, vel, "trombone", 0.3, song.rng)
            else:
                tone = strings(m, length * legato, vel, attack, 0.6, 5, rng=song.rng)
            song.put(bus, tone, when, 1.0 / count ** 0.5, human=0.0)


def bassline(song: Song, bus: str, chords: list[str], start_bar: int, vel: float = 0.7, octave: int = 2,
             pulse: float | None = None, cutoff: float = 650.0) -> None:
    for name, when, length in chord_events(song, chords, start_bar):
        m = bass_note(name, octave)
        if pulse is None:
            song.put(bus, bass(m, length * 1.02, vel, cutoff, 0.3, song.rng), when, human=0.0)
        else:
            step = pulse * song.beat
            for k in range(int(round(length / step))):
                accent = 1.0 if k % 2 == 0 else 0.75
                song.put(bus, bass(m, step * 0.7, vel * accent, cutoff, 0.12, song.rng), when + k * step)


def melody(song: Song, bus: str, text: str, start_bar: int, instrument: str = "horn", vel: float = 0.8,
           shift: int = 0, legato: float = 0.96) -> None:
    for midi, beat, length in parse_line(text):
        if midi is None:
            continue
        when = song.time(start_bar, beat)
        dur = length * song.beat * legato
        accent = vel * (1.06 if beat % 4 == 0 else 1.0) * float(song.rng.uniform(0.94, 1.04))
        if instrument == "strings":
            tone = strings(midi + shift, dur, accent, 0.08, 0.4, 6, rng=song.rng)
        elif instrument == "choir":
            tone = choir_voice(midi + shift, dur, accent, 0.12, 0.5, 5, song.rng)
        elif instrument == "bells":
            tone = stereo(bell(hz(midi + shift), 2.2, accent))
        elif instrument == "pluck":
            tone = stereo(pluck(midi + shift, 1.6, accent, 1.1, rng=song.rng))
        else:
            tone = brass(midi + shift, dur, accent, instrument, 0.25, song.rng)
        song.put(bus, tone, when)


def arpeggio(song: Song, bus: str, chords: list[str], start_bar: int, pattern: list[int], step: float = 0.5,
             center: int = 62, vel: float = 0.5, instrument: str = "harp") -> None:
    for name, when, length in chord_events(song, chords, start_bar):
        notes = voicing(name, center, 3)
        ladder = notes + [m + 12 for m in notes] + [m + 24 for m in notes]
        for k in range(int(round(length / (step * song.beat)))):
            m = ladder[pattern[k % len(pattern)]]
            v = vel * (1.0 if k % 2 == 0 else 0.8)
            if instrument == "spiccato":
                tone = song.sample(("sp", m, round(v, 1)), lambda m=m, v=v: spiccato(m, v, 0.14, 3, song.rng))
            else:
                tone = song.sample(("harp", m, round(v, 1)), lambda m=m, v=v: stereo(pluck(m, 1.8, v, 1.0, rng=song.rng), float(song.rng.uniform(-0.3, 0.3))))
            song.put(bus, tone, when + k * step * song.beat)


def figure(song: Song, bus: str, bars: dict, start_bar: int, instrument: str = "oud", vel: float = 0.55, step: float = 0.5) -> None:
    """Explicit note figures per bar (list of note names, one per step)."""
    for i, names in bars.items():
        for k, name in enumerate(names.split()):
            if name == "r":
                continue
            m = note(name)
            v = vel * (1.0 if k % 2 == 0 else 0.78)
            if instrument == "oud":
                tone = song.sample(("oud", m, round(v, 1)), lambda m=m, v=v: stereo(pluck(m, 1.2, v, 1.4, 16, True, song.rng), -0.25))
            else:
                tone = song.sample(("sp", m, round(v, 1)), lambda m=m, v=v: spiccato(m, v, 0.14, 3, song.rng))
            song.put(bus, tone, song.time(start_bar + i, k * step))


GALLOP = [0, None, 0, 0, 12, None, 0, 0, 0, None, 0, 0, 12, None, 7, 0]


def ostinato(song: Song, bus: str, chords: list[str], start_bar: int, pattern=GALLOP, vel: float = 0.55, base: int = 48) -> None:
    for name, when, length in chord_events(song, chords, start_bar):
        root = base + bass_note(name, 2) % 12
        steps = int(round(length / (0.25 * song.beat)))
        for k in range(steps):
            interval = pattern[k % len(pattern)]
            if interval is None:
                continue
            m = root + interval
            v = vel * (1.0 if k % 4 == 0 else 0.72)
            tone = song.sample(("sp", m, round(v, 1)), lambda m=m, v=v: spiccato(m, v, 0.12, 3, song.rng))
            song.put(bus, tone, when + k * 0.25 * song.beat)


def drums(song: Song, bar: int, grid: dict[str, str], vel: float = 1.0) -> None:
    """One bar of 16 steps per voice: X loud, x normal, o soft, . rest."""
    makers = {
        "big": lambda: stereo(taiko(1.0, 1.15, 1.6, song.rng)),
        "mid": lambda: stereo(taiko(0.9, 0.7, 0.9, song.rng), 0.25),
        "snare": lambda: stereo(snare(0.9, 0.5, 190, song.rng), -0.1),
        "frame": lambda: stereo(frame_drum(0.9, 0.5, song.rng), 0.3),
        "shaker": lambda: stereo(hp(white(samples(0.08), song.rng), 5000) * env_exp(samples(0.08), 0.02) * 0.5, -0.35),
    }
    weights = {"X": 1.0, "x": 0.72, "o": 0.42}
    for voice, steps in grid.items():
        for k, ch in enumerate(steps.replace(" ", "")):
            if ch in weights:
                tone = song.sample((voice,), makers[voice], 4)
                song.put("drums" if voice in ("big", "mid") else "perc", tone, song.time(bar, k * 0.25), weights[ch] * vel)


def timp(song: Song, bar: int, beat: float, name: str, vel: float = 0.8) -> None:
    m = note(name)
    tone = song.sample(("timp", m), lambda: stereo(timpani(m, 1.0, 2.2, song.rng)), 3)
    song.put("drums", tone, song.time(bar, beat), vel)


def roll(song: Song, bar: int, beats: float, name: str, v0: float = 0.2, v1: float = 0.9, start: float = 0.0) -> None:
    hits = int(beats * 6)
    for k in range(hits):
        timp(song, bar, start + k * beats / hits, name, v0 + (v1 - v0) * k / max(1, hits - 1))


def snare_roll(song: Song, bar: int, beats: float, v0: float = 0.15, v1: float = 0.8, start: float = 0.0) -> None:
    hits = int(beats * 8)
    for k in range(hits):
        tone = song.sample(("snare",), lambda: stereo(snare(0.9, 0.5, 190, song.rng), -0.1), 4)
        song.put("perc", tone, song.time(bar, start + k * beats / hits), v0 + (v1 - v0) * k / max(1, hits - 1), human=0.002)


def crash(song: Song, bar: int, vel: float = 0.7, beat: float = 0.0) -> None:
    tone = song.sample(("crash",), lambda: cymbal(1.0, 3.2, song.rng), 2)
    song.put("perc", tone, song.time(bar, beat), vel, human=0.0)


def riser(song: Song, bar: int, beats: float = 2.0, vel: float = 0.5) -> None:
    """Reverse cymbal ending exactly on the downbeat of `bar`."""
    length = beats * song.beat
    song.put("perc", swell(length, 1.0, song.rng), song.time(bar) - length, vel, human=0.0)


def stabs(song: Song, chords: list[str], start_bar: int, beats: list[float], vel: float = 0.8, length: float = 0.5, center: int = 50) -> None:
    for i, bar in enumerate(chords):
        name = bar.split()[0]
        for b in beats:
            for m in voicing(name, center, 3):
                song.put("brass", brass(m, length * song.beat, vel, "trombone", 0.15, song.rng), song.time(start_bar + i, b), 0.6)


def hit(song: Song, bar: int, root: str, vel: float = 0.8) -> None:
    song.put("brass", braam(note(root), 2.4, 1.0, song.rng), song.time(bar), vel, human=0.0)
    song.put("drums", stereo(taiko(1.0, 1.2, 1.8, song.rng)), song.time(bar), 1.0, human=0.0)


# ---------------------------------------------------------------- mixing buses

def standard_buses(song: Song, choir_vowel: str = "a") -> None:
    song.bus("strings", 0.85, 0.35, lambda x: peak_eq(peak_eq(lp(hp(x, 70), 5200), 350, -2.5, 0.8), 2800, 2.0, 1.0))
    song.bus("spiccato", 1.8, 0.25, lambda x: lp(hp(x, 90), 4200))
    song.bus("brass", 0.7, 0.3, lambda x: peak_eq(hp(x, 55), 1300, 2.0, 1.0))
    song.bus("lead", 0.8, 0.32, lambda x: peak_eq(hp(x, 90), 1500, 2.5, 1.0))
    song.bus("choir", 2.8, 0.45, lambda x: lp(hp(formant(x, choir_vowel), 110), 6500))
    song.bus("bass", 0.9, 0.12, lambda x: lp(hp(x, 40), 700))
    song.bus("harp", 1.1, 0.35, lambda x: hp(x, 140))
    song.bus("bells", 2.0, 0.45, lambda x: hp(x, 500))
    song.bus("drums", 0.85, 0.18, lambda x: peak_eq(hp(x, 42), 62, -3.0, 1.0))
    song.bus("perc", 0.5, 0.25, lambda x: hp(x, 120))


# ---------------------------------------------------------------- 1. lobby (title, city, hall, rooms)

def lobby() -> np.ndarray:
    song = Song(96, 32, 101)
    standard_buses(song)
    A = ["D", "A/C#", "Bm", "G", "D", "G", "Em", "A"]
    B = ["D", "Bm", "G", "A", "D", "Bm", "G A", "D"]
    C = ["Bm", "G", "D", "A", "Bm", "G", "Em", "A"]
    D = ["G", "A", "F#m", "Bm", "G", "A", "Bm G", "A"]
    mel_a = "D4:1.5 A4:.5 A4:1 B4:.5 A4:.5 | G4:1 F#4:.5 E4:.5 E4:2 | F#4:1.5 B4:.5 B4:1 C#5:.5 B4:.5 | A4:1 G4:.5 F#4:.5 G4:2 | F#4:1 A4:1 D5:1.5 C#5:.5 | B4:1.5 A4:.5 G4:1 B4:1 | A4:1.5 G4:.5 F#4:1 E4:1 | E4:1 F#4:.5 G4:.5 A4:2"
    mel_b = "A4:1.5 D5:.5 D5:1 E5:.5 F#5:.5 | F#5:1.5 E5:.5 D5:1 C#5:.5 B4:.5 | D5:1.5 C#5:.5 B4:1 D5:1 | C#5:1.5 B4:.5 A4:2 | A4:1.5 D5:.5 D5:1 E5:.5 F#5:.5 | F#5:1 B5:1 A5:1 F#5:1 | G5:1 D5:1 E5:1 C#5:1 | D5:4"
    mel_c = "B3:2 F#4:2 | G4:1.5 F#4:.5 E4:1 D4:1 | F#4:2 A4:2 | E4:3 C#4:1 | B4:2 D5:2 | D5:1.5 C#5:.5 B4:1 G4:1 | G4:1 B4:1 E5:2 | E5:1 C#5:1 A4:1 C#5:.5 E5:.5"
    mel_d = "B4:1.5 D5:.5 D5:1 G5:1 | E5:1.5 F#5:.5 E5:1 C#5:1 | C#5:1.5 F#5:.5 F#5:1 A5:1 | F#5:2 D5:1 B4:1 | B4:1.5 D5:.5 G5:1 F#5:.5 E5:.5 | E5:1 C#5:1 A4:1 E5:1 | D5:2 B4:1 D5:1 | C#5:2 A4:2"
    harp_up = [0, 1, 2, 3, 4, 3, 2, 1]
    # A: harp, soft strings and the horn theme
    pad(song, "strings", A, 0, 62, 4, 0.34, 0.5)
    bassline(song, "bass", A, 0, 0.45)
    arpeggio(song, "harp", A, 0, harp_up, 0.5, 55, 0.5)
    melody(song, "brass", mel_a, 0, "horn", 0.62)
    for bar, name in [(0, "D5"), (2, "B4"), (4, "F#5"), (6, "A5")]:
        melody(song, "bells", f"{name}:4", bar, "bells", 0.35)
    timp(song, 0, 0, "D2", 0.45)
    timp(song, 4, 0, "D2", 0.45)
    roll(song, 7, 2, "A2", 0.15, 0.6, 2)
    riser(song, 8, 2, 0.45)
    # B: full orchestra, trumpets with horns below, choir
    pad(song, "strings", B, 8, 64, 4, 0.5, 0.25)
    pad(song, "choir", B, 8, 67, 3, 0.42, 0.35, "choir")
    bassline(song, "bass", B, 8, 0.65, pulse=0.5)
    melody(song, "lead", mel_b, 8, "trumpet", 0.82)
    melody(song, "brass", mel_b, 8, "horn", 0.66, -12)
    arpeggio(song, "harp", B, 8, harp_up, 0.5, 62, 0.35)
    crash(song, 8, 0.7)
    for i in range(8):
        drums(song, 8 + i, {"big": "X.......x.......", "snare": "....o.......o..." if i < 7 else "....o.......xxXX"})
        timp(song, 8 + i, 0, "D2" if B[i][0] == "D" else "A2", 0.55)
    # C: bridge in B minor, strings drive the pulse
    pad(song, "strings", C, 16, 60, 4, 0.42, 0.3)
    pad(song, "choir", C, 16, 64, 3, 0.25, 0.6, "choir")
    ostinato(song, "spiccato", C, 16, [0, None, 0, None, 7, None, 0, None, 12, None, 7, None, 0, None, 7, None], 0.48, 50)
    bassline(song, "bass", C, 16, 0.55)
    melody(song, "brass", mel_c, 16, "horn", 0.72)
    for i in range(8):
        drums(song, 16 + i, {"big": "X...............", "frame": "..o...o...o...o."})
    snare_roll(song, 23, 4, 0.1, 0.7)
    riser(song, 24, 4, 0.55)
    # D: climax, then the orchestra settles back into the A section
    pad(song, "strings", D, 24, 64, 4, 0.55, 0.2)
    pad(song, "choir", D, 24, 69, 4, 0.5, 0.25, "choir")
    melody(song, "lead", mel_d, 24, "trumpet", 0.9)
    melody(song, "brass", mel_d, 24, "horn", 0.72, -12)
    melody(song, "strings", mel_d, 24, "strings", 0.38, 12)
    bassline(song, "bass", D, 24, 0.7, pulse=0.5)
    ostinato(song, "spiccato", D[:7], 24, [0, None, 0, 0, 12, None, 0, 0, 7, None, 0, 0, 12, None, 7, None], 0.4, 50)
    crash(song, 24, 0.8)
    crash(song, 28, 0.6)
    for i in range(7):
        drums(song, 24 + i, {"big": "X.......X.......", "mid": "......x.......x." if i % 2 else "..............xx", "snare": "....o.......o..."})
        timp(song, 24 + i, 0, "G2" if D[i][0] in "GB" else "A2", 0.6)
    drums(song, 31, {"big": "X...............", "mid": "................"}, 0.8)
    roll(song, 31, 3, "A2", 0.5, 0.12)
    return song.render(0.32, 2.8, -14.5)


# ---------------------------------------------------------------- 2. battle (PvP)

def battle() -> np.ndarray:
    song = Song(140, 40, 202)
    standard_buses(song, "a")
    A = ["Dm", "Dm", "Bb", "C", "Dm", "Dm", "Bb", "A"]
    B = ["Dm", "Bb", "F", "C", "Dm", "Bb", "Gm", "A"]
    C = ["Bb", "C", "Dm", "Dm", "Bb", "C", "A", "A"]
    D = ["Gm", "Gm", "Dm", "Dm", "Bb", "C", "A", "A"]
    mel_b = "D4:1 A4:1 A4:1.5 G4:.5 | F4:1.5 G4:.5 F4:1 D4:1 | C5:1.5 A4:.5 F4:1 A4:1 | G4:3 E4:1 | D4:1 A4:1 D5:1.5 C5:.5 | D5:1 F5:1 D5:1 Bb4:1 | G4:1 Bb4:1 D5:2 | C#5:2 E5:1 A4:1"
    mel_c = "F5:1.5 D5:.5 Bb4:1 D5:1 | E5:1.5 C5:.5 G4:1 C5:1 | D5:1 F5:1 A5:2 | A5:1.5 G5:.5 F5:1 E5:1 | F5:1.5 D5:.5 Bb4:1 F5:1 | G5:1.5 E5:.5 C5:1 G5:1 | A5:2 G5:1 E5:1 | C#5:1 E5:1 A5:2"
    low = "G2:1.5 Bb2:.5 D3:2 | C3:1.5 Bb2:.5 A2:1 G2:1 | D3:1.5 F3:.5 A3:2 | G3:1.5 F3:.5 E3:1 D3:1"
    climb = "D4:2 F4:2 | E4:2 G4:2 | A4:2 C#5:2 | E5:4"
    groove = {"big": "X.....x.X.......", "mid": "....x.....x.x...", "snare": "....x.......x...", "shaker": "x.x.x.x.x.x.x.x."}
    fill = {"big": "X.....x.X.......", "mid": "........xxxxXXXX", "snare": "....x.......x..."}
    # A: galloping strings, taiko and brass stabs
    hit(song, 0, "D2", 0.7)
    crash(song, 0, 0.8)
    ostinato(song, "spiccato", A, 0, GALLOP, 0.6)
    bassline(song, "bass", A, 0, 0.6)
    pad(song, "strings", A, 0, 57, 3, 0.3, 0.4)
    for i in range(8):
        drums(song, i, {"big": "X.......X......."} if i < 4 else (fill if i == 7 else groove))
    stabs(song, A[4:], 4, [0.0, 1.5, 3.0], 0.75, 0.4)
    riser(song, 8, 2, 0.5)
    # B: horn theme
    crash(song, 8, 0.7)
    ostinato(song, "spiccato", B, 8, GALLOP, 0.52)
    bassline(song, "bass", B, 8, 0.7)
    pad(song, "strings", B, 8, 60, 4, 0.4, 0.2)
    pad(song, "choir", B, 8, 62, 3, 0.25, 0.4, "choir")
    melody(song, "brass", mel_b, 8, "horn", 0.85)
    for i in range(8):
        drums(song, 8 + i, fill if i == 7 else groove)
        timp(song, 8 + i, 0, "D2" if B[i] == "Dm" else ("A2" if B[i] in ("A", "F") else "G2"), 0.55)
    riser(song, 16, 2, 0.55)
    # C: trumpets up high with the choir
    crash(song, 16, 0.8)
    ostinato(song, "spiccato", C, 16, GALLOP, 0.55)
    arpeggio(song, "spiccato", C, 16, [0, 1, 2, 3, 2, 1, 2, 3], 0.5, 69, 0.3, "spiccato")
    bassline(song, "bass", C, 16, 0.75)
    pad(song, "strings", C, 16, 62, 4, 0.45, 0.15)
    pad(song, "choir", C, 16, 67, 4, 0.5, 0.2, "choir")
    melody(song, "lead", mel_c, 16, "trumpet", 0.88)
    melody(song, "brass", mel_c, 16, "horn", 0.62, -12)
    stabs(song, C, 16, [0.0], 0.6, 0.5)
    for i in range(8):
        drums(song, 16 + i, fill if i == 7 else groove)
    # D: breakdown on a low drone, then the climb back
    pad(song, "strings", ["Dm"] * 4, 24, 50, 3, 0.35, 0.6)
    song.put("bass", bass(note("D2"), 4 * 4 * song.beat, 0.7, 500, 0.5, song.rng), song.time(24), human=0.0)
    melody(song, "brass", low, 24, "trombone", 0.8)
    for i in range(4):
        drums(song, 24 + i, {"big": "X.......x.......", "snare": "........X......."})
    ostinato(song, "spiccato", D[4:], 28, GALLOP, 0.5)
    bassline(song, "bass", D[4:], 28, 0.7)
    pad(song, "strings", D[4:], 28, 60, 4, 0.45, 0.3)
    melody(song, "brass", climb, 28, "horn", 0.8)
    for i in range(4):
        drums(song, 28 + i, {"big": "X.......X.......", "mid": "x.x.x.x.x.x.x.x." if i < 3 else "xxxxxxxxXXXXXXXX"}, 0.6 + 0.12 * i)
    snare_roll(song, 30, 8, 0.1, 0.85)
    riser(song, 32, 4, 0.6)
    # E: the horn theme again, trumpets an octave up, everyone in
    crash(song, 32, 0.9)
    hit(song, 32, "D2", 0.5)
    ostinato(song, "spiccato", B, 32, GALLOP, 0.58)
    arpeggio(song, "spiccato", B, 32, [0, 1, 2, 3, 2, 1, 2, 3], 0.5, 69, 0.28, "spiccato")
    bassline(song, "bass", B, 32, 0.75)
    pad(song, "strings", B, 32, 62, 4, 0.5, 0.15)
    pad(song, "choir", B, 32, 67, 4, 0.55, 0.2, "choir")
    melody(song, "lead", mel_b, 32, "trumpet", 0.9, 12)
    melody(song, "brass", mel_b, 32, "horn", 0.8)
    melody(song, "strings", mel_b, 32, "strings", 0.35, 12)
    for i in range(8):
        drums(song, 32 + i, fill if i == 7 else groove)
        timp(song, 32 + i, 0, "D2" if B[i] == "Dm" else ("A2" if B[i] in ("A", "F") else "G2"), 0.6)
    riser(song, 40, 2, 0.5)
    return song.render(0.24, 2.2, -13.5)


# ---------------------------------------------------------------- 3. instance (Templo do Sol)

OUD = {
    "Am": "A3 E4 A4 E4 C5 B4 A4 E4",
    "F": "F3 C4 F4 C4 A4 G#4 F4 C4",
    "E": "E3 B3 E4 F4 G#4 F4 E4 B3",
    "Dm": "D3 A3 D4 A3 F4 E4 D4 A3",
    "Bb": "Bb2 F3 Bb3 F3 D4 C4 Bb3 F3",
    "G": "G3 D4 G4 D4 B4 A4 G4 D4",
}


def instance() -> np.ndarray:
    song = Song(104, 32, 303)
    standard_buses(song, "o")
    song.bus("oud", 0.6, 0.3, lambda x: peak_eq(hp(x, 120), 1400, 3.0, 1.2))
    song.bus("chant", 2.6, 0.5, lambda x: lp(hp(formant(x, "a"), 110), 6500))
    A = ["Am", "Am", "F", "E", "Am", "Am", "Dm", "E"]
    B = ["Am", "F", "Dm", "E", "Am", "F", "Dm", "E"]
    C = ["Am", "Bb", "Am", "Bb", "F", "G", "E", "E"]
    mel_a = "A3:3 B3:.5 C4:.5 | E4:2 D4:1 C4:1 | D4:1.5 E4:.5 F4:1 A4:1 | G#4:2 F4:1 E4:1"
    mel_b = "E4:1 A4:1 B4:1 C5:1 | C5:1.5 B4:.5 A4:1 F4:1 | F4:1 A4:1 D5:1.5 C5:.5 | B4:1 G#4:1 E4:2 | E4:1 A4:1 B4:1 C5:1 | C5:1 F5:1.5 E5:.5 D5:1 | D5:1.5 C5:.5 B4:1 A4:1 | G#4:1.5 A4:.5 B4:2"
    mel_c = "A4:2 C5:1 E5:1 | F5:2 D5:1 Bb4:1 | E5:2 C5:1 A4:1 | D5:1 F5:1 F5:2 | C5:1 F5:1 A5:2 | B4:1 D5:1 G5:2 | G#5:2 F5:1 E5:1 | E5:2 B4:2"
    heavy = {"big": "X.........x.....", "mid": "....x.......x.xx", "frame": "........X......."}
    # A: the temple wakes: oud figure over a low drone, distant chant
    figure(song, "oud", {i: OUD[ch] for i, ch in enumerate(A)}, 0, "oud", 0.55)
    song.put("bass", bass(note("A1"), 8 * 4 * song.beat, 0.5, 400, 1.0, song.rng), 0.0, human=0.0)
    song.put("bass", bass(note("E2"), 8 * 4 * song.beat, 0.35, 400, 1.0, song.rng), 0.0, human=0.0)
    pad(song, "choir", A, 0, 57, 3, 0.3, 0.8, "choir")
    melody(song, "brass", mel_a, 4, "horn", 0.55)
    for i in range(8):
        drums(song, i, {"big": "X...............", "frame": "x..o..x.o..o..x." if i >= 2 else "................"}, 0.75)
    for bar, name in [(0, "E6"), (2, "C6"), (4, "E6"), (6, "F6")]:
        melody(song, "bells", f"{name}:4", bar, "bells", 0.3)
    roll(song, 7, 2, "E2", 0.15, 0.7, 2)
    riser(song, 8, 2, 0.5)
    # B: the march of the Sun King
    crash(song, 8, 0.7)
    figure(song, "oud", {i: OUD[ch] for i, ch in enumerate(B)}, 8, "oud", 0.38)
    ostinato(song, "spiccato", B, 8, [0, None, 0, None, 12, None, 0, None, 7, None, 0, None, 12, None, 7, None], 0.5, 45)
    bassline(song, "bass", B, 8, 0.7)
    pad(song, "strings", B, 8, 60, 4, 0.42, 0.25)
    pad(song, "choir", B, 8, 57, 3, 0.35, 0.4, "choir")
    melody(song, "brass", mel_b, 8, "horn", 0.85)
    for i in range(8):
        drums(song, 8 + i, heavy)
        timp(song, 8 + i, 0, "A2" if B[i] in ("Am", "F") else ("D2" if B[i] == "Dm" else "E2"), 0.6)
    riser(song, 16, 2, 0.55)
    # C: the fury: Neapolitan Bb, brass stabs, the chant takes the melody
    crash(song, 16, 0.85)
    hit(song, 16, "A1", 0.45)
    bassline(song, "bass", C, 16, 0.8)
    pad(song, "strings", C, 16, 62, 4, 0.48, 0.15)
    melody(song, "lead", mel_c, 16, "trumpet", 0.85)
    melody(song, "chant", mel_c, 16, "choir", 0.6, -12)
    stabs(song, C, 16, [0.0, 2.5], 0.8, 0.6, 52)
    ostinato(song, "spiccato", C, 16, GALLOP, 0.5, 45)
    for i in range(8):
        drums(song, 16 + i, {"big": "X...X...X...X...", "mid": "..x...x...x...xx", "snare": "....x.......x..."} if i < 7 else {"big": "X...X...X.......", "mid": "........xxxxXXXX"})
    roll(song, 22, 4, "E2", 0.3, 0.9)
    riser(song, 24, 4, 0.6)
    # D: climax, then the E chord rings out into the temple again
    crash(song, 24, 0.9)
    figure(song, "oud", {i: OUD[ch] for i, ch in enumerate(B)}, 24, "oud", 0.32)
    ostinato(song, "spiccato", B[:7], 24, GALLOP, 0.55, 45)
    bassline(song, "bass", B, 24, 0.8)
    pad(song, "strings", B, 24, 62, 4, 0.5, 0.15)
    pad(song, "choir", B, 24, 64, 4, 0.5, 0.2, "choir")
    melody(song, "lead", mel_b, 24, "trumpet", 0.9, 12)
    melody(song, "brass", mel_b, 24, "horn", 0.82)
    melody(song, "chant", mel_b, 24, "choir", 0.45)
    melody(song, "strings", mel_b, 24, "strings", 0.35, 12)
    crash(song, 28, 0.6)
    for i in range(7):
        drums(song, 24 + i, heavy)
        timp(song, 24 + i, 0, "A2" if B[i] in ("Am", "F") else ("D2" if B[i] == "Dm" else "E2"), 0.65)
    drums(song, 31, {"big": "X...............", "frame": "x..............."}, 0.8)
    roll(song, 31, 3, "E2", 0.5, 0.12, 1)
    return song.render(0.34, 3.0, -14.0)


TRACKS = {"lobby": lobby, "battle": battle, "instance": instance}

if __name__ == "__main__":
    for name in sys.argv[1:] or list(TRACKS):
        print(name)
        audio = TRACKS[name]()
        write_ogg(str(OUT / f"{name}.ogg"), audio, 5)
        print(f"  {audio.shape[1] / SR:.1f}s  peak {peak_db(audio):.1f} dB  rms {rms_db(audio):.1f} dB")
