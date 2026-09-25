"""Small numpy synthesizer behind every Frontier Tank sound.

The effects (tools/make_sfx.py) and the three music loops (tools/make_music.py) are
generated from code, so the audio is original and can be rebuilt or tweaked:

    python tools/make_sfx.py      -> assets/audio/sfx/*.ogg
    python tools/make_music.py    -> assets/audio/music/*.ogg

Needs numpy, scipy and an ffmpeg with libvorbis on the PATH.
Signals are float arrays: mono (n,) or stereo (2, n), at 44.1 kHz.
"""
from __future__ import annotations

import math
import os
import subprocess
import tempfile

import numpy as np
from scipy import signal
from scipy.io import wavfile
from scipy.ndimage import maximum_filter1d

SR = 44100
RNG = np.random.default_rng(1337)


# ---------------------------------------------------------------- basics

def samples(seconds: float) -> int:
    return max(0, int(round(seconds * SR)))


def timeline(n: int) -> np.ndarray:
    return np.arange(n) / SR


def hz(midi: float) -> float:
    return 440.0 * 2.0 ** ((midi - 69.0) / 12.0)


_LETTERS = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def note(name: str) -> int:
    """'C4' -> 60, 'F#3', 'Bb5'."""
    letter, rest, shift = name[0].upper(), name[1:], 0
    while rest and rest[0] in "#b":
        shift += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    return 12 * (int(rest) + 1) + _LETTERS[letter] + shift


def cents(value: float) -> float:
    return 2.0 ** (value / 1200.0)


def db(value: float) -> float:
    return 10.0 ** (value / 20.0)


# ---------------------------------------------------------------- oscillators

def _phase(freq, n: int) -> tuple[np.ndarray, np.ndarray]:
    inc = np.broadcast_to(np.asarray(freq, dtype=float), (n,)) / SR
    return np.cumsum(inc), np.array(inc)


def _blep(p: np.ndarray, dt: np.ndarray) -> np.ndarray:
    out = np.zeros_like(p)
    m = p < dt
    x = p[m] / dt[m]
    out[m] = x + x - x * x - 1.0
    m = p > 1.0 - dt
    x = (p[m] - 1.0) / dt[m]
    out[m] = x * x + x + x + 1.0
    return out


def sine(freq, n: int, phase: float = 0.0) -> np.ndarray:
    ph, _ = _phase(freq, n)
    return np.sin(2.0 * np.pi * (ph + phase))


def saw(freq, n: int, phase: float = 0.0) -> np.ndarray:
    """Band-limited sawtooth (PolyBLEP)."""
    ph, inc = _phase(freq, n)
    p = (ph + phase) % 1.0
    return 2.0 * p - 1.0 - _blep(p, inc)


def square(freq, n: int, width: float = 0.5, phase: float = 0.0) -> np.ndarray:
    ph, inc = _phase(freq, n)
    p1 = (ph + phase) % 1.0
    p2 = (ph + phase + width) % 1.0
    return (2.0 * p1 - _blep(p1, inc)) - (2.0 * p2 - _blep(p2, inc))


def triangle(freq, n: int, phase: float = 0.0) -> np.ndarray:
    ph, _ = _phase(freq, n)
    p = (ph + phase) % 1.0
    return 4.0 * np.abs(p - 0.5) - 1.0


def white(n: int, rng=RNG) -> np.ndarray:
    return rng.uniform(-1.0, 1.0, n)


def pink(n: int, rng=RNG) -> np.ndarray:
    b = [0.049922035, -0.095993537, 0.050612699, -0.004408786]
    a = [1.0, -2.494956002, 2.017265875, -0.522189400]
    y = signal.lfilter(b, a, rng.standard_normal(n))
    return y / (np.max(np.abs(y)) + 1e-9)


def glide(f0: float, f1: float, n: int, curve: float = 1.0) -> np.ndarray:
    """Exponential frequency glide from f0 to f1 (curve > 1 moves early)."""
    x = np.linspace(0.0, 1.0, n) ** (1.0 / curve)
    return f0 * (f1 / f0) ** x


# ---------------------------------------------------------------- envelopes

def env_exp(n: int, tau: float) -> np.ndarray:
    return np.exp(-timeline(n) / tau)


