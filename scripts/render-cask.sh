#!/usr/bin/env bash
# Prints the Homebrew cask for a release: scripts/render-cask.sh <version> <sha256>
set -euo pipefail
VERSION="${1:?version, e.g. 0.1.0}"
SHA256="${2:?sha256 of the release zip}"
VERSION="${VERSION#v}"

cat <<CASK
cask "clipboard-history" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "https://github.com/jorgenbs/clipboard-history/releases/download/v#{version}/ClipboardHistory-#{version}.zip"
  name "Clipboard History"
  desc "Menu bar clipboard history with search, preview and auto-paste"
  homepage "https://github.com/jorgenbs/clipboard-history"

  depends_on macos: :sonoma

  app "Clipboard History.app"

  # The app is self-signed, not notarized. Removing the quarantine flag lets it open without
  # a Gatekeeper prompt. Only do this for apps you trust (this one is built by your own CI).
  postflight_steps do
    run "/usr/bin/xattr",
        args:           ["-dr", "com.apple.quarantine", "{{appdir}}/Clipboard History.app"],
        writable_paths: ["Clipboard History.app"],
        writable_base:  :appdir,
        must_succeed:   false
  end

  uninstall quit: "com.jorgenbs.ClipboardHistory"

  zap trash: [
    "~/Library/Application Support/ClipboardHistory",
    "~/Library/Preferences/com.jorgenbs.ClipboardHistory.plist",
  ]

  caveats <<~EOS
    Clipboard History lives in the menu bar. Open it with ⌥⌘C.

    Auto-paste needs Accessibility access:
      System Settings › Privacy & Security › Accessibility › enable "Clipboard History"

    If auto-paste stops working after an upgrade, remove the app from that list (–) and add it again.
    After upgrading, start the app again from /Applications (or enable "Launch at login" in its settings).
  EOS
end
CASK
