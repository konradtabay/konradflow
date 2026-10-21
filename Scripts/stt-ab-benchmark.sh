#!/usr/bin/env bash
set -euo pipefail

# A/B batch transcription latency for fixed WAV fixtures against Groq.
# Usage:
#   GROQ_API_KEY=... Scripts/stt-ab-benchmark.sh clip-a.wav [clip-b.wav ...]

if [[ -z "${GROQ_API_KEY:-}" ]]; then
  echo "Set GROQ_API_KEY to run STT A/B benchmarks." >&2
  exit 1
fi

if [[ "$#" -lt 1 ]]; then
  echo "Usage: GROQ_API_KEY=... $0 file.wav [more.wav ...]" >&2
  exit 1
fi

BASE_URL="${GROQ_BASE_URL:-https://api.groq.com/openai/v1}"
MODELS=("whisper-large-v3" "whisper-large-v3-turbo")
FORMATS=("verbose_json" "json")

for wav in "$@"; do
  echo "=== ${wav} ==="
  for model in "${MODELS[@]}"; do
    for format in "${FORMATS[@]}"; do
      if [[ "${format}" == "verbose_json" && "${model}" != whisper-large-v3* ]]; then
        continue
      fi
      start_ms=$(python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
)
      response="$(curl -sS -o /tmp/konradflow-stt-ab.json -w "%{http_code}" \
        -X POST "${BASE_URL}/audio/transcriptions" \
        -H "Authorization: Bearer ${GROQ_API_KEY}" \
        -F "file=@${wav}" \
        -F "model=${model}" \
        -F "response_format=${format}")"
      end_ms=$(python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
)
      elapsed=$((end_ms - start_ms))
      echo "model=${model} format=${format} http=${response} elapsed_ms=${elapsed}"
    done
  done
done
