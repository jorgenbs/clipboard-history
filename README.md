# Clipboard History

A small macOS menu bar app for clipboard history, inspired by Alfred's clipboard feature.

- **⌥⌘C** (configurable) opens a floating overlay. The search field is focused, your clips are listed on the left, and a preview of the selected clip is on the right.
- Type to filter, use **↑/↓** to move, and press **Return** to paste into the app you were using.
- **⌘1–⌘9** paste a row directly. **⌘⌫** deletes the selected clip. **Esc** or a click outside closes the overlay.
- Records plain text, rich text, links and images (shown as `img`). File copies are skipped.
- **Never records** copies from sensitive apps (1Password, Proton Pass, Passwords, Keychain Access, …) or data marked as concealed, transient or auto-generated ([nspasteboard.org](http://nspasteboard.org) markers).
- Keeps the last 500 clips (configurable), stored in `~/Library/Application Support/ClipboardHistory`. Images over 10 MB are skipped.
- All settings live in the menu bar: shortcut, history size, ignored apps, launch at login, pause recording and clear history.

## Install

Both this repo and the tap are **private**: this is for my own Macs only, since a self-signed app with
Accessibility access isn't something to hand to others. That means:

- the tap is cloned over SSH (your normal GitHub SSH key), and
- the cask downloads the release zip through the GitHub API with `HOMEBREW_GITHUB_API_TOKEN`.

```sh
gh auth login                                   # once per machine, if needed
brew tap jorgenbs/tap git@github.com:jorgenbs/homebrew-tap.git
HOMEBREW_GITHUB_API_TOKEN=$(gh auth token) brew install --cask jorgenbs/tap/clipboard-history
open "/Applications/Clipboard History.app"
```

So `brew upgrade` works without thinking about it, export the token for brew only. In fish
(`~/.config/fish/conf.d/homebrew-github-token.fish`):

```fish
function brew --wraps brew
    HOMEBREW_GITHUB_API_TOKEN=(gh auth token 2>/dev/null) command brew $argv
end
```

Without the token the download fails with a 404 (GitHub hides private assets).

### First launch

1. **Gatekeeper.** The app is self-signed, not notarized. The cask removes the quarantine flag so it opens normally. If macOS still blocks it, go to System Settings › Privacy & Security and click **Open Anyway**.
2. **Accessibility (for auto-paste).** On first launch the app asks for Accessibility access. Turn it on under System Settings › Privacy & Security › Accessibility. Until then, Return copies the clip to your clipboard and you paste it yourself with ⌘V. The menu bar shows a warning item while access is missing.

### After upgrading

Releases are signed with the same self-signed certificate, so macOS normally keeps the Accessibility grant. If auto-paste stops working (the app is still listed and switched on, but nothing gets pasted), the grant is stale. Select the app in the Accessibility list, remove it with **–**, then add it again (or relaunch the app and accept the prompt).

## Known limitations

- **Passwords copied from browser extensions** (1Password or Proton Pass in the browser, Safari/Chrome password managers) are skipped only if the extension marks the copy as concealed. The frontmost app is the browser, so the ignored-apps list can't catch them. That marking is the extension's job.
- Only the first pasteboard item is recorded (multi-item copies are rare outside Finder).
- Proton Mail's bundle ID in the default ignore list (`ch.protonmail.desktop`) hasn't been verified. Check it with "Add Running App" in settings.

## Development

Needs Swift 6 (Command Line Tools are enough; Xcode isn't required).

```sh
swift test                               # unit tests (capture filter, store, search)
swift build && .build/debug/ClipboardHistory   # run unbundled (Accessibility won't stick)
UNIVERSAL=0 ./scripts/bundle.sh          # build/Clipboard History.app, ad-hoc signed
```

Useful while developing:

- `CLIPBOARD_HISTORY_DATA_DIR=/tmp/ch …` uses a scratch history instead of your real one.
- `--show` opens the overlay on launch.
- Debug builds only: `--snapshot out.png [--dark] [--query text] [--select n]` renders the overlay to a PNG and exits.
- `swift scripts/make-icon.swift` regenerates `Resources/AppIcon.icns`.

Layout:

| Path | What |
| --- | --- |
| `Sources/ClipboardCore` | AppKit-free logic: `CaptureFilter`, `ClipFactory`, `ClipStore`, `ClipSearch` |
| `Sources/ClipboardHistory` | The app: pasteboard monitor, hotkey, overlay panel, paste, menu bar, settings |
| `scripts/` | Bundling, signing-cert and cask helpers |

## Releasing

### One-time setup

Already done for `jorgenbs/clipboard-history` and `jorgenbs/homebrew-tap` (both private). For reference:

1. **Repos.** `jorgenbs/clipboard-history` (this repo) and `jorgenbs/homebrew-tap` (with a `Casks/` folder), both private.
2. **Tap deploy key.** CI pushes cask updates with a write-enabled deploy key that only works on the tap:
   ```sh
   ssh-keygen -t ed25519 -N "" -C "clipboard-history release" -f /tmp/tap_key
   gh repo deploy-key add /tmp/tap_key.pub -R jorgenbs/homebrew-tap --allow-write -t "clipboard-history release"
   gh secret set TAP_DEPLOY_KEY -R jorgenbs/clipboard-history < /tmp/tap_key && rm /tmp/tap_key*
   ```
   Without it, releases still work: the workflow prints the updated cask in the job summary for you to commit by hand.
3. **Signing certificate.** Create it and store it as Actions secrets on this repo:
   ```sh
   ./scripts/create-signing-cert.sh --set-secrets
   ```
   This writes `signing/` (gitignored). Back up `signing/ClipboardHistory.p12` and `signing/password.txt` (for example in 1Password). Losing them means a new certificate, which means re-granting Accessibility once.

### Each release

```sh
git tag v0.1.0 && git push origin v0.1.0
```

The `Release` workflow runs the tests, builds a universal (arm64 + x86_64) app, signs it, publishes `ClipboardHistory-<version>.zip` to GitHub Releases, and updates `Casks/clipboard-history.rb` in the tap with the asset's API URL and checksum. Then `brew update && brew upgrade --cask clipboard-history` picks it up.

The `CI` workflow only runs on pull requests or by hand (`gh workflow run CI`), because macOS runner minutes count 10x against the private-repo quota.
