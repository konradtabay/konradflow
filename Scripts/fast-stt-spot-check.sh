#!/usr/bin/env bash
# Quick STT spot-check: whisper-large-v3 vs turbo on a few Dev session clips.
set -euo pipefail

AUDIO_DIR="${HOME}/Library/Application Support/KonradFlow Dev/audio"
SETTINGS="${HOME}/Library/Application Support/KonradFlow/.settings"
BASE_URL="${GROQ_BASE_URL:-https://api.groq.com/openai/v1}"

if [[ -z "${GROQ_API_KEY:-}" ]]; then
  GROQ_API_KEY="$(python3 -c "import json; print(json.load(open('${SETTINGS}')).get('groq_api_key','').strip())")"
fi
[[ -n "${GROQ_API_KEY}" ]] || { echo "Missing Groq API key" >&2; exit 1; }

WAVS=()
while IFS= read -r line; do
  WAVS+=("$line")
done < <(python3 - <<'PY'
from pathlib import Path
audio = Path.home() / "Library/Application Support/KonradFlow Dev/audio"
clips = sorted(audio.glob("*.wav"), key=lambda p: p.stat().st_size)
for p in clips[-5:]:
    print(p)
PY
)
MODELS=(whisper-large-v3 whisper-large-v3-turbo)

echo "STT spot-check ($(date +%Y-%m-%d)) — 5 clips, json format"
for wav in "${WAVS[@]}"; do
  name="$(basename "${wav}")"
  size=$(( $(stat -f%z "${wav}") / 1024 ))
  echo ""
  echo "=== ${name} (${size} KB) ==="
  for model in "${MODELS[@]}"; do
    start_ms=$(python3 - <<PY
import time
print(int(time.time() * 1000))
PY
)
    http=$(curl -sS -o /tmp/stt-out.json -w "%{http_code}" -X POST "${BASE_URL}/audio/transcriptions" \
      -H "Authorization: Bearer ${GROQ_API_KEY}" \
      -F "model=${model}" \
      -F "response_format=json" \
      -F "file=@${wav}")
    end_ms=$(python3 - <<PY
import time
print(int(time.time() * 1000))
PY
)
    ms=$(( end_ms - start_ms ))
    if [[ "${http}" == "200" ]]; then
      chars=$(python3 -c "import json; print(len(json.load(open('/tmp/stt-out.json')).get('text','')))")
      echo "  ${model}: ${ms} ms (${chars} chars)"
    else
      echo "  ${model}: HTTP ${http} (${ms} ms)"
    fi
    sleep 2
  done
done