def env_ar(n: int, attack: float, tau: float) -> np.ndarray:
    e = env_exp(n, tau)
    a = min(n, samples(attack))
    if a > 0:
        e[:a] = np.sin(np.linspace(0.0, np.pi / 2, a)) ** 2
        e[a:] = np.exp(-timeline(n - a) / tau)
    return e


def adsr(n: int, attack: float, decay: float, sustain: float, release: float, gate: float) -> np.ndarray:
    """Attack/decay to sustain while the gate is held, then an exponential release."""
    tt = timeline(n)
    e = np.where(tt < attack, np.sin(np.clip(tt / max(attack, 1e-4), 0, 1) * np.pi / 2) ** 2,
                 sustain + (1.0 - sustain) * np.exp(-(tt - attack) / max(decay, 1e-4)))
    held = min(gate, tt[-1] if n else 0.0)
    level = e[min(n - 1, samples(held))] if n else 0.0
    after = tt > held
    e[after] = level * np.exp(-(tt[after] - held) / max(release, 1e-4) * 3.0)
    return e


def shape(n: int, points: list[tuple[float, float]]) -> np.ndarray:
    """Piecewise-linear curve through (seconds, value) points."""
    xs, ys = zip(*points)
    return np.interp(timeline(n), xs, ys)


def fades(x: np.ndarray, fade_in: float = 0.002, fade_out: float = 0.02) -> np.ndarray:
    x = np.array(x, dtype=float)
    n = x.shape[-1]
    a, b = min(n, samples(fade_in)), min(n, samples(fade_out))
    if a:
        x[..., :a] *= np.linspace(0, 1, a)
    if b:
        x[..., n - b:] *= np.linspace(1, 0, b)
    return x


# ---------------------------------------------------------------- filters

def _sos(kind: str, freq, order: int = 2):
    nyq = SR * 0.49
    if isinstance(freq, (tuple, list)):
        freq = [min(max(f, 10.0), nyq) for f in freq]
    else:
        freq = min(max(freq, 10.0), nyq)
    return signal.butter(order, freq, kind, fs=SR, output="sos")


def lp(x, freq: float, order: int = 2):
    return signal.sosfilt(_sos("lowpass", freq, order), x, axis=-1)


def hp(x, freq: float, order: int = 2):
    return signal.sosfilt(_sos("highpass", freq, order), x, axis=-1)


def bp(x, low: float, high: float, order: int = 2):
    return signal.sosfilt(_sos("bandpass", (low, high), order), x, axis=-1)


def resonator(x, freq: float, q: float):
    b, a = signal.iirpeak(min(freq, SR * 0.45), q, fs=SR)
    return signal.lfilter(b, a, x, axis=-1)


def peak_eq(x, freq: float, gain_db: float, q: float = 1.0):
    """Peaking EQ (RBJ cookbook)."""
    amp = 10 ** (gain_db / 40)
    w0 = 2 * np.pi * freq / SR
    alpha = np.sin(w0) / (2 * q)
    b = [1 + alpha * amp, -2 * np.cos(w0), 1 - alpha * amp]
    a = [1 + alpha / amp, -2 * np.cos(w0), 1 - alpha / amp]
    return signal.lfilter(np.array(b) / a[0], np.array(a) / a[0], x, axis=-1)


