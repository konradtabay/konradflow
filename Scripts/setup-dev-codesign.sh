#!/usr/bin/env bash
# Create a stable local codesign identity so macOS keeps Accessibility grants across rebuilds.
set -euo pipefail

CERT_NAME="${KONRADFLOW_DEV_CERT_NAME:-KonradFlow Dev}"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
TMPDIR="${TMPDIR:-/tmp}/konradflow-codesign-$$"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

if security find-identity -v -p codesigning 2>/dev/null | grep -Fq " ${CERT_NAME}"; then
  echo "Codesign identity already exists: ${CERT_NAME}"
  security find-identity -v -p codesigning | grep -F "${CERT_NAME}" || true
  exit 0
fi

echo "Creating self-signed codesign identity: ${CERT_NAME}"
openssl req -x509 -newkey rsa:2048 -days 825 \
  -keyout "${TMPDIR}/key.pem" -out "${TMPDIR}/cert.pem" -nodes \
  -subj "/CN=${CERT_NAME}/O=KonradFlow Dev/C=US"
openssl pkcs12 -export -out "${TMPDIR}/cert.p12" \
  -inkey "${TMPDIR}/key.pem" -in "${TMPDIR}/cert.pem" -passout pass:konradflow
security import "${TMPDIR}/cert.p12" -k "${KEYCHAIN}" -P konradflow -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "${KEYCHAIN}" 2>/dev/null || true

echo "Done. Rebuild with:"
echo "  cd /Applications/konradflow && make"
echo ""
echo "Then re-add KonradFlow Dev in System Settings > Accessibility ONCE (signature is now stable)."
