#!/usr/bin/env python3
"""Replay saved KonradFlow WAV clips through STT + post-processing variants."""

from __future__ import annotations

import json
import subprocess
import sys
import time
import tempfile
from datetime import date
from pathlib import Path

BASE_URL = "https://api.groq.com/openai/v1"
AUDIO_DIR = Path.home() / "Library/Application Support/KonradFlow Dev/audio"
SETTINGS = Path.home() / "Library/Application Support/KonradFlow/.settings"
OUTPUT = Path(__file__).resolve().parent.parent / "docs/benchmarks/replay-pipeline-2026-07-14.json"

VARIANTS = {
    "baseline": {
        "stt_model": "whisper-large-v3",
        "pp_model": "openai/gpt-oss-20b",
        "run_pp": True,
    },
    "fast_cleanup": {
        "stt_model": "whisper-large-v3",
        "pp_model": "groq/compound-mini",
        "run_pp": True,
    },
    "fast_stt_turbo": {
        "stt_model": "whisper-large-v3-turbo",
        "pp_model": "openai/gpt-oss-20b",
        "run_pp": True,
    },
    "fast_both": {
        "stt_model": "whisper-large-v3-turbo",
        "pp_model": "groq/compound-mini",
        "run_pp": True,
    },
}


def load_api_key() -> str:
    data = json.loads(SETTINGS.read_text(encoding="utf-8"))
    key = (data.get("groq_api_key") or "").strip()
    if not key:
        raise SystemExit("Missing groq_api_key in KonradFlow settings")
    return key


def percentile(values: list[float], p: float) -> float | None:
    if not values:
        return None
    values = sorted(values)
    idx = max(0, min(len(values) - 1, int(round(p * (len(values) - 1)))))
    return values[idx]


def curl_post_multipart(url: str, key: str, fields: dict[str, str], wav: Path) -> tuple[int, str, float]:
    start = time.perf_counter()
    cmd = [
        "curl",
        "-sS",
        "-w",
        "\n%{http_code}",
        "-X",
        "POST",
        url,
        "-H",
        f"Authorization: Bearer {key}",
    ]
    for name, value in fields.items():
        cmd.extend(["-F", f"{name}={value}"])
    cmd.extend(["-F", f"file=@{wav}"])
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    elapsed_ms = (time.perf_counter() - start) * 1000
    output = proc.stdout
    if "\n" not in output:
        return 0, proc.stderr or output, elapsed_ms
    body, status_line = output.rsplit("\n", 1)
    return int(status_line), body, elapsed_ms


def curl_post_json(url: str, key: str, payload: dict) -> tuple[int, str, float]:
    start = time.perf_counter()
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as tmp:
        json.dump(payload, tmp)
        tmp_path = tmp.name
    try:
        proc = subprocess.run(
            [
                "curl",
                "-sS",
                "-w",
                "\n%{http_code}",
                "-X",
                "POST",
                url,
                "-H",
                f"Authorization: Bearer {key}",
                "-H",
                "Content-Type: application/json",
                "--data-binary",
                f"@{tmp_path}",
            ],
            capture_output=True,
            text=True,
            check=False,
        )
    finally:
        Path(tmp_path).unlink(missing_ok=True)
    elapsed_ms = (time.perf_counter() - start) * 1000
    output = proc.stdout
    if "\n" not in output:
        return 0, proc.stderr or output, elapsed_ms
    body, status_line = output.rsplit("\n", 1)
    return int(status_line), body, elapsed_ms


REQUEST_GAP_SEC = 3.5
MAX_RETRIES = 6


def _retry_after_sec(body: str, attempt: int) -> float:
    try:
        err = json.loads(body).get("error", {})
        message = err.get("message", "")
        if "try again in" in message.lower():
            import re

            match = re.search(r"try again in ([0-9.]+)s", message, re.I)
            if match:
                return float(match.group(1)) + 0.5
    except (json.JSONDecodeError, ValueError, TypeError):
        pass
    return min(60.0, REQUEST_GAP_SEC * (attempt + 1))


def groq_call(fn, label: str):
    last_exc: Exception | None = None
    for attempt in range(MAX_RETRIES):
        try:
            result = fn()
            time.sleep(REQUEST_GAP_SEC)
            return result
        except RuntimeError as exc:
            last_exc = exc
            msg = str(exc)
            if "HTTP 429" not in msg and "HTTP 5" not in msg:
                raise
            wait = _retry_after_sec(msg, attempt)
            print(f"  {label}: rate limited, waiting {wait:.1f}s...", file=sys.stderr, flush=True)
            time.sleep(wait)
    raise last_exc or RuntimeError(f"{label} failed after retries")


