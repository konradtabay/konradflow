#!/usr/bin/env bash
# Apply benchmark-proven low-latency settings to KonradFlow Dev.
# Restart KonradFlow Dev after running so AppState picks up UserDefaults.
set -euo pipefail

DOMAIN="${KONRADFLOW_DEFAULTS_DOMAIN:-com.konradtabay.konradflow.dev}"
TIER="${1:-fast}"

case "${TIER}" in
  fast)
    # Proven in replay: turbo STT + skip smart context. Keeps LLM cleanup.
    defaults write "${DOMAIN}" transcription_model -string "whisper-large-v3-turbo"
    defaults write "${DOMAIN}" fast_dictation_context_enabled -bool true
    defaults write "${DOMAIN}" fast_post_processing_enabled -bool false
    defaults write "${DOMAIN}" preserve_exact_wording -bool false
    defaults write "${DOMAIN}" realtime_streaming_enabled -bool false
    ;;
  fastest)
    # Maximum speed: turbo STT, no context LLM, no cleanup LLM.
    defaults write "${DOMAIN}" transcription_model -string "whisper-large-v3-turbo"
    defaults write "${DOMAIN}" fast_dictation_context_enabled -bool true
    defaults write "${DOMAIN}" fast_post_processing_enabled -bool false
    defaults write "${DOMAIN}" preserve_exact_wording -bool true
    defaults write "${DOMAIN}" realtime_streaming_enabled -bool false
    ;;
  *)
    echo "Usage: $0 [fast|fastest]" >&2
    echo "  fast     — turbo STT + skip smart context (recommended)" >&2
    echo "  fastest  — fast + skip cleanup LLM (verbatim paste)" >&2
    exit 1
    ;;
esac

echo "Applied '${TIER}' preset to ${DOMAIN}:"
defaults read "${DOMAIN}" transcription_model 2>/dev/null || true
defaults read "${DOMAIN}" fast_dictation_context_enabled 2>/dev/null || true
defaults read "${DOMAIN}" preserve_exact_wording 2>/dev/null || true
echo ""
echo "Quit and reopen KonradFlow Dev to load these settings."
