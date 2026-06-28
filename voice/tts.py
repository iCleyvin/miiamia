"""TTS con Piper: sintetiza una frase y la reproduce por PipeWire (pw-play),
emitiendo amplitud (RMS) para el lip-sync. Soporta interrupción (barge-in)."""
from __future__ import annotations

import subprocess

from vad import rms_norm


def speak(text: str, piper_bin: str, voice_model: str, speaker=1, rate: int = 22050,
          amplitude_cb=None, stop_flag=None) -> bool:
    """Habla `text`. Devuelve False si fue interrumpido por stop_flag (barge-in)."""
    text = (text or "").strip()
    if not text:
        return True

    cmd = [piper_bin, "--model", voice_model, "--output-raw"]
    if speaker is not None:
        cmd += ["--speaker", str(speaker)]
    piper = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL)
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
        block = piper.stdout.read(2048)   # 1024 samples s16
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
    if interrupted:
        for p in (piper, player):
            if p.poll() is None:
                p.kill()
                p.wait()   # recolecta para no dejar zombie
    else:
        try:
            piper.wait(timeout=10)
        except subprocess.TimeoutExpired:
            piper.kill(); piper.wait()
        try:
            player.wait(timeout=10)
        except subprocess.TimeoutExpired:
            player.kill(); player.wait()
    if amplitude_cb:
        amplitude_cb(0.0)
    return not interrupted