def transcribe(key: str, wav: Path, model: str) -> tuple[str, float]:
    def _call() -> tuple[str, float]:
        status, body, elapsed_ms = curl_post_multipart(
            f"{BASE_URL}/audio/transcriptions",
            key,
            {"model": model, "response_format": "json"},
            wav,
        )
        if status != 200:
            raise RuntimeError(f"STT HTTP {status}: {body[:200]}")
        text = (json.loads(body).get("text") or "").strip()
        return text, elapsed_ms

    return groq_call(_call, f"STT {model}")


def post_process(key: str, transcript: str, model: str) -> tuple[str, float]:
    payload = {
        "model": model,
        "messages": [
            {
                "role": "system",
                "content": "Clean up this dictated transcript. Fix punctuation and casing. Return only the cleaned text.",
            },
            {"role": "user", "content": transcript},
        ],
        "temperature": 0,
    }

    def _call() -> tuple[str, float]:
        status, body, elapsed_ms = curl_post_json(f"{BASE_URL}/chat/completions", key, payload)
        if status != 200:
            raise RuntimeError(f"post-processing HTTP {status}: {body[:200]}")
        content = json.loads(body)["choices"][0]["message"]["content"].strip()
        return content, elapsed_ms

    return groq_call(_call, f"PP {model}")


def main() -> None:
    key = load_api_key()
    wavs = sorted(AUDIO_DIR.glob("*.wav"), key=lambda p: p.stat().st_size)
    if not wavs:
        raise SystemExit(f"No WAV files in {AUDIO_DIR}")

    runs: list[dict] = []
    totals: dict[str, list[float]] = {name: [] for name in VARIANTS}
    stt_totals: dict[str, list[float]] = {name: [] for name in VARIANTS}
    pp_totals: dict[str, list[float]] = {name: [] for name in VARIANTS}

    for wav in wavs:
        print(f"Replaying {wav.name} ({wav.stat().st_size // 1024} KB)...", flush=True)
        for variant_name, cfg in VARIANTS.items():
            try:
                transcript, stt_ms = transcribe(key, wav, cfg["stt_model"])
                pp_ms = 0.0
                final = transcript
                if cfg["run_pp"] and transcript:
                    final, pp_ms = post_process(key, transcript, cfg["pp_model"])
                total_ms = stt_ms + pp_ms
                runs.append(
                    {
                        "wav": wav.name,
                        "variant": variant_name,
                        "stt_ms": round(stt_ms, 1),
                        "pp_ms": round(pp_ms, 1),
                        "total_ms": round(total_ms, 1),
                        "raw_len": len(transcript),
                        "final_len": len(final),
                    }
                )
                totals[variant_name].append(total_ms)
                stt_totals[variant_name].append(stt_ms)
                pp_totals[variant_name].append(pp_ms)
                print(f"  {variant_name}: stt={stt_ms:.0f}ms pp={pp_ms:.0f}ms total={total_ms:.0f}ms", flush=True)
            except Exception as exc:  # noqa: BLE001
                print(f"  {variant_name}: {exc}", file=sys.stderr, flush=True)

    summary = {
        "generated_on": date.today().isoformat(),
        "audio_dir": str(AUDIO_DIR),
        "clip_count": len(wavs),
        "note": (
            "Simulated post-release pipeline only (STT upload + LLM cleanup). "
            "Does not include T_start mic warm-up or shortcut-release paste delay."
        ),
        "live_dev_session_baseline": {
            "source": "docs/benchmarks/baseline-2026-07-14.json",
            "t_start_p50_ms": 13.2,
            "t_paste_p50_ms": 920.6,
            "stt_p50_ms": 430.4,
            "pp_p50_ms": 223.6,
        },
        "variants": {},
        "runs": runs,
    }

    baseline_p50 = percentile(totals["baseline"], 0.5)
    for name, values in totals.items():
        summary["variants"][name] = {
            "total_ms": {
                "count": len(values),
                "p50": percentile(values, 0.5),
                "p95": percentile(values, 0.95),
            },
            "stt_ms": {
                "p50": percentile(stt_totals[name], 0.5),
                "p95": percentile(stt_totals[name], 0.95),
            },
            "pp_ms": {
                "p50": percentile(pp_totals[name], 0.5),
                "p95": percentile(pp_totals[name], 0.95),
            },
        }
        if baseline_p50 and name != "baseline":
            p50 = summary["variants"][name]["total_ms"]["p50"]
            if p50 is not None:
                summary["variants"][name]["delta_vs_baseline_p50_ms"] = round(p50 - baseline_p50, 1)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in summary.items() if k != "runs"}, indent=2), flush=True)
    print(f"Wrote {OUTPUT}", flush=True)


if __name__ == "__main__":
    main()
