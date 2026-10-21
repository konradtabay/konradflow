#!/usr/bin/env bash
# Print a codesign identity name if installed, otherwise "-" for ad-hoc.
set -euo pipefail
NAME="${1:-KonradFlow Dev}"
if security find-identity -v -p codesigning 2>/dev/null | grep -Fq " ${NAME}"; then
  printf '%s' "${NAME}"
else
  printf '%s' '-'
fi
