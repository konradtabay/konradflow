#!/usr/bin/env bash
# Maximum-speed preset: OpenAI realtime STT + fast dictation + Groq cleanup.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/apply-realtime-openai-preset.sh" "${OPENAI_API_KEY:-${1:-}}"

DOMAIN="${KONRADFLOW_DEFAULTS_DOMAIN:-com.konradtabay.konradflow.dev}"
defaults write "${DOMAIN}" fast_dictation_context_enabled -bool true
defaults write "${DOMAIN}" fast_post_processing_enabled -bool false
defaults write "${DOMAIN}" preserve_exact_wording -bool false

echo ""
echo "Max-speed preset applied. Restart KonradFlow Dev, dictate 10+ times, then:"
echo "  ${SCRIPT_DIR}/latency-benchmark.sh"
