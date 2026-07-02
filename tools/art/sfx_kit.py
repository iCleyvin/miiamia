"""sfx_kit — mini-motor DSP para diseño sonoro cinematográfico (numpy + scipy).

Lo que separa un blip de Atari de un sonido sci-fi: CAPAS (sub + aire + tono + brillo),
movimiento (barridos, vibrato, desafinación) y sobre todo REVERB con cola. Aquí:
reverb Schroeder (combs+allpass), FM de cristal, pads desafinados, ruido con filtro
barrido por bloques (overlap-add), granular, bitcrush y saturación suave.

Correr con el venv de arte: ~/miiamia-art/.venv/bin/python (numpy+scipy).
"""
from __future__ import annotations

import numpy as np
from scipy import signal

SR = 44100


# ----------------------------------------------------------------- utilidades
def t_axis(dur: float) -> np.ndarray:
    return np.arange(int(SR * dur)) / SR


def env_exp(dur: float, attack: float = 0.005, decay: float = 4.0) -> np.ndarray:
    t = t_axis(dur)
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-decay * t)


def env_swell(dur: float, up: float = 0.5, down: float = 0.3) -> np.ndarray:
    """Sube suave (seno) hasta `up`, meseta, y cae en los últimos `down` segundos."""
    n = int(SR * dur)
    e = np.ones(n)
    nu, nd = int(SR * up), int(SR * down)
    if nu > 0:
        e[:nu] = np.sin(np.linspace(0, np.pi / 2, nu)) ** 2
    if nd > 0:
        e[-nd:] *= np.cos(np.linspace(0, np.pi / 2, nd)) ** 2
    return e


def saturate(x: np.ndarray, drive: float = 1.6) -> np.ndarray:
    return np.tanh(x * drive) / np.tanh(drive)


def sine_sweep(f0: float, f1: float, dur: float, curve: float = 1.0) -> np.ndarray:
    t = t_axis(dur)
    f = f0 + (f1 - f0) * (t / dur) ** curve
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def sub(f0: float, f1: float, dur: float, decay: float = 3.0, drive: float = 2.2) -> np.ndarray:
    """Sub-bass con barrido y saturación (el 'peso' cinematográfico)."""
    return saturate(sine_sweep(f0, f1, dur, 0.7) * env_exp(dur, 0.004, decay), drive)


def pad(freqs, dur: float, voices: int = 5, detune: float = 0.004,
        vib_hz: float = 4.5, vib_amt: float = 0.0025) -> np.ndarray:
    """Pad desafinado con vibrato lento: nunca estático, siempre 'vivo'."""
    t = t_axis(dur)
    out = np.zeros_like(t)
    rng = np.random.default_rng(7)
    vib = 1 + vib_amt * np.sin(2 * np.pi * vib_hz * t + rng.uniform(0, 6.28))
    for f in np.atleast_1d(freqs):
        for v in range(voices):
            d = 1 + detune * (v - (voices - 1) / 2) / max(1, (voices - 1) / 2)
            ph = rng.uniform(0, 2 * np.pi)
            out += np.sin(2 * np.pi * np.cumsum(f * d * vib) / SR + ph) / voices
    return out / max(1, len(np.atleast_1d(freqs)))


def fm_bell(f: float, dur: float, ratio: float = 2.756, index: float = 3.0,
            decay: float = 5.0) -> np.ndarray:
    """Campana FM de cristal (el 'ping' sci-fi, no un bleep cuadrado)."""
    t = t_axis(dur)
    idx = index * np.exp(-decay * 1.4 * t)
    mod = np.sin(2 * np.pi * f * ratio * t) * idx
    return np.sin(2 * np.pi * f * t + mod) * env_exp(dur, 0.002, decay)


def noise_sweep(dur: float, f0: float, f1: float, q: float = 2.5,
                curve: float = 1.0) -> np.ndarray:
    """Ruido con paso-banda BARRIDO (riser/whoosh): filtro variable por bloques overlap-add."""
    n = int(SR * dur)
    x = np.random.default_rng(3).uniform(-1, 1, n)
    hop, win = 512, 1024
    out = np.zeros(n + win)
    w = np.hanning(win)
    for i in range(0, n - 1, hop):
        tt = (i / n) ** curve
        fc = np.clip(f0 * (f1 / f0) ** tt, 30, SR / 2 - 200)   # barrido logarítmico
        sos = signal.butter(2, [fc / (1 + 1 / q), min(fc * (1 + 1 / q), SR / 2 - 100)],
                            "bandpass", fs=SR, output="sos")
        blk = x[i:i + win]
        out[i:i + len(blk)] += signal.sosfilt(sos, blk * w[:len(blk)])
    return out[:n]


