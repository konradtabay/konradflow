#!/usr/bin/env python3
"""Resident Julia-1 choice helper for KonradFlow Paste Light."""

from __future__ import annotations

import json
import logging
import os
import socket
import sys
import time
from pathlib import Path

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("julia_cleanup_helper")

QUESTION = "Which sentence is the cleaned dictation?"
DEFAULT_SOCKET = Path.home() / "Library/Application Support/KonradFlow/julia-cleanup.sock"


def load_engine():
    model_path = os.environ.get("JULIA_MODEL_PATH", "Julia-1")
    from julia import load_model

    engine = load_model(
        model_path,
        device="cpu",
        strict_encoding=True,
        max_length=8192,
        head_length=512,
    )
    log.info("Julia model loaded from %s", model_path)
    return engine


def run_choice(engine, state: str, options: list[str]) -> dict:
    if len(options) < 2:
        return {"error": "need at least 2 options"}

    criteria = {f"opt{i}": opt for i, opt in enumerate(options)}
    t0 = time.perf_counter()
    result = engine.predict(
        state=state,
        questions={
            "pick": {
                "type": "choice",
                "instructions": QUESTION,
                "criteria": criteria,
            }
        },
    )
    elapsed_ms = (time.perf_counter() - t0) * 1000

    answer = result["answers"]["pick"]
    choice_key = answer["choice"]
    index = int(choice_key.replace("opt", "")) if choice_key.startswith("opt") else 0
    probabilities = answer.get("probabilities", {})
    prob_list = [float(probabilities.get(f"opt{i}", 0.0)) for i in range(len(options))]

    log.info("choice index=%d elapsed=%.1fms", index, elapsed_ms)
    return {
        "index": index,
        "probabilities": prob_list,
        "elapsed_ms": elapsed_ms,
    }


def handle_client(conn: socket.socket, engine) -> None:
    with conn:
        data = b""
        while True:
            chunk = conn.recv(65536)
            if not chunk:
                return
            data += chunk
            if b"\n" in data:
                line, _, rest = data.partition(b"\n")
                data = rest
                request = json.loads(line.decode("utf-8"))
                state = request.get("state", "")
                options = request.get("options") or []
                response = run_choice(engine, state, options)
                conn.sendall((json.dumps(response) + "\n").encode("utf-8"))


def main() -> int:
    socket_path = Path(os.environ.get("JULIA_SOCKET_PATH", str(DEFAULT_SOCKET)))
    socket_path.parent.mkdir(parents=True, exist_ok=True)
    if socket_path.exists():
        socket_path.unlink()

    engine = load_engine()

    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(str(socket_path))
    server.listen(5)
    log.info("listening on %s", socket_path)

    while True:
        conn, _ = server.accept()
        try:
            handle_client(conn, engine)
        except Exception as exc:
            log.exception("client error: %s", exc)
            try:
                conn.sendall((json.dumps({"error": str(exc)}) + "\n").encode("utf-8"))
            except OSError:
                pass

    return 0


if __name__ == "__main__":
    sys.exit(main())
