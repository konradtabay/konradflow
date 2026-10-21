#!/usr/bin/env python3
"""Benchmark OpenAI realtime vs batch STT on KonradFlow Dev session clips."""

from __future__ import annotations

import asyncio
import base64
import json
import struct
import subprocess
import sys
import time
import venv
import wave
from datetime import date
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
VENV_DIR = SCRIPT_DIR / ".venv-realtime"
VENV_PY = VENV_DIR / "bin" / "python3"
OUTPUT = SCRIPT_DIR.parent / "docs/benchmarks/openai-pipeline-2026-07-14.json"
AUDIO_DIR = Path.home() / "Library/Application Support/KonradFlow Dev/audio"
SETTINGS = Path.home() / "Library/Application Support/KonradFlow Dev/.settings"
REQUEST_GAP = 2.0


def ensure_websockets() -> None:
    try:
        import websockets  # noqa: F401
        return
    except ImportError:
        pass
    if not VENV_PY.exists():
        venv.EnvBuilder(with_pip=True).create(VENV_DIR)
    subprocess.check_call([str(VENV_PY), "-m", "pip", "install", "-q", "websockets"])
    import os

    os.execv(str(VENV_PY), [str(VENV_PY), str(Path(__file__).resolve())])


ensure_websockets()
import websockets  # noqa: E402


def load_settings() -> tuple[str, str]:
    data = json.loads(SETTINGS.read_text())
    key = data.get("transcription_api_key", "").strip()
    base = data.get("transcription_api_url", "https://api.openai.com/v1").strip()
    if not key:
        raise SystemExit("Missing transcription_api_key in KonradFlow Dev settings")
    return key, base.rstrip("/")


def wav_to_pcm24(path: Path) -> bytes:
    with wave.open(str(path), "rb") as wf:
        channels = wf.getnchannels()
        rate = wf.getframerate()
        frames = wf.readframes(wf.getnframes())
    samples = struct.unpack(f"<{len(frames) // 2}h", frames)
    if channels > 1:
        samples = samples[::channels]
    if rate != 24000:
        ratio = rate / 24000
        out = []
        for i in range(int(len(samples) / ratio)):
            out.append(samples[min(int(i * ratio), len(samples) - 1)])
        samples = out
    return struct.pack(f"<{len(samples)}h", *samples)


def curl_ms(args: list[str]) -> tuple[int, float]:
    start = time.perf_counter()
    proc = subprocess.run(args, capture_output=True, text=True)
    ms = (time.perf_counter() - start) * 1000
    code = int(proc.stdout.rsplit("\n", 1)[-1]) if proc.stdout.rstrip().endswith(tuple("0123456789")) else proc.returncode
    if "\nHTTP:" in proc.stdout or proc.stdout.rsplit("\n", 1)[-1].isdigit():
        body, code_line = proc.stdout.rsplit("\n", 1)
        code = int(code_line.replace("HTTP:", ""))
    else:
        body = proc.stdout
        code = proc.returncode
    return code, ms


async def bench_realtime(path: Path, key: str) -> dict:
    pcm = wav_to_pcm24(path)
    chunk = 4800
    url = "wss://api.openai.com/v1/realtime?intent=transcription"
    headers = {"Authorization": f"Bearer {key}"}
    connect_start = time.perf_counter()
    async with websockets.connect(url, additional_headers=headers, max_size=8 * 1024 * 1024) as ws:
        connect_ms = (time.perf_counter() - connect_start) * 1000
        await ws.recv()
        await ws.send(
            json.dumps(
                {
                    "type": "session.update",
                    "session": {
                        "type": "transcription",
                        "audio": {
                            "input": {
                                "format": {"type": "audio/pcm", "rate": 24000},
                                "transcription": {"model": "gpt-realtime-whisper", "delay": "minimal"},
                                "turn_detection": None,
                            }
                        },
                    },
                }
            )
        )
        await ws.recv()
        stream_start = time.perf_counter()
        first_delta_ms = None
        done = asyncio.Event()
        final = ""

        async def reader() -> None:
            nonlocal first_delta_ms, final
            async for message in ws:
                event = json.loads(message)
                et = event.get("type")
                if et == "conversation.item.input_audio_transcription.delta":
                    if first_delta_ms is None:
                        first_delta_ms = (time.perf_counter() - stream_start) * 1000
                elif et == "conversation.item.input_audio_transcription.completed":
                    final = event.get("transcript", final)
                    done.set()

        task = asyncio.create_task(reader())
        for off in range(0, len(pcm), chunk):
            await ws.send(
                json.dumps(
                    {
                        "type": "input_audio_buffer.append",
                        "audio": base64.b64encode(pcm[off : off + chunk]).decode("ascii"),
                    }
                )
            )
            await asyncio.sleep(0.03)
        commit_start = time.perf_counter()
        await ws.send(json.dumps({"type": "input_audio_buffer.commit"}))
        await asyncio.wait_for(done.wait(), timeout=30)
        commit_ms = (time.perf_counter() - commit_start) * 1000
        task.cancel()
        return {
            "connect_ms": round(connect_ms, 1),
            "first_delta_ms": round(first_delta_ms or 0, 1),
            "commit_to_final_ms": round(commit_ms, 1),
            "release_equivalent_ms": round(commit_ms, 1),
            "chars": len(final),
        }


