"""TTS con Piper: sintetiza una frase y la reproduce por PipeWire (pw-play),
emitiendo amplitud (RMS) para el lip-sync. Soporta interrupción (barge-in).

Por pet puede aplicar un EFECTO de voz (`fx`) insertando una etapa ffmpeg entre Piper y la
reproducción (p.ej. "infernal" para el dragón), y cambiar la VELOCIDAD de habla (`length_scale`,
>1.0 = más lento y pausado). Sin fx el camino es idéntico al original (Piper -> pw-play)."""
from __future__ import annotations

import json
import subprocess
import tempfile
import time

from vad import rms_norm


def _voice_rate(voice_model: str, default: int = 22050) -> int:
    """Sample rate real de la voz (del .onnx.json de Piper). Las voces *-low son de 16000 Hz:
    con el rate equivocado suenan aceleradas/agudas."""
    try:
        with open(voice_model + ".json", encoding="utf-8") as f:
            return int(json.load(f).get("audio", {}).get("sample_rate", default))
    except Exception:
        return default


def _fx_filtergraph(name: str, sr: int):
    """-filter_complex de ffmpeg para el efecto `name`, o None si no hay efecto."""
    if name == "cute":
        # Voz kawaii (p.ej. ajolote): tono +14% (más agudo/tierno pero aún humano, sin chipmunk) +
        # brillo ("aire") + un toque de chispa/dulzura con un chorus muy leve. Sin graves ni caverna.
        return (
            "[0:a]asetrate={sr}*1.17,aresample={sr},atempo=0.855[p];"
            "[p]treble=g=4:f=3800,"
            "chorus=0.6:0.9:40:0.25:0.4:2,"
            "volume=1.4,alimiter=limit=0.95[out]"
        ).format(sr=sr)
    if name == "sweet":
        # Voz DULCE y SUAVE (mujer): tono +6% (femenino tierno, sin chipmunk), calidez en graves,
        # un toque de "aire"/brillo para dulzura, y un halo de reverb muy suave para suavidad.
        # atempo=0.9434 neutraliza el cambio de tempo del pitch-up; la pausa la pone length_scale.
        return (
            "[0:a]asetrate={sr}*1.06,aresample={sr},atempo=0.9434[p];"
            "[p]bass=g=2:f=170,treble=g=2.5:f=7000,"
            "aecho=0.9:0.55:22:0.16,"
            "volume=1.2,alimiter=limit=0.95[out]"
        ).format(sr=sr)
    if name == "cyber":
        # Voz SINTÉTICA cyberpunk (Nyx): timbre metálico por AM rápida (tremolo a ~65Hz),
        # doble voz muy junta (chorus corto), brillo digital y un eco seco de sala pequeña.
        return (
            "[0:a]chorus=0.7:0.9:12|18:0.42|0.38:0.6|0.5:0.8|0.7[p];"
            "[p]tremolo=f=65:d=0.22,treble=g=5:f=4500,highpass=f=120,"
            "aecho=0.75:0.4:18:0.18,"
            "volume=1.25,alimiter=limit=0.95[out]"
        )
    if name == "bubble":
        # Voz SUBMARINA (Otto el pulpo): apagada como bajo el agua (paso-bajo), con un
        # wobble líquido (chorus) y un eco corto de tanque. Tono casi neutro (-4%).
        return (
            "[0:a]asetrate={sr}*0.96,aresample={sr},atempo=1.0417[p];"
            "[p]lowpass=f=2500,bass=g=3:f=200,"
            "chorus=0.6:0.9:45|55:0.32|0.28:0.5|0.4:1.8|1.4,"
            "aecho=0.8:0.55:35|90:0.25|0.14,"
            "volume=1.35,alimiter=limit=0.95[out]"
        ).format(sr=sr)
    if name == "ghost":
        # Voz ETÉREA (fantasmas/fénix): un toque más aguda y con "aire", eco largo y suave
        # (presencia que flota), sin graves (los cuerpos etéreos no tienen pecho).
        return (
            "[0:a]asetrate={sr}*1.08,aresample={sr},atempo=0.9259[p];"
            "[p]highpass=f=220,treble=g=5:f=5000,"
            "chorus=0.5:0.9:50|60:0.3|0.25:0.3|0.28:1.5|1.2,"
            "aecho=0.8:0.7:60|180:0.35|0.22,"
            "volume=1.25,alimiter=limit=0.95[out]"
        ).format(sr=sr)
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
    """Habla `text`. Devuelve False si fue interrumpido por stop_flag (barge-in).
    Lanza RuntimeError si Piper falla sin producir audio (voz inexistente/corrupta):
    antes ese fallo era invisible (stderr a DEVNULL, returncode ignorado) y la pet
    quedaba muda para siempre sin pista alguna en los logs."""
    text = (text or "").strip()
    if not text:
        return True
    rate = _voice_rate(voice_model, rate)

    cmd = [piper_bin, "--model", voice_model, "--output-raw"]
    try:
        if length_scale and abs(float(length_scale) - 1.0) > 1e-3:
            cmd += ["--length_scale", str(length_scale)]
    except (TypeError, ValueError):
        pass
    if speaker is not None:
        cmd += ["--speaker", str(speaker)]
    # stderr a tempfile (no PIPE: sin lector se llenaría y bloquearía a piper) para diagnóstico.
    errf = tempfile.TemporaryFile()
    piper = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=errf)

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

    # pw-play lee PCM crudo de stdin (s16 mono al rate de la voz). Si falta el binario,
    # reapear lo ya lanzado (piper/ffmpeg quedaban vivos bloqueados en un pipe sin lector).
    try:
        player = subprocess.Popen(
            ["pw-play", "--rate=%d" % rate, "--channels=1", "--format=s16", "--raw", "-"],
            stdin=subprocess.PIPE, stderr=subprocess.DEVNULL)
    except Exception:
        for p in (piper, ff):
            if p is not None and p.poll() is None:
                p.kill(); p.wait()
        errf.close()
        raise

    try:
        piper.stdin.write(text.encode("utf-8"))
        piper.stdin.close()
    except BrokenPipeError:
        pass

    interrupted = False
    samples = 0
    start = time.monotonic()
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
        samples += len(block) // 2
        if amplitude_cb:
            amplitude_cb(rms_norm(block))
        # Ritmo casi-realtime: Piper sintetiza más rápido que el audio y la amplitud (boca)
        # iba ~1.5 s adelantada a lo audible. No adelantarse más de ~0.4 s de colchón.
        lead = samples / rate - (time.monotonic() - start)
        if lead > 0.4:
            time.sleep(lead - 0.4)

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

    # Piper murió sin producir NADA -> error real (voz inexistente, modelo corrupto...).
    if not interrupted and samples == 0 and piper.returncode not in (0, None):
        try:
            errf.seek(0)
            tail = errf.read()[-400:].decode("utf-8", "replace").strip()
        except Exception:
            tail = ""
        errf.close()
        raise RuntimeError("piper falló (código %s) con la voz %s%s"
                           % (piper.returncode, voice_model, (": " + tail) if tail else ""))
    errf.close()
    return not interrupted
