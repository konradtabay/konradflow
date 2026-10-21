#!/usr/bin/env python3
"""Quick stage-by-stage speed report for the KonradFlow dictation path.

Reads latency traces written by the app and prints every measured gap from
Fn down through paste. Optional --probe times a live Julia choice on the
helper socket without starting a new dictation.
"""

from __future__ import annotations

import argparse
import json
import socket
import statistics
import sys
import time
from pathlib import Path

STAGE_ORDER = [
    "holdActivated",
    "startRecordingEntered",
    "beginRecording",
    "firstBuffer",
    "holdDeactivated",
    "wavReady",
    "contextReady",
    "sttDone",
    "candidatesBuilt",
    "juliaDone",
    "ppDone",
    "pastePosted",
]

# Consecutive gaps, in pipeline order. A gap is skipped when either mark is missing.
CONSECUTIVE = [
    ("holdActivated", "startRecordingEntered", "Fn down → recording function entered"),
    ("startRecordingEntered", "beginRecording", "Checks → microphone start"),
    ("beginRecording", "firstBuffer", "Microphone start → first audio"),
    ("holdDeactivated", "wavReady", "Release → audio file closed"),
    ("wavReady", "sttDone", "Audio closed → Groq final transcript"),
    ("sttDone", "candidatesBuilt", "Transcript → cleanup candidates"),
    ("candidatesBuilt", "juliaDone", "Candidates → Julia choice"),
    ("sttDone", "ppDone", "Transcript → cleanup finished"),
    ("ppDone", "pastePosted", "Cleanup finished → paste posted"),
]

HEADLINES = [
    ("holdActivated", "firstBuffer", "Fn down → first audio"),
    ("holdDeactivated", "pastePosted", "Release → paste"),
    ("holdActivated", "holdDeactivated", "Hold length (speaking)"),
]


def trace_file() -> Path:
    candidates = [
        Path.home() / "Library/Application Support/KonradFlow Dev/latency-traces.jsonl",
        Path.home() / "Library/Application Support/KonradFlow/latency-traces.jsonl",
    ]
    for path in candidates:
        if path.exists():
            return path
    return candidates[0]


def load_records(path: Path) -> list[dict]:
    if not path.exists():
        raise SystemExit(f"No traces at {path}\nDictate once in KonradFlow Dev, then re-run.")
    records = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    if not records:
        raise SystemExit(f"Trace file is empty: {path}")
    return records


def span_ms(record: dict, start: str, end: str) -> float | None:
    ts = record.get("timestamps") or {}
    if start not in ts or end not in ts:
        return None
    return (ts[end] - ts[start]) * 1000


def median(values: list[float]) -> float:
    return statistics.median(values)


def fmt(value: float | None) -> str:
    if value is None:
        return "—"
    return f"{value:.0f}"


def print_table(title: str, rows: list[tuple[str, list[float]]]) -> None:
    print(f"\n{title}")
    print(f"{'Stage':<46} {'n':>3} {'min':>7} {'med':>7} {'max':>7}")
    print("-" * 74)
    for label, values in rows:
        if not values:
            print(f"{label:<46} {'0':>3} {'—':>7} {'—':>7} {'—':>7}")
            continue
        print(
            f"{label:<46} {len(values):>3} {min(values):>7.0f} {median(values):>7.0f} {max(values):>7.0f}"
        )


def report(records: list[dict], last: int) -> None:
    window = records[-last:]
    print(f"Pipeline speed — last {len(window)} of {len(records)} traces")
    config = window[-1].get("config") or {}
    if config:
        flags = ", ".join(
            f"{key}={value}"
            for key, value in config.items()
            if key in ("pasteLightEnabled", "realtimeStreamingEnabled", "transcriptionModel", "postProcessingModel")
        )
        print(flags)

    headline_rows = []
    for start, end, label in HEADLINES:
        values = [v for record in window if (v := span_ms(record, start, end)) is not None]
        headline_rows.append((label, values))
    print_table("Totals (ms)", headline_rows)

    stage_rows = []
    for start, end, label in CONSECUTIVE:
        values = [v for record in window if (v := span_ms(record, start, end)) is not None]
        stage_rows.append((label, values))
    print_table("Each step (ms)", stage_rows)

    latest = window[-1]
    print("\nLatest run, from release")
    ts = latest.get("timestamps") or {}
    if "holdDeactivated" not in ts:
        print("  (no release mark)")
    else:
        base = ts["holdDeactivated"]
        previous = None
        for stage in STAGE_ORDER:
            if stage not in ts:
                continue
            rel = (ts[stage] - base) * 1000
            delta = ""
            if previous is not None:
                delta = f"   +{(ts[stage] - previous) * 1000:.0f} ms"
            print(f"  {stage:<24} {rel:8.0f} ms{delta}")
            previous = ts[stage]

    report_julia(records, window)


# Julia pasted when its choice is present and cleanup did not continue into a
# Groq call. A quick fire is that paste with the choice itself under 50 ms.
JULIA_FOLLOW_THROUGH_MS = 80
JULIA_QUICK_CHOICE_MS = 50


