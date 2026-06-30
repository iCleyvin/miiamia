"""TTS con Piper: sintetiza una frase y la reproduce por PipeWire (pw-play),
emitiendo amplitud (RMS) para el lip-sync. Soporta interrupción (barge-in).

Por pet puede aplicar un EFECTO de voz (`fx`) insertando una etapa ffmpeg entre Piper y la
reproducción (p.ej. "infernal" para el dragón), y cambiar la VELOCIDAD de habla (`length_scale`,
>1.0 = más lento y pausado). Sin fx el camino es idéntico al original (Piper -> pw-play)."""
from __future__ import annotations

import subprocess

from vad import rms_norm


def _fx_filtergraph(name: str, sr: int):
    """-filter_complex de ffmpeg para el efecto `name`, o None si no hay efecto."""
    if name == "infernal":
        # Dragona infernal: tono -20% (grave pero aún femenino) + una capa a la octava de abajo
        # (rugido sobrenatural) + realce de graves + reverberación de caverna + grit suave.
        # atempo=1.25 neutraliza el cambio de tempo del pitch-down; la lentitud la pone length_scale.
        half = sr // 2
        return (
            "[0:a]asplit=2[a][b];"
            f"[a]asetrate={sr}*0.80,aresample={sr},atempo=1.25[m];"
            f"[b]asetrate={half},aresample={sr},atempo=2.0,volume=0.40[s];"
            "[m][s]amix=inputs=2:normalize=0[mix];"
            "[mix]bass=g=5:f=110,aecho=0.85:0.78:55|120:0.28|0.14,"
            "asoftclip=type=tanh,volume=1.3,alimiter=limit=0.95[out]"
        )
    return None


def speak(text: str, piper_bin: str, voice_model: str, speaker=1, rate: int = 22050,
          amplitude_cb=None, stop_flag=None, fx: str = "", length_scale: float = 1.0) -> bool:
    """Habla `text`. Devuelve False si fue interrumpido por stop_flag (barge-in)."""
    text = (text or "").strip()
    if not text:
        return True

    cmd = [piper_bin, "--model", voice_model, "--output-raw"]
    try:
        if length_scale and abs(float(length_scale) - 1.0) > 1e-3:
            cmd += ["--length_scale", str(length_scale)]
    except (TypeError, ValueError):
        pass
    if speaker is not None:
        cmd += ["--speaker", str(speaker)]
    piper = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL)

    # Efecto de voz opcional: Piper -> ffmpeg(fx) -> reproducción. Si no hay fx, se lee de Piper.
    fxgraph = _fx_filtergraph(fx, rate) if fx else None
    ff = None
    audio_src = piper.stdout
    if fxgraph:
        try:
            ff = subprocess.Popen(
                ["ffmpeg", "-hide_banner", "-loglevel", "error",
                 "-f", "s16le", "-ar", str(rate), "-ac", "1", "-i", "pipe:0",
                 "-filter_complex", fxgraph, "-map", "[out]",
                 "-f", "s16le", "-ar", str(rate), "-ac", "1", "pipe:1"],
                stdin=piper.stdout, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            piper.stdout.close()   # deja que el EOF de Piper llegue a ffmpeg
            audio_src = ff.stdout
        except Exception:
            ff = None
            audio_src = piper.stdout

    # pw-play lee PCM crudo de stdin (s16 mono al rate de la voz).
    player = subprocess.Popen(
        ["pw-play", "--rate=%d" % rate, "--channels=1", "--format=s16", "--raw", "-"],
        stdin=subprocess.PIPE, stderr=subprocess.DEVNULL)

    try:
        piper.stdin.write(text.encode("utf-8"))
        piper.stdin.close()
    except BrokenPipeError:
        pass

    interrupted = False
    while True:
        block = audio_src.read(2048)   # 1024 samples s16
        if not block:
            break
        if stop_flag and stop_flag():
            interrupted = True
            break
        try:
            player.stdin.write(block)
        except BrokenPipeError:
            interrupted = True
            break
        if amplitude_cb:
            amplitude_cb(rms_norm(block))

    try:
        player.stdin.close()
    except Exception:
        pass

    procs = [p for p in (piper, ff, player) if p is not None]
    if interrupted:
        for p in procs:
            if p.poll() is None:
                p.kill()
                p.wait()   # recolecta para no dejar zombie
    else:
        for p in procs:
            try:
                p.wait(timeout=10)
            except subprocess.TimeoutExpired:
                p.kill(); p.wait()
    if amplitude_cb:
        amplitude_cb(0.0)
    return not interrupted