def bench_batch(path: Path, key: str, base: str, model: str) -> dict:
    proc = subprocess.run(
        [
            "curl",
            "-sS",
            "-w",
            "\nHTTP:%{http_code}",
            "-X",
            "POST",
            f"{base}/audio/transcriptions",
            "-H",
            f"Authorization: Bearer {key}",
            "-F",
            f"model={model}",
            "-F",
            "response_format=json",
            "-F",
            f"file=@{path}",
        ],
        capture_output=True,
        text=True,
    )
    body, code_line = proc.stdout.rsplit("\n", 1)
    code = int(code_line.replace("HTTP:", ""))
    elapsed = 0.0
    if code == 200:
        elapsed = proc.stderr or 0
    # curl doesn't give timing in this mode; measure externally
    start = time.perf_counter()
    subprocess.run(
        [
            "curl",
            "-sS",
            "-o",
            "/dev/null",
            "-X",
            "POST",
            f"{base}/audio/transcriptions",
            "-H",
            f"Authorization: Bearer {key}",
            "-F",
            f"model={model}",
            "-F",
            "response_format=json",
            "-F",
            f"file=@{path}",
        ],
        check=False,
    )
    ms = (time.perf_counter() - start) * 1000
    chars = 0
    if code == 200:
        try:
            chars = len(json.loads(body).get("text", ""))
        except json.JSONDecodeError:
            pass
    return {"total_ms": round(ms, 1), "http": code, "chars": chars}


def p50(values: list[float]) -> float | None:
    if not values:
        return None
    values = sorted(values)
    return values[len(values) // 2]


def main() -> None:
    key, base = load_settings()
    clips = sorted(AUDIO_DIR.glob("*.wav"), key=lambda p: p.stat().st_size)
    if not clips:
        raise SystemExit(f"No clips in {AUDIO_DIR}")
    sample = [clips[len(clips) // 4], clips[len(clips) // 2], clips[(3 * len(clips)) // 4]]

    runs = []
    for path in sample:
        print(f"Realtime: {path.name} ({path.stat().st_size // 1024} KB)...", flush=True)
        rt = asyncio.run(bench_realtime(path, key))
        runs.append({"wav": path.name, "variant": "openai_realtime", **rt})
        print(f"  commit_to_final={rt['commit_to_final_ms']}ms", flush=True)
        time.sleep(REQUEST_GAP)

        print(f"Batch mini: {path.name}...", flush=True)
        batch = bench_batch(path, key, base, "gpt-4o-mini-transcribe")
        runs.append({"wav": path.name, "variant": "openai_batch_mini", **batch})
        print(f"  total={batch['total_ms']}ms", flush=True)
        time.sleep(REQUEST_GAP)

    rt_commit = [r["commit_to_final_ms"] for r in runs if r["variant"] == "openai_realtime"]
    batch_total = [r["total_ms"] for r in runs if r["variant"] == "openai_batch_mini"]
    summary = {
        "generated_on": date.today().isoformat(),
        "clip_count": len(sample),
        "openai_realtime_commit_p50_ms": p50(rt_commit),
        "openai_batch_mini_p50_ms": p50(batch_total),
        "estimated_savings_at_release_ms": round((p50(batch_total) or 0) - (p50(rt_commit) or 0), 1),
        "note": "release_equivalent_ms = commit_to_final only; excludes PP (~224ms) and paste (~12ms)",
        "runs": runs,
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps({k: v for k, v in summary.items() if k != "runs"}, indent=2))
    print(f"Wrote {OUTPUT}")


if __name__ == "__main__":
    main()
