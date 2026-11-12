#!/usr/bin/env bash
# Prints the Homebrew cask for a release:
#   scripts/render-cask.sh <version> <sha256> <asset-api-url>
#
# The source repo is private, so the cask downloads the release asset through the GitHub API
# (https://api.github.com/repos/<owner>/<repo>/releases/assets/<id>) with the token in
# HOMEBREW_GITHUB_API_TOKEN. Homebrew passes HOMEBREW_* variables through to casks.
set -euo pipefail
VERSION="${1:?version, e.g. 0.1.0}"
SHA256="${2:?sha256 of the release zip}"
ASSET_URL="${3:?GitHub API URL of the release asset}"
VERSION="${VERSION#v}"

cat <<CASK
cask "clipboard-history" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "${ASSET_URL}",
      header: [
        "Accept: application/octet-stream",
        "Authorization: Bearer #{ENV.fetch("HOMEBREW_GITHUB_API_TOKEN", "")}",
      ]
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

    Installing and upgrading need HOMEBREW_GITHUB_API_TOKEN set to a token that can read
    jorgenbs/clipboard-history, for example: HOMEBREW_GITHUB_API_TOKEN=\$(gh auth token) brew upgrade

    Auto-paste needs Accessibility access:
      System Settings › Privacy & Security › Accessibility › enable "Clipboard History"

    If auto-paste stops working after an upgrade, remove the app from that list (–) and add it again.
    After upgrading, start the app again from /Applications (or enable "Launch at login" in its settings).
  EOS
end
CASK
