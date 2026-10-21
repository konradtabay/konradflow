#!/usr/bin/env bash
set -euo pipefail

# Enables Paste Light dev settings (threshold still 1.0 until fit script runs).
defaults write com.konradtabay.konradflow.dev paste_light_enabled -bool true
defaults write com.konradtabay.konradflow.dev realtime_streaming_enabled -bool true
# Dev-only: allow Julia paste before offline quality gate (replace after fit-julia-paste-light-threshold.py).
defaults write com.konradtabay.konradflow.dev julia_confidence_threshold -float 0.85
echo "Paste Light preset applied for KonradFlow Dev (paste_light_enabled, realtime_streaming_enabled, julia threshold 0.85 for testing)."