def julia_choice_ms(record: dict) -> float | None:
    return span_ms(record, "candidatesBuilt", "juliaDone")


def julia_fired(record: dict) -> bool:
    choice = julia_choice_ms(record)
    if choice is None:
        return False
    follow = span_ms(record, "juliaDone", "ppDone")
    if follow is None:
        return True
    return follow < JULIA_FOLLOW_THROUGH_MS


def julia_was_quick(record: dict) -> bool:
    choice = julia_choice_ms(record)
    return julia_fired(record) and choice is not None and choice <= JULIA_QUICK_CHOICE_MS


def report_julia(records: list[dict], window: list[dict]) -> None:
    fired = [record for record in records if julia_fired(record)]
    quick = [record for record in fired if julia_was_quick(record)]
    recent_fired = [record for record in window if julia_fired(record)]
    recent_quick = [record for record in recent_fired if julia_was_quick(record)]

    print("\nJulia pastes")
    print(
        f"  fired {len(fired)} of {len(records)} traces"
        f" ({len(recent_fired)} in this window);"
        f" quick choice ≤{JULIA_QUICK_CHOICE_MS:.0f} ms: {len(quick)}"
        f" ({len(recent_quick)} in this window)"
    )
    if not fired:
        print("  no trace where Julia pasted instead of Groq")
        return

    rows = [
        ("Julia choice", [v for record in quick if (v := julia_choice_ms(record)) is not None]),
        ("Release → paste, Julia quick", [v for record in quick if (v := span_ms(record, "holdDeactivated", "pastePosted")) is not None]),
        ("Fn → first audio, Julia quick", [v for record in quick if (v := span_ms(record, "holdActivated", "firstBuffer")) is not None]),
        ("Release → paste, Julia fired", [v for record in fired if (v := span_ms(record, "holdDeactivated", "pastePosted")) is not None]),
    ]
    print_table("When Julia fired and was quick (ms)", rows)

    shown = list(reversed(quick[-5:] or fired[-5:]))
    label = "Last quick Julia pastes" if quick else "Last Julia pastes (none were ≤50 ms)"
    print(f"\n{label}")
    for record in shown:
        choice = julia_choice_ms(record)
        paste = span_ms(record, "holdDeactivated", "pastePosted")
        print(f"  choice {fmt(choice)} ms   release→paste {fmt(paste)} ms")


def julia_socket_paths() -> list[Path]:
    return [
        Path.home() / "Library/Application Support/KonradFlow Dev/julia-cleanup.sock",
        Path.home() / "Library/Application Support/KonradFlow/julia-cleanup.sock",
    ]


def probe_julia(repeats: int) -> None:
    print("\nJulia probe")
    sock_path = next((path for path in julia_socket_paths() if path.exists()), None)
    if sock_path is None:
        print("  helper socket not found — launch KonradFlow Dev so Julia is loaded, then re-run with --probe")
        return

    request = {
        "state": "they was happy yesterday",
        "question": "Which sentence is the cleaned dictation?",
        "options": ["they was happy yesterday", "they were happy yesterday"],
    }
    payload = (json.dumps(request) + "\n").encode("utf-8")
    samples: list[float] = []
    last_index = None
    last_top = None
    for _ in range(repeats):
        started = time.perf_counter()
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
                sock.settimeout(5)
                sock.connect(str(sock_path))
                sock.sendall(payload)
                data = b""
                while b"\n" not in data:
                    chunk = sock.recv(65536)
                    if not chunk:
                        break
                    data += chunk
        except OSError as error:
            print(f"  request failed: {error}")
            return
        samples.append((time.perf_counter() - started) * 1000)
        line = data.split(b"\n", 1)[0]
        try:
            body = json.loads(line.decode("utf-8"))
        except json.JSONDecodeError:
            body = {}
        last_index = body.get("index")
        probs = body.get("probabilities") or []
        last_top = max(probs) if probs else None

    print(f"  socket {sock_path}")
    print(
        f"  round trip  n={len(samples)} min={min(samples):.0f} med={median(samples):.0f} max={max(samples):.0f} ms"
    )
    if last_index is not None:
        top = f"{last_top:.2f}" if isinstance(last_top, float) else "—"
        print(f"  last choice index={last_index} top={top}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Stage-by-stage KonradFlow speed report")
    parser.add_argument("--last", type=int, default=8, help="How many recent traces to include")
    parser.add_argument("--probe", action="store_true", help="Also time a live Julia choice")
    parser.add_argument("--probe-repeats", type=int, default=5)
    parser.add_argument("--trace-file", type=Path, default=None)
    args = parser.parse_args()
    if args.last < 1:
        raise SystemExit("--last must be at least 1")

    path = args.trace_file or trace_file()
    records = load_records(path)
    report(records, args.last)
    if args.probe:
        probe_julia(args.probe_repeats)


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        sys.exit(0)
