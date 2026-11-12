#!/usr/bin/env bash
# Builds "Clipboard History.app" with SwiftPM (no Xcode project needed), signs it and zips it.
#
# Environment:
#   VERSION        version string (default: 0.0.0-dev)
#   SIGN_IDENTITY  codesign identity; "-" = ad-hoc (default). CI uses the self-signed cert.
#   KEYCHAIN       optional keychain holding SIGN_IDENTITY
#   UNIVERSAL      1 = arm64 + x86_64 (default), 0 = host architecture only (faster for dev)
#
# Output: build/Clipboard History.app and build/ClipboardHistory-$VERSION.zip
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.0.0-dev}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
UNIVERSAL="${UNIVERSAL:-1}"
BUNDLE_ID="com.jorgenbs.ClipboardHistory"
EXECUTABLE="ClipboardHistory"
APP="build/Clipboard History.app"
ZIP="build/ClipboardHistory-${VERSION}.zip"

rm -rf "$APP" "$ZIP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [[ "$UNIVERSAL" == "1" ]]; then
  binaries=()
  for arch in arm64 x86_64; do
    triple="${arch}-apple-macosx14.0"
    echo "==> Building $triple"
    swift build -c release --product "$EXECUTABLE" --triple "$triple"
    # Copy right away: some SwiftPM build backends share one output path across triples.
    cp "$(swift build -c release --triple "$triple" --show-bin-path)/$EXECUTABLE" "build/$EXECUTABLE-$arch"
    binaries+=("build/$EXECUTABLE-$arch")
  done
  lipo -create "${binaries[@]}" -output "$APP/Contents/MacOS/$EXECUTABLE"
else
  echo "==> Building host architecture"
  swift build -c release --product "$EXECUTABLE"
  cp "$(swift build -c release --show-bin-path)/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
fi

BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>${EXECUTABLE}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleName</key><string>Clipboard History</string>
  <key>CFBundleDisplayName</key><string>Clipboard History</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION#v}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Personal project by jorgenbs</string>
</dict>
</plist>
PLIST

if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

echo "==> Signing with identity: $SIGN_IDENTITY"
sign_args=(--force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" --timestamp=none)
if [[ -n "${KEYCHAIN:-}" ]]; then sign_args+=(--keychain "$KEYCHAIN"); fi
codesign "${sign_args[@]}" "$APP"
codesign --verify --strict --verbose=2 "$APP"
codesign -d -r- "$APP" 2>&1 | grep designated || true

echo "==> Zipping"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP"
echo "Built $APP"
