#!/usr/bin/env bash
# Enable OpenAI Realtime transcription on KonradFlow Dev (keeps Groq for cleanup).
# Requires OPENAI_API_KEY in the environment or as the first argument.
set -euo pipefail

DOMAIN="${KONRADFLOW_DEFAULTS_DOMAIN:-com.konradtabay.konradflow.dev}"
SETTINGS_DIR="${HOME}/Library/Application Support/KonradFlow Dev"
SETTINGS_FILE="${SETTINGS_DIR}/.settings"
REALTIME_MODEL="${REALTIME_MODEL:-gpt-realtime-whisper}"
OPENAI_BASE="https://api.openai.com/v1"

OPENAI_KEY="${OPENAI_API_KEY:-${1:-}}"
if [[ -z "${OPENAI_KEY}" ]]; then
  echo "Set OPENAI_API_KEY or pass your key as the first argument." >&2
  echo "Example: OPENAI_API_KEY=sk-... $0" >&2
  exit 1
fi

mkdir -p "${SETTINGS_DIR}"

python3 - "${SETTINGS_FILE}" "${OPENAI_KEY}" "${OPENAI_BASE}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
key = sys.argv[2].strip()
base_url = sys.argv[3].strip()
data = {}
if path.exists():
    data = json.loads(path.read_text(encoding="utf-8"))
data["transcription_api_key"] = key
data["transcription_api_url"] = base_url
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
path.chmod(0o600)
PY

defaults write "${DOMAIN}" transcription_api_url -string "${OPENAI_BASE}"
defaults write "${DOMAIN}" realtime_streaming_enabled -bool true
defaults write "${DOMAIN}" realtime_streaming_model -string "${REALTIME_MODEL}"
defaults write "${DOMAIN}" transcription_model -string "gpt-4o-mini-transcribe"
defaults write "${DOMAIN}" fast_dictation_context_enabled -bool true
defaults write "${DOMAIN}" fast_post_processing_enabled -bool false

echo "OpenAI Realtime preset applied to ${DOMAIN}:"
echo "  Transcription API URL: ${OPENAI_BASE}"
echo "  Realtime model:        ${REALTIME_MODEL}"
echo "  Fast dictation:        on"
echo "  Batch STT fallback:    gpt-4o-mini-transcribe (OpenAI)"
echo ""
echo "Groq API key unchanged — still used for post-processing cleanup."
echo "Quit and reopen KonradFlow Dev, then dictate to test."
