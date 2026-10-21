#!/usr/bin/env bash
# Preview all dictation sound options. Usage:
#   ./Scripts/preview-dictation-sounds.sh          # play all 20 in order
#   ./Scripts/preview-dictation-sounds.sh 7        # play option 07 only
#   ./Scripts/preview-dictation-sounds.sh 7 12 19  # play selected options

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/Resources/Sounds/options"

declare -a LABELS=(
  "01 — Flow Ping (current default style, medium-high ping)"
  "02 — Bright Tink (sharp, high, macOS-like)"
  "03 — Warm Bell (rounded bell tone, longer tail)"
  "04 — Soft Glass (bright but gentle)"
  "05 — Deep Gong (lowest, slow decay)"
  "06 — Mid Chime (balanced mid-range chime)"
  "07 — Crisp Snap (short, snappy click)"
  "08 — Lounge Pop (muted, warm mid-low)"
  "09 — Hero Rise (pitch rises on start)"
  "10 — Submarine Soft (deep macOS-submarine feel)"
  "11 — Crystal Drop (high start, drops down)"
  "12 — Double Tap (two quick pings)"
  "13 — Funk Bump (bouncy low-mid thump)"
  "14 — Purr Start (soft, velvety)"
  "15 — Morse Tick (very short high tick)"
  "16 — Bottle Pop (pop with downward glide)"
  "17 — Smooth Whoosh (sweeping pitch down)"
  "18 — Basso Lite (soft low tone, not as deep as gong)"
  "19 — Golden Ping (warm upper-mid ping)"
  "20 — Whisper Flow (Wispr-inspired balanced ping)"
)

play_one() {
  local n="$1"
  local num
  num=$(printf "%02d" "$n")
  local file
  file=$(ls "$DIR"/${num}-*.wav 2>/dev/null | head -1)
  if [[ -z "$file" ]]; then
    echo "No sound for option $n" >&2
    return 1
  fi
  echo ""
  echo "▶ ${LABELS[$((n - 1))]}"
  afplay "$file"
}

if [[ $# -eq 0 ]]; then
  echo "Playing all 20 dictation start sounds (press Ctrl+C to stop)..."
  for i in $(seq 1 20); do
    play_one "$i"
    sleep 0.4
  done
  echo ""
  echo "Done. Reply with the number(s) you like (e.g. 19 or 6 and 19)."
else
  for arg in "$@"; do
    play_one "$arg"
  done
fi
