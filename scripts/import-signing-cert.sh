#!/usr/bin/env bash
# CI helper: imports the self-signed certificate into a temporary keychain.
# Needs MACOS_SIGNING_CERT_P12 (base64) and MACOS_SIGNING_CERT_PASSWORD.
# Prints `KEYCHAIN=...` and `SIGN_IDENTITY=...` lines (append them to $GITHUB_ENV).
set -euo pipefail

KEYCHAIN="${KEYCHAIN_PATH:-${RUNNER_TEMP:-$(mktemp -d)}/clipboard-history-signing.keychain-db}"
KEYCHAIN_PASSWORD="$(uuidgen)"
P12_FILE="$(dirname "$KEYCHAIN")/signing-cert.p12"

printf '%s' "$MACOS_SIGNING_CERT_P12" | base64 --decode > "$P12_FILE"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >&2
security set-keychain-settings -lut 21600 "$KEYCHAIN" >&2
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >&2
security import "$P12_FILE" -k "$KEYCHAIN" -P "$MACOS_SIGNING_CERT_PASSWORD" -T /usr/bin/codesign >&2
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
rm -f "$P12_FILE"
# codesign looks up the private key through the keychain search list, so add ours to it.
existing=()
while IFS= read -r kc; do existing+=("$kc"); done < <(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"$//')
security list-keychains -d user -s "$KEYCHAIN" "${existing[@]}" >&2

# Self-signed certs aren't "valid" identities to `find-identity -v`, so sign by SHA-1 fingerprint.
IDENTITY="$(security find-certificate -a -Z "$KEYCHAIN" | awk '/SHA-1 hash:/ {print $NF; exit}')"
if [[ -z "$IDENTITY" ]]; then echo "No certificate found in imported .p12" >&2; exit 1; fi
echo "KEYCHAIN=$KEYCHAIN"
echo "SIGN_IDENTITY=$IDENTITY"
