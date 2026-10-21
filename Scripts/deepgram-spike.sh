#!/usr/bin/env bash
set -euo pipefail

# Optional spike script for Deepgram Nova-3 streaming latency.
# Requires DEEPGRAM_API_KEY and a mono 16kHz/24kHz WAV fixture.

if [[ -z "${DEEPGRAM_API_KEY:-}" ]]; then
  echo "Set DEEPGRAM_API_KEY to run the Deepgram spike." >&2
  exit 0
fi

AUDIO_FILE="${1:-}"
if [[ -z "${AUDIO_FILE}" || ! -f "${AUDIO_FILE}" ]]; then
  echo "Usage: DEEPGRAM_API_KEY=... $0 /path/to/fixture.wav" >&2
  exit 1
fi

echo "Deepgram spike is documented-only in this repo."
echo "Compare OpenAI Realtime (U5) against batch Groq before integrating a new vendor."
echo "Fixture: ${AUDIO_FILE}"
