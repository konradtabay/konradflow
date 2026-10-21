#!/usr/bin/env python3
"""Smoke-test OpenAI Realtime transcription against a saved KonradFlow WAV."""

from __future__ import annotations

import asyncio
import base64
import json
import os
import struct
import sys
import time
import venv
import wave
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
VENV_DIR = SCRIPT_DIR / ".venv-realtime"
VENV_PY = VENV_DIR / "bin" / "python3"


def ensure_websockets() -> None:
    try:
        import websockets  # noqa: F401
        return
    except ImportError:
        pass
    if not VENV_PY.exists():
        builder = venv.EnvBuilder(with_pip=True)
        builder.create(VENV_DIR)
    import subprocess

    subprocess.check_call([str(VENV_PY), "-m", "pip", "install", "-q", "websockets"])
    os.execv(str(VENV_PY), [str(VENV_PY), str(Path(__file__).resolve()), *sys.argv[1:]])


ensure_websockets()
import websockets  # noqa: E402

OPENAI_BASE = os.environ.get("OPENAI_BASE_URL", "https://api.openai.com/v1").rstrip("/")
REALTIME_MODEL = os.environ.get("REALTIME_MODEL", "gpt-realtime-whisper")
AUDIO_DIR = Path.home() / "Library/Application Support/KonradFlow Dev/audio"
SETTINGS_CANDIDATES = [
    Path.home() / "Library/Application Support/KonradFlow Dev/.settings",
    Path.home() / "Library/Application Support/KonradFlow/.settings",
]


def load_openai_key() -> str:
    key = os.environ.get("OPENAI_API_KEY", "").strip()
    if key:
        return key
    for path in SETTINGS_CANDIDATES:
        if not path.exists():
            continue
        stored = json.loads(path.read_text(encoding="utf-8")).get("transcription_api_key", "").strip()
        if stored:
            return stored
    raise SystemExit("Missing OPENAI_API_KEY and no transcription_api_key in KonradFlow settings")


def wav_to_pcm24_mono(path: Path) -> bytes:
    with wave.open(str(path), "rb") as wf:
        channels = wf.getnchannels()
        sample_width = wf.getsampwidth()
        sample_rate = wf.getframerate()
        frames = wf.readframes(wf.getnframes())
    if sample_width != 2:
        raise SystemExit(f"Expected 16-bit PCM WAV, got {sample_width * 8}-bit")
    samples = struct.unpack(f"<{len(frames) // 2}h", frames)
    if channels > 1:
        samples = samples[::channels]
    if sample_rate != 24000:
        ratio = sample_rate / 24000
        out = []
        target_len = int(len(samples) / ratio)
        for i in range(target_len):
            src = int(i * ratio)
            out.append(samples[min(src, len(samples) - 1)])
        samples = out
    return struct.pack(f"<{len(samples)}h", *samples)


def ws_url() -> str:
    if OPENAI_BASE.endswith("/v1"):
        return OPENAI_BASE.replace("https://", "wss://").replace("http://", "ws://") + "/realtime?intent=transcription"
    return OPENAI_BASE.replace("https://", "wss://").replace("http://", "ws://") + "/v1/realtime?intent=transcription"


async def run_test(wav: Path, key: str) -> None:
    pcm = wav_to_pcm24_mono(wav)
    chunk_bytes = 2400 * 2  # 100 ms at 24 kHz mono PCM16
    headers = {"Authorization": f"Bearer {key}"}

    connect_start = time.perf_counter()
    async with websockets.connect(ws_url(), additional_headers=headers, max_size=8 * 1024 * 1024) as ws:
        connect_ms = (time.perf_counter() - connect_start) * 1000

        # Wait for the server handshake before configuring the session.
        handshake = json.loads(await asyncio.wait_for(ws.recv(), timeout=10))
        if handshake.get("type") == "error":
            err = handshake.get("error", {})
            raise RuntimeError(f"{err.get('code')}: {err.get('message')}")

        session_update = {
            "type": "session.update",
            "session": {
                "type": "transcription",
                "audio": {
                    "input": {
                        "format": {"type": "audio/pcm", "rate": 24000},
                        "transcription": {
                            "model": REALTIME_MODEL,
                            "delay": "minimal",
                        },
                        "turn_detection": None,
                    }
                },
            },
        }
        await ws.send(json.dumps(session_update))
        updated = json.loads(await asyncio.wait_for(ws.recv(), timeout=10))
        if updated.get("type") == "error":
            err = updated.get("error", {})
            raise RuntimeError(f"{err.get('code')}: {err.get('message')}")

        stream_start = time.perf_counter()
        first_delta_ms: float | None = None
        final_text = ""
        done = asyncio.Event()

        async def reader() -> None:
            nonlocal first_delta_ms, final_text
            async for message in ws:
                event = json.loads(message)
                etype = event.get("type", "")
                if etype == "conversation.item.input_audio_transcription.delta":
                    if first_delta_ms is None:
                        first_delta_ms = (time.perf_counter() - stream_start) * 1000
                    sys.stdout.write(event.get("delta", ""))
                    sys.stdout.flush()
                elif etype == "conversation.item.input_audio_transcription.completed":
                    final_text = event.get("transcript", final_text)
                    done.set()
                elif etype == "error":
                    err = event.get("error", {})
                    raise RuntimeError(f"{err.get('code')}: {err.get('message')}")

        reader_task = asyncio.create_task(reader())

        for offset in range(0, len(pcm), chunk_bytes):
            chunk = pcm[offset : offset + chunk_bytes]
            await ws.send(
                json.dumps(
                    {
                        "type": "input_audio_buffer.append",
                        "audio": base64.b64encode(chunk).decode("ascii"),
                    }
                )
            )
            await asyncio.sleep(0.04)

        commit_start = time.perf_counter()
        await ws.send(json.dumps({"type": "input_audio_buffer.commit"}))
        await asyncio.wait_for(done.wait(), timeout=30)
        commit_to_final_ms = (time.perf_counter() - commit_start) * 1000
        reader_task.cancel()

        print("\n")
        print(f"clip:              {wav.name} ({wav.stat().st_size // 1024} KB)")
        print(f"connect_ms:        {connect_ms:.0f}")
        print(f"first_delta_ms:    {first_delta_ms:.0f}" if first_delta_ms else "first_delta_ms:    n/a")
        print(f"commit_to_final_ms:{commit_to_final_ms:.0f}")
        print(f"final_chars:       {len(final_text)}")


def main() -> None:
    key = load_openai_key()
    wavs = sorted(AUDIO_DIR.glob("*.wav"), key=lambda p: p.stat().st_size)
    if not wavs:
        raise SystemExit(f"No WAV files in {AUDIO_DIR}")
    wav = wavs[len(wavs) // 2]
    if len(sys.argv) > 1:
        wav = Path(sys.argv[1])
    print(f"Testing OpenAI Realtime ({REALTIME_MODEL}) on {wav.name}")
    asyncio.run(run_test(wav, key))


if __name__ == "__main__":
    main()
