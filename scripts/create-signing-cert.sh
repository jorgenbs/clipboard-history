#!/usr/bin/env bash
# One-time: creates a self-signed code-signing certificate for release builds.
#
# Signing every release with the same certificate keeps the app's code identity stable, so macOS
# keeps the Accessibility and login-item grants across upgrades (ad-hoc signatures change on every build).
#
# Writes signing/ClipboardHistory.p12 (gitignored) and prints the two GitHub secrets to set:
#   MACOS_SIGNING_CERT_P12       base64 of the .p12
#   MACOS_SIGNING_CERT_PASSWORD  its password
# With --set-secrets it sets them on the current GitHub repo using `gh secret set`.
set -euo pipefail

cd "$(dirname "$0")/.."
NAME="Clipboard History Self-Signed"
OUT_DIR="signing"
P12="$OUT_DIR/ClipboardHistory.p12"
OPENSSL=/usr/bin/openssl   # LibreSSL: produces .p12 files the macOS keychain can import

if [[ -e "$P12" ]]; then
  echo "$P12 already exists. Delete it first if you really want a new certificate" >&2
  echo "(a new certificate means re-granting Accessibility once after the next upgrade)." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
CNF

PASSWORD="$("$OPENSSL" rand -base64 24 | tr -d '/+=' )"
"$OPENSSL" req -x509 -newkey rsa:3072 -sha256 -days 7300 -nodes \
  -config "$tmp/cert.cnf" -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
"$OPENSSL" pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$NAME" \
  -out "$P12" -passout "pass:$PASSWORD"
chmod 600 "$P12"
printf '%s' "$PASSWORD" > "$OUT_DIR/password.txt"
chmod 600 "$OUT_DIR/password.txt"

echo "Created $P12 (password in $OUT_DIR/password.txt). Keep both somewhere safe, e.g. your password manager."

if [[ "${1:-}" == "--set-secrets" ]]; then
  base64 -i "$P12" | gh secret set MACOS_SIGNING_CERT_P12
  printf '%s' "$PASSWORD" | gh secret set MACOS_SIGNING_CERT_PASSWORD
  echo "Set MACOS_SIGNING_CERT_P12 and MACOS_SIGNING_CERT_PASSWORD on $(gh repo view --json nameWithOwner -q .nameWithOwner)."
else
  echo
  echo "Set these GitHub Actions secrets on the clipboard-history repo:"
  echo "  base64 -i $P12 | gh secret set MACOS_SIGNING_CERT_P12"
  echo "  gh secret set MACOS_SIGNING_CERT_PASSWORD < $OUT_DIR/password.txt"
  echo "(or rerun with --set-secrets on a fresh certificate)"
fi
