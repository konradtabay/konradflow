#!/usr/bin/env python3
"""Fit Julia Paste Light confidence threshold from exported Groq pipeline history."""

from __future__ import annotations

import json
import os
import re
import socket
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLI_SOURCES = [
    ROOT / "Sources/EnglishConjugation.swift",
    ROOT / "Sources/PasteLightCandidateBuilder.swift",
    ROOT / "Scripts/paste_light_candidates_main.swift",
]
CLI_BINARY = ROOT / "build/paste-light-candidates"
OUTPUT_DEFAULT = Path.home() / "Library/Application Support/KonradFlow/paste-light-threshold.json"
SOCKET = Path.home() / "Library/Application Support/KonradFlow/julia-cleanup.sock"


def normalize(text: str) -> str:
    return re.sub(r"\s+", " ", text.strip().lower())


def comma_capital_equiv(a: str, b: str) -> bool:
    def squash(s: str) -> str:
        s = s.strip().lower()
        s = re.sub(r"[.,!?;:\-]", "", s)
        return re.sub(r"\s+", " ", s)

    return squash(a) == squash(b)


def build_cli() -> None:
    CLI_BINARY.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        "swiftc",
        "-parse-as-library",
        "-o",
        str(CLI_BINARY),
        "-sdk",
        subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip(),
        "-target",
        f"{subprocess.check_output(['uname', '-m'], text=True).strip()}-apple-macosx13.0",
        *[str(path) for path in CLI_SOURCES],
    ]
    subprocess.check_call(cmd)


def candidates_for(raw: str) -> list[str]:
    proc = subprocess.run(
        [str(CLI_BINARY)],
        input=raw + "\n",
        text=True,
        capture_output=True,
        check=True,
    )
    payload = json.loads(proc.stdout)
    return payload.get("candidates") or []


def julia_choice(state: str, options: list[str]) -> tuple[int, list[float]]:
    request = json.dumps({"state": state, "options": options}) + "\n"
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.connect(str(SOCKET))
        sock.sendall(request.encode("utf-8"))
        data = b""
        while b"\n" not in data:
            chunk = sock.recv(65536)
            if not chunk:
                break
            data += chunk
    line = data.split(b"\n", 1)[0]
    response = json.loads(line.decode("utf-8"))
    if "error" in response:
        raise RuntimeError(response["error"])
    index = int(response.get("index", -1))
    probs = [float(p) for p in response.get("probabilities") or []]
    return index, probs


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: fit-julia-paste-light-threshold.py <production-history.json> [output.json]", file=sys.stderr)
        return 1

    history_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2]) if len(sys.argv) > 2 else OUTPUT_DEFAULT

    if not history_path.is_file():
        print(f"Missing history export: {history_path}", file=sys.stderr)
        return 1
    if not SOCKET.exists():
        print(f"Julia helper socket not found: {SOCKET}. Start KonradFlow or julia_cleanup_helper.py first.", file=sys.stderr)
        return 1

    build_cli()
    history = json.loads(history_path.read_text(encoding="utf-8"))
    entries = history.get("entries") or history

    mismatch_top_probs: list[float] = []
    evaluated = 0
    accepted = 0

    for entry in entries:
        raw = (entry.get("raw_transcript") or entry.get("rawTranscript") or "").strip()
        groq = (entry.get("post_processed_transcript") or entry.get("postProcessedTranscript") or "").strip()
        if not raw or not groq:
            continue
        options = candidates_for(raw)
        if len(options) < 2:
            continue
        index, probs = julia_choice(raw, options)
        evaluated += 1
        pick = options[index] if 0 <= index < len(options) else ""
        top = max(probs) if probs else 0.0
        ok = normalize(pick) == normalize(groq) or comma_capital_equiv(pick, groq)
        if ok:
            accepted += 1
        else:
            mismatch_top_probs.append(top)
            print(f"MISMATCH top={top:.3f}\n  julia: {pick}\n  groq:  {groq}", file=sys.stderr)

    threshold = 1.0 if not mismatch_top_probs else min(1.0, max(mismatch_top_probs) + 0.001)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "threshold": threshold,
        "evaluated": evaluated,
        "accepted": accepted,
        "mismatch_count": len(mismatch_top_probs),
    }
    output_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
