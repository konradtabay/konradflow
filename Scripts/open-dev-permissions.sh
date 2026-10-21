#!/usr/bin/env bash
# Open the privacy panes KonradFlow Dev needs and reveal the app in Finder.
set -euo pipefail

APP="/Applications/konradflow/build/KonradFlow Dev.app"
if [[ ! -d "${APP}" ]]; then
  echo "Build KonradFlow Dev first: cd /Applications/konradflow && make" >&2
  exit 1
fi

echo "Opening System Settings and revealing KonradFlow Dev in Finder..."
echo ""
echo "In each pane, enable **KonradFlow Dev** (not KonradFlow):"
echo "  1. Accessibility  — required to paste text"
echo "  2. Microphone     — required to record"
echo "  3. Screen Recording — optional if Fast dictation is on"
echo ""
echo "If KonradFlow Dev is already listed but still fails, remove it with −"
echo "then drag the app from Finder into the list again."
echo ""

open -R "${APP}"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
sleep 1
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
sleep 1
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