def lowpass_sweep(x: np.ndarray, f0: float, f1: float) -> np.ndarray:
    """Paso-bajo cuyo corte barre f0->f1 (cerrar = 'apagado', abrir = 'despertar')."""
    n = len(x)
    hop, win = 512, 1024
    out = np.zeros(n + win)
    w = np.hanning(win)
    for i in range(0, n - 1, hop):
        fc = np.clip(f0 * (f1 / f0) ** (i / n), 40, SR / 2 - 200)
        sos = signal.butter(2, fc, "lowpass", fs=SR, output="sos")
        blk = x[i:i + win]
        out[i:i + len(blk)] += signal.sosfilt(sos, blk * w[:len(blk)])
    return out[:n]


def bitcrush(x: np.ndarray, bits: int = 6, down: int = 5) -> np.ndarray:
    q = 2 ** (bits - 1)
    y = np.round(x * q) / q
    return np.repeat(y[::down], down)[:len(x)]


def grains(x: np.ndarray, dur: float, g_ms=(18, 45), density: float = 40,
           seed: int = 11) -> np.ndarray:
    """Granular: trocea una textura y la recompone desordenada (el 'tear' digital)."""
    rng = np.random.default_rng(seed)
    n = int(SR * dur)
    out = np.zeros(n)
    t = 0
    while t < n:
        g = int(SR * rng.uniform(*g_ms) / 1000)
        src = rng.integers(0, max(1, len(x) - g))
        grain = x[src:src + g] * np.hanning(g)
        if rng.random() < 0.3:
            grain = grain[::-1]
        gain = rng.uniform(0.3, 1.0) * (rng.random() < 0.85)
        out[t:t + g] += grain[:max(0, min(g, n - t))] * gain
        t += int(g * rng.uniform(0.4, 0.9))
    return out


def reverb(x: np.ndarray, wet: float = 0.35, size: float = 1.0,
           damp: float = 0.35, tail: float = 1.2) -> np.ndarray:
    """Schroeder: 4 combs + 2 allpass. `size` escala delays; `tail` añade cola en segundos."""
    x = np.concatenate([x, np.zeros(int(SR * tail))])
    combs = [(int(SR * d * size), g) for d, g in
             ((0.0297, 0.82), (0.0371, 0.80), (0.0411, 0.78), (0.0437, 0.76))]
    wetsig = np.zeros_like(x)
    for D, g in combs:
        b = np.zeros(D + 1); b[0] = 1
        a = np.zeros(D + 1); a[0] = 1; a[D] = -g
        wetsig += signal.lfilter(b, a, x) / len(combs)
    for D, g in ((int(SR * 0.005), 0.7), (int(SR * 0.0017), 0.7)):
        b = np.zeros(D + 1); b[0] = -g; b[D] = 1
        a = np.zeros(D + 1); a[0] = 1; a[D] = -g
        wetsig = signal.lfilter(b, a, wetsig)
    sos = signal.butter(1, 3800 * (1 - damp) + 1200, "lowpass", fs=SR, output="sos")
    wetsig = signal.sosfilt(sos, wetsig)
    return x * (1 - wet) + wetsig * wet


def master(x: np.ndarray, gain: float = 0.8, fade_out: float = 0.08) -> np.ndarray:
    """HPF 25Hz + soft clip + normalizado + fades: nada de clicks ni DC."""
    sos = signal.butter(2, 25, "highpass", fs=SR, output="sos")
    x = signal.sosfilt(sos, x)
    x = saturate(x, 1.15)
    x = x / max(1e-9, np.max(np.abs(x))) * gain
    nf = int(SR * fade_out)
    if nf > 0 and nf < len(x):
        x[-nf:] *= np.cos(np.linspace(0, np.pi / 2, nf)) ** 2
    ni = int(SR * 0.003)
    x[:ni] *= np.linspace(0, 1, ni)
    return x


def write_wav(path, x: np.ndarray):
    import struct
    import wave
    data = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(data)
    print(f"  ✓ {path.name} ({len(x)/SR:.2f}s)")


def mix(*layers) -> np.ndarray:
    """Suma capas de distintas longitudes; cada capa puede ser (señal, offset_segundos)."""
    parts = [(l if isinstance(l, tuple) else (l, 0.0)) for l in layers]
    n = max(int(SR * off) + len(sig) for sig, off in parts)
    out = np.zeros(n)
    for sig, off in parts:
        i = int(SR * off)
        out[i:i + len(sig)] += sig
    return out