def sweep(x: np.ndarray, kind: str, start: float, end: float, width: float = 0.6,
          curve: float = 1.0, block: int = 256, order: int = 2, path: np.ndarray | None = None) -> np.ndarray:
    """Time-varying Butterworth filter, block by block with carried state.
    `kind` is lowpass/highpass/bandpass; `width` is the band as a fraction of the centre.
    `path` (one value per sample) overrides the start/end glide."""
    n = x.shape[-1]
    if path is None:
        path = glide(start, end, n, curve)
    out = np.zeros_like(x, dtype=float)
    zi = None
    for i in range(0, n, block):
        fc = float(path[min(n - 1, i + block // 2)])
        if kind == "bandpass":
            sos = _sos("bandpass", (fc * (1 - width / 2), fc * (1 + width / 2)), order)
        else:
            sos = _sos(kind, fc, order)
        if zi is None or zi.shape[0] != sos.shape[0]:
            zi = np.zeros((sos.shape[0], 2))
        out[i:i + block], zi = signal.sosfilt(sos, x[i:i + block], zi=zi)
    return out


def formant(x, vowel: str = "a", dry: float = 0.15):
    """Parallel vowel resonators for choir voices."""
    table = {
        "a": [(800, 8, 1.0), (1150, 10, 0.55), (2900, 18, 0.22), (3900, 20, 0.1)],
        "o": [(450, 7, 1.0), (800, 9, 0.6), (2830, 18, 0.12)],
        "u": [(325, 6, 1.0), (700, 8, 0.35), (2530, 16, 0.08)],
        "e": [(400, 7, 1.0), (1600, 12, 0.45), (2700, 16, 0.25)],
    }
    out = lp(x, 5000) * dry
    for freq, q, gain in table[vowel]:
        out = out + resonator(x, freq, q) * gain
    return out


def drive(x, amount: float = 2.0):
    return np.tanh(x * amount) / np.tanh(amount)


def bitcrush(x, bits: int = 6):
    step = 2.0 / (2 ** bits)
    return np.round(x / step) * step


# ---------------------------------------------------------------- stereo, mixing

def stereo(x: np.ndarray, pan: float = 0.0) -> np.ndarray:
    """Constant-power pan of a mono signal; stereo input passes through (balanced)."""
    if x.ndim == 2:
        if pan == 0.0:
            return x
        angle = (pan + 1) * np.pi / 4
        return np.stack([x[0] * np.cos(angle) * 1.4142, x[1] * np.sin(angle) * 1.4142])
    angle = (pan + 1) * np.pi / 4
    return np.stack([x * np.cos(angle), x * np.sin(angle)]) * 1.4142


def mono(x: np.ndarray) -> np.ndarray:
    return x.mean(axis=0) if x.ndim == 2 else x


def canvas(seconds: float, channels: int = 1) -> np.ndarray:
    n = samples(seconds)
    return np.zeros(n) if channels == 1 else np.zeros((2, n))


def place(buffer: np.ndarray, x: np.ndarray, at: float, gain: float = 1.0) -> np.ndarray:
    """Add x into buffer at `at` seconds (mono into stereo is centred)."""
    i = samples(at)
    if buffer.ndim == 2 and x.ndim == 1:
        x = np.stack([x, x])
    if buffer.ndim == 1 and x.ndim == 2:
        x = x.mean(axis=0)
    m = min(x.shape[-1], buffer.shape[-1] - i)
    if m > 0:
        buffer[..., i:i + m] += x[..., :m] * gain
    return buffer


def rms_db(x) -> float:
    return 20 * math.log10(float(np.sqrt(np.mean(np.square(x)))) + 1e-12)


def peak_db(x) -> float:
    return 20 * math.log10(float(np.max(np.abs(x))) + 1e-12)


def haas(x: np.ndarray, ms: float = 12.0, pan: float = 0.0) -> np.ndarray:
    """Cheap width: the right channel slightly delayed."""
    d = samples(ms / 1000)
    right = np.concatenate([np.zeros(d), x[:-d]]) if d else x
    return stereo(np.stack([x, right]), pan)


# ---------------------------------------------------------------- space

_IR_CACHE: dict = {}


def reverb_ir(seconds: float = 2.2, damping: float = 0.45, predelay: float = 0.015, seed: int = 3,
              brightness: float = 2400.0) -> np.ndarray:
    key = (seconds, damping, predelay, seed, brightness)
    if key in _IR_CACHE:
        return _IR_CACHE[key]
    rng = np.random.default_rng(seed)
    n = samples(seconds)
    tt = timeline(n)
    channels = []
    for _ in range(2):
        noise = rng.standard_normal(n)
        low = lp(noise, brightness, 2)
        high = noise - low
        ir = low * np.exp(-6.9 * tt / seconds) + high * np.exp(-6.9 * tt / (seconds * damping)) * 0.7
        ir *= np.minimum(1.0, tt / 0.01)
        for _ in range(10):
            pos = int(rng.integers(samples(0.004), samples(0.08)))
            ir[pos] += rng.uniform(-1, 1) * 6.0 * math.exp(-pos / SR / 0.05)
        channels.append(np.concatenate([np.zeros(samples(predelay)), ir]))
    ir = np.stack(channels)
    ir /= np.sqrt(np.sum(ir ** 2, axis=1, keepdims=True))
    _IR_CACHE[key] = ir
    return ir


def reverb(x: np.ndarray, wet: float = 0.25, seconds: float = 1.6, damping: float = 0.45,
           predelay: float = 0.012, keep_length: bool = False, dry: bool = True) -> np.ndarray:
    """Stereo convolution reverb; returns dry + wet (longer than x unless keep_length)."""
    ir = reverb_ir(seconds, damping, predelay)
    source = stereo(x) if x.ndim == 1 else x
    tail = [signal.fftconvolve(source[c], ir[c]) for c in range(2)]
    out = np.stack(tail) * wet
    if dry:
        out[:, :source.shape[1]] += source
    return out[:, :source.shape[1]] if keep_length else out


def trim_silence(x: np.ndarray, threshold_db: float = -60.0, pad: float = 0.02) -> np.ndarray:
    level = np.abs(mono(x))
    loud = np.nonzero(level > db(threshold_db) * (np.max(level) + 1e-12))[0]
    if loud.size == 0:
        return x
    end = min(level.size, loud[-1] + samples(pad))
    return x[..., :end]


def limiter(x: np.ndarray, ceiling_db: float = -1.0, release: float = 0.08, lookahead: float = 0.004) -> np.ndarray:
    """Look-ahead peak limiter with a smooth release, then a soft safety clip."""
    ceiling = db(ceiling_db)
    level = np.max(np.abs(x), axis=0) if x.ndim == 2 else np.abs(x)
    env = maximum_filter1d(level, size=max(1, samples(lookahead) * 2 + 1))
    gain = np.minimum(1.0, ceiling / np.maximum(env, 1e-9))
    # Smooth: instant attack (already looked ahead), exponential release.
    coeff = math.exp(-1.0 / (release * SR))
    smoothed = signal.lfilter([1 - coeff], [1, -coeff], gain - 1.0) + 1.0
    gain = np.minimum(gain, smoothed)
    gain = -maximum_filter1d(-gain, size=max(1, samples(lookahead) * 2 + 1))
    y = x * gain
    return np.tanh(y / ceiling * 0.9) / np.tanh(0.9) * ceiling if np.max(np.abs(y)) > ceiling else y


def normalize(x: np.ndarray, rms_target: float | None = None, peak: float = -1.0) -> np.ndarray:
    """Scale to an RMS target (dBFS) if given, keep peaks under `peak` dBFS."""
    y = np.array(x, dtype=float)
    y -= np.mean(y, axis=-1, keepdims=True)
    if rms_target is not None:
        y *= db(rms_target - rms_db(y))
    else:
        y *= db(peak - peak_db(y))
    if peak_db(y) > peak:
        y = limiter(y, peak)
    return y


# ---------------------------------------------------------------- output

def decode(path: str) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32)


def write_ogg(path: str, x: np.ndarray, quality: float = 5.0, ceiling_db: float = -0.8) -> None:
    """Encode to Ogg Vorbis. Vorbis overshoots sharp transients by a few dB, so the
    file is decoded again and re-encoded quieter until its peaks stay under the ceiling."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = np.array(x, dtype=float)
    for _ in range(4):
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as handle:
            temp = handle.name
        try:
            clipped = np.clip(data, -1.0, 1.0)
            wavfile.write(temp, SR, ((clipped.T if clipped.ndim == 2 else clipped) * 32767.0).astype(np.int16))
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", temp, "-c:a", "libvorbis",
                            "-q:a", str(quality), path], check=True)
        finally:
            os.remove(temp)
        over = peak_db(decode(path)) - ceiling_db
        if over <= 0:
            return
        data = data * db(-over - 0.2)


def write_wav(path: str, x: np.ndarray) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = np.clip(x, -1.0, 1.0)
    wavfile.write(path, SR, ((data.T if data.ndim == 2 else data) * 32767.0).astype(np.int16))


# ---------------------------------------------------------------- orchestra

def _vibrato(n: int, rate: float, depth_cents: float, delay: float, rng) -> np.ndarray:
    tt = timeline(n)
    ramp = np.clip((tt - delay) / 0.4, 0.0, 1.0)
    wobble = np.sin(2 * np.pi * (rate + rng.uniform(-0.3, 0.3)) * tt + rng.uniform(0, 6.28))
    return 2.0 ** (wobble * ramp * depth_cents / 1200.0)


def strings(midi: float, dur: float, vel: float = 0.8, attack: float = 0.22, release: float = 0.45,
            voices: int = 6, spread: float = 0.7, rng=RNG) -> np.ndarray:
    """Legato string section (detuned saws with vibrato); filter on the bus."""
    n = samples(dur + release)
    f0 = hz(midi)
    out = np.zeros((2, n))
    for v in range(voices):
        side = (v / max(1, voices - 1)) * 2 - 1
        detune = cents(side * 9 + rng.uniform(-3, 3))
        freq = f0 * detune * _vibrato(n, 5.2, 11, 0.15, rng)
        out += stereo(saw(freq, n, rng.uniform(0, 1)), side * spread)
    env = adsr(n, attack, 0.3, 0.9, release, dur)
    return out * env * vel / math.sqrt(voices)


def spiccato(midi: float, vel: float = 0.8, length: float = 0.16, voices: int = 3, rng=RNG) -> np.ndarray:
    """Short bowed strings for ostinatos."""
    n = samples(length + 0.12)
    f0 = hz(midi)
    out = np.zeros((2, n))
    for v in range(voices):
        side = (v / max(1, voices - 1)) * 2 - 1
        out += stereo(saw(f0 * cents(side * 7 + rng.uniform(-2, 2)), n, rng.uniform(0, 1)), side * 0.5)
    tt = timeline(n)
    env = np.minimum(1.0, tt / 0.006) * np.exp(-tt / (length * 0.55))
    bow = lp(white(n, rng), 3000) * np.exp(-tt / 0.02) * 0.3
    return (out / math.sqrt(voices) + stereo(bow)) * env * vel


BRASS = {
    # dark cutoff, bright cutoff, voices, attack, detune cents, drive
    "horn": (420.0, 1700.0, 3, 0.07, 5.0, 1.2),
    "trumpet": (900.0, 4600.0, 2, 0.035, 4.0, 1.6),
    "trombone": (330.0, 2300.0, 3, 0.05, 6.0, 1.8),
    "tuba": (200.0, 900.0, 2, 0.06, 4.0, 1.4),
}


def brass(midi: float, dur: float, vel: float = 0.8, kind: str = "horn", release: float = 0.22, rng=RNG) -> np.ndarray:
    dark_fc, bright_fc, voices, attack, spread, amount = BRASS[kind]
    n = samples(dur + release)
    tt = timeline(n)
    f0 = hz(midi)
    scoop = 2.0 ** (-38 * np.exp(-tt / 0.035) / 1200.0)
    out = np.zeros((2, n))
    for v in range(voices):
        side = (v / max(1, voices - 1)) * 2 - 1 if voices > 1 else 0.0
        freq = f0 * scoop * cents(side * spread + rng.uniform(-2, 2)) * _vibrato(n, 5.0, 7, 0.35, rng)
        out += stereo(saw(freq, n, rng.uniform(0, 1)), side * 0.35)
    out /= math.sqrt(voices)
    rise = np.clip(tt / attack, 0, 1)
    bright = np.clip(vel * (0.45 + 0.75 * np.exp(-tt / 0.28)) * rise, 0, 1)
    dark = lp(out, dark_fc)
    shine = lp(out, bright_fc * (0.6 + 0.6 * vel))
    tone = dark * (1 - bright) + shine * bright
    env = adsr(n, attack, 0.25, 0.82, release, dur)
    return drive(tone * env * (0.6 + 0.6 * vel), amount) * vel


def choir_voice(midi: float, dur: float, vel: float = 0.7, attack: float = 0.35, release: float = 0.7,
                voices: int = 5, rng=RNG) -> np.ndarray:
    """Raw choir source; put it on a bus that runs `formant`."""
    n = samples(dur + release)
    f0 = hz(midi)
    out = np.zeros((2, n))
    for v in range(voices):
        side = (v / max(1, voices - 1)) * 2 - 1
        freq = f0 * cents(side * 14 + rng.uniform(-4, 4)) * _vibrato(n, 5.6, 22, 0.2, rng)
        tone = saw(freq, n, rng.uniform(0, 1)) * 0.8 + triangle(freq, n) * 0.4
        out += stereo(tone, side * 0.8)
    breath = hp(white(n, rng), 1500) * 0.06
    env = adsr(n, attack, 0.4, 0.9, release, dur)
    return (out / math.sqrt(voices) + stereo(breath)) * env * vel


def pluck(midi: float, dur: float = 1.6, vel: float = 0.8, brightness: float = 1.0,
          harmonics: int = 18, nasal: bool = False, rng=RNG) -> np.ndarray:
    """Harp-like plucked string (additive, upper partials die first)."""
    n = samples(dur)
    tt = timeline(n)
    f0 = hz(midi)
    out = np.zeros(n)
    for h in range(1, harmonics + 1):
        f = f0 * h * (1 + 0.0004 * h * h)
        if f > SR * 0.45:
            break
        amp = (1.0 / h ** (1.3 / brightness))
        if nasal:
            amp *= 1.0 + 1.6 * math.exp(-((f - 1400) / 700) ** 2)
        tau = dur * 0.45 / (1 + 0.35 * (h - 1) / brightness)
        out += amp * np.sin(2 * np.pi * f * tt + rng.uniform(0, 6.28)) * np.exp(-tt / tau)
    click = hp(white(n, rng), 2500) * np.exp(-tt / 0.004) * 0.25 * brightness
    out = (out + click) * np.minimum(1.0, tt / 0.0015)
    return out * vel / 2.2


def bell(freq: float, dur: float = 2.0, vel: float = 0.7, ratios=(1.0, 2.76, 5.40, 8.93),
         amps=(1.0, 0.45, 0.22, 0.1), decays=(1.0, 0.45, 0.22, 0.12)) -> np.ndarray:
    n = samples(dur)
    tt = timeline(n)
    out = np.zeros(n)
    for r, a, d in zip(ratios, amps, decays):
        if freq * r < SR * 0.45:
            out += a * np.sin(2 * np.pi * freq * r * tt) * np.exp(-tt / (d * dur * 0.5))
    return out * np.minimum(1.0, tt / 0.001) * vel * 0.6


def timpani(midi: float, vel: float = 0.8, dur: float = 2.2, rng=RNG) -> np.ndarray:
    n = samples(dur)
    tt = timeline(n)
    f0 = hz(midi)
    bend = 1 + 0.06 * np.exp(-tt / 0.04)
    out = np.zeros(n)
    for ratio, amp, tau in [(1.0, 1.0, 0.9), (1.5, 0.5, 0.55), (1.98, 0.35, 0.4), (2.44, 0.2, 0.3), (2.9, 0.12, 0.2)]:
        out += amp * sine(f0 * ratio * bend, n) * np.exp(-tt / (tau * dur / 2.2))
    mallet = lp(white(n, rng), 1200) * np.exp(-tt / 0.012) * 0.8
    return drive((out + mallet) * vel, 1.3) * 0.8


def taiko(vel: float = 0.9, size: float = 1.0, dur: float = 1.4, rng=RNG) -> np.ndarray:
    """Big drum: pitched body with a fast pitch drop and a skin slap."""
    n = samples(dur)
    tt = timeline(n)
    f = (46 + 70 * np.exp(-tt / 0.05)) / size
    body = sine(f, n) * np.exp(-tt / (0.45 * size))
    over = sine(f * 2.3, n) * np.exp(-tt / 0.08) * 0.3
    slap = bp(white(n, rng), 300, 2200) * np.exp(-tt / 0.018) * 0.9
    room = lp(white(n, rng), 400) * np.exp(-tt / 0.2) * 0.25
    return drive((body + over + slap + room) * vel, 1.6) * 0.9


def snare(vel: float = 0.7, dur: float = 0.45, tone: float = 190.0, rng=RNG) -> np.ndarray:
    n = samples(dur)
    tt = timeline(n)
    wires = bp(white(n, rng), 1800, 8000) * np.exp(-tt / 0.11)
    head = sine(tone * (1 + 0.3 * np.exp(-tt / 0.01)), n) * np.exp(-tt / 0.05)
    return (wires * 0.8 + head * 0.7) * vel


def frame_drum(vel: float = 0.7, dur: float = 0.5, rng=RNG) -> np.ndarray:
    n = samples(dur)
    tt = timeline(n)
    body = sine(150 * (1 + 0.5 * np.exp(-tt / 0.01)), n) * np.exp(-tt / 0.12)
    skin = bp(white(n, rng), 500, 3500) * np.exp(-tt / 0.03)
    return (body * 0.8 + skin * 0.6) * vel


def cymbal(vel: float = 0.7, dur: float = 3.0, rng=RNG) -> np.ndarray:
    n = samples(dur)
    tt = timeline(n)
    metal = sum(square(f, n, 0.5, rng.uniform(0, 1)) for f in (205.3, 304.4, 369.6, 522.7, 540.0, 800.0))
    wash = hp(white(n, rng), 5000) * 1.2 + hp(metal, 4000) * 0.35
    env = np.minimum(1.0, tt / 0.003) * (0.55 * np.exp(-tt / 0.08) + 0.45 * np.exp(-tt / (dur * 0.35)))
    return stereo(lp(wash, 12000) * env * vel, 0.0) * np.array([[1.0], [0.92]])


def swell(dur: float = 2.0, vel: float = 0.6, rng=RNG) -> np.ndarray:
    """Reverse-cymbal riser that stops dead on the downbeat."""
    n = samples(dur)
    tt = timeline(n)
    ramp = (tt / dur) ** 3
    noise = sweep(white(n, rng), "highpass", 1500, 6000, curve=0.7)
    return stereo(noise * ramp * vel, 0.0) * np.array([[1.0], [0.9]])


def bass(midi: float, dur: float, vel: float = 0.8, cutoff: float = 700.0, release: float = 0.3, rng=RNG) -> np.ndarray:
    """Cellos and basses in octaves."""
    n = samples(dur + release)
    f0 = hz(midi)
    tone = saw(f0 * cents(-4), n, rng.uniform(0, 1)) + saw(f0 * cents(4), n, rng.uniform(0, 1)) + 0.5 * saw(f0 * 2, n)
    env = adsr(n, 0.05, 0.3, 0.85, release, dur)
    return stereo(lp(tone, cutoff) * env * vel * 0.6)


def braam(root: int, dur: float = 2.8, vel: float = 1.0, rng=RNG) -> np.ndarray:
    """Epic low brass cluster (root, fifth, octaves), very bright and driven."""
    out = np.zeros((2, samples(dur + 0.4)))
    for offset, gain in [(-12, 0.9), (0, 1.0), (7, 0.7), (12, 0.6)]:
        tone = brass(root + offset, dur, vel, "trombone", 0.4, rng)
        out[:, :tone.shape[1]] += tone * gain
    return drive(out * 0.8, 2.2)


# ---------------------------------------------------------------- harmony helpers

_QUALITIES = {"": [0, 4, 7], "m": [0, 3, 7], "dim": [0, 3, 6], "aug": [0, 4, 8], "sus4": [0, 5, 7],
              "sus2": [0, 2, 7], "7": [0, 4, 7, 10], "m7": [0, 3, 7, 10], "maj7": [0, 4, 7, 11], "5": [0, 7]}


def chord(name: str) -> tuple[int, list[int], int]:
    """'F#m' -> (root pc, pitch classes, bass pc). Slash chords set the bass ('A/C#')."""
    body, _, slash = name.partition("/")
    i = 1
    while i < len(body) and body[i] in "#b":
        i += 1
    root = note(body[:i] + "4") % 12
    quality = _QUALITIES[body[i:]]
    pcs = [(root + q) % 12 for q in quality]
    bass_pc = note(slash + "4") % 12 if slash else root
    return root, pcs, bass_pc


def voicing(name: str, center: int, count: int = 4, previous: list[int] | None = None) -> list[int]:
    """Closest stacked voicing of `count` chord tones around `center` (smooth voice leading)."""
    _, pcs, _ = chord(name)
    best, best_score = None, 1e9
    for start in range(center - 8, center + 6):
        if start % 12 not in pcs:
            continue
        notes = [start]
        m = start
        while len(notes) < count:
            m += 1
            if m % 12 in pcs:
                notes.append(m)
        if previous:
            score = sum(abs(a - b) for a, b in zip(notes, previous))
        else:
            score = abs(sum(notes) / len(notes) - center)
        if score < best_score:
            best, best_score = notes, score
    return best


def bass_note(name: str, octave: int = 2) -> int:
    _, _, bass_pc = chord(name)
    return 12 * (octave + 1) + bass_pc


def parse_line(text: str, beats_per_bar: float = 4.0) -> list[tuple[int | None, float, float]]:
    """'D4:1.5 A4:.5 r:2 | ...' -> [(midi or None, start beat, length)]; bars are checked."""
    events, beat = [], 0.0
    for b, bar in enumerate(text.split("|")):
        bar_start = beat
        for token in bar.split():
            name, _, length = token.partition(":")
            value = float(length or 1)
            events.append((None if name == "r" else note(name), beat, value))
            beat += value
        if bar.strip() and abs(beat - bar_start - beats_per_bar) > 1e-6:
            raise ValueError(f"bar {b + 1} has {beat - bar_start} beats: {bar.strip()}")
    return events
