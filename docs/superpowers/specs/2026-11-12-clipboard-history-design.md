# Clipboard History — Design

Date: 2026-11-12
Status: draft for approval (builder check done)

## Intent

A personal clipboard history app for macOS, modeled on Alfred's clipboard history feature. It's for the author's own use. Part of the motivation is learning, specifically how to ship a native app through a personal Homebrew tap. It should feel instant and stay out of the way. Copy as usual, press a hotkey, find the clip, press Return, and it's pasted.

## Goals

- Record clipboard history: plain text, rich text, URLs and images. Skip files.
- Open a small overlay on a global hotkey (default ⌥⌘C) with the search field focused.
- Two-column overlay: search field and clip list on the left, a preview of the selected clip on the right.
- Return pastes the selected clip into the app that was frontmost before the overlay opened.
- Never record anything from sensitive apps, or anything marked as concealed or auto-generated.
- Configure everything from the menu bar.
- Install with `brew install --cask <user>/tap/clipboard-history`, with releases built by CI.

## Non-goals

- Recording files or file references copied from Finder.
- iCloud or cross-device sync.
- Snippets or text expansion, pinned or favorite clips, merging clips.
- Notarization or a paid Apple Developer account. The app is ad-hoc signed only.
- Distribution to other people. The README can assume a technical user.
- Catching passwords copied from browser extensions or browser password managers (1Password/Proton Pass extensions, Safari/Chrome passwords). In that case the frontmost app is the browser, so the app relies only on the concealed/transient markers below. Marking secrets is the extension's responsibility. A leak would show up in the system clipboard anyway. The README notes this gap.

## Anti-goals (a failure even if it technically works)

- A password or secret ends up in history because it came from a password manager or was marked concealed.
- The overlay feels slow: noticeable lag before it appears, or input lag while typing to search.
- Return pastes into the wrong app, or doesn't paste and leaves the user guessing.
- The app shows a Dock icon or takes focus in a way that breaks the user's flow.

## Constraints

- **No paid Apple Developer account, so no notarization.** *(my call)* The app is signed with a free **self-signed code-signing certificate**. It's generated once and stored as a CI secret (base64 .p12 plus password), then imported into a temporary keychain in CI. Every release is signed with the same identity, so the code's designated requirement stays stable and the Accessibility and launch-at-login grants should survive upgrades. Local dev builds may fall back to ad-hoc (`codesign -s -`). Consequences, all to be documented in the README:
  - After install, Gatekeeper blocks the first launch. The user approves it once in System Settings › Privacy & Security, or the cask's `postflight` strips the quarantine attribute (see below).
  - If the Accessibility grant still breaks (for example after the certificate changes), the stale System Settings entry can still look enabled while it doesn't work. The README explains how to remove it and re-add the app. The app detects missing permission and guides the user (see Pasting).
  - The plan includes a one-time script that generates the certificate and prints the values to put in the GitHub secrets.
- **The dev machine has Swift 6.4 command-line tools but no full Xcode install.** The project must build with SwiftPM (`swift build`) plus a script that assembles the `.app` bundle (Info.plist, icon, signing). There should be no dependency on an `.xcodeproj`. CI (GitHub Actions macOS runners) uses the same script.
- **Minimum macOS: 14 (Sonoma).** (my call: modern SwiftUI and SwiftData APIs without hacks. The user runs macOS 27.)
- Menu-bar-only app: `LSUIElement = YES`, no Dock icon.

## What the user decided

### Capture

- Recorded types: plain text, rich text (RTF/HTML, kept so paste preserves formatting), URLs, images (PNG/TIFF).
- **Files are skipped.** *(my call on the exact rule)* Any copy that contains `public.file-url` is skipped. That includes Finder copies, which also carry the file name as text and an icon image. **Exception:** when the source app is *not* Finder and the copy also carries real image data (Preview, Photos, screenshot tools), it's recorded as an image and the file reference is dropped.
- In the list, images are labeled "img".
- **Ignored apps** (by bundle ID, checked against the frontmost app at copy time). Defaults:
  - 1Password (`com.1password.1password`, `com.agilebits.onepassword7`)
  - Proton Pass (`me.proton.pass.electron`) and other Proton apps where they apply
  - Passwords (`com.apple.Passwords`)
  - Wallet (`com.apple.Passbook`, if present on macOS)
  - Keychain Access (`com.apple.keychainaccess`)
  - The builder should verify the exact bundle IDs on a real system and correct this list.
- Users can add and remove ignored apps from the menu bar (pick from running apps or choose a `.app`).
- **Concealed or auto-generated data is never recorded.** If the pasteboard contains any of these types, the copy is skipped:
  - `org.nspasteboard.ConcealedType`
  - `org.nspasteboard.TransientType`
  - `org.nspasteboard.AutoGeneratedType`
  - `com.agilebits.onepassword` (legacy 1Password marker)
  - (`com.apple.is-remote-clipboard` is not a sensitive marker. Universal Clipboard content is recorded normally.)

### Overlay

- About 750×450, floating above all windows, centered on the screen with the active window. It doesn't activate the app in a way that shows a Dock icon. It's a non-activating `NSPanel` that still takes key focus for typing.
- **Left column:** search field (focused on open) above a list of clips, newest first. Each row shows the first line, truncated, plus the source app icon and a relative time ("3m", "2h", "Yesterday"). Image rows show "img" and a small thumbnail.
- **Right column:** preview of the selected clip. Long text appears in full and scrolls. Rich text renders with formatting. Images are scaled to fit. A footer shows the source app, copy time and size (character count, or pixel dimensions and file size).
- **Keys:**
  - Typing filters the list live (case-insensitive substring match on the text content. Image clips match on "img" and the source app name).
  - ↑/↓ moves the selection and the preview follows.
  - Return pastes the selected clip.
  - ⌘1–⌘9 paste the clip in that row.
  - ⌘⌫ deletes the selected clip from history.
  - Esc, or a click outside the panel, closes without pasting.
- Opening the overlay always resets it: empty search, first row selected.

### Pasting

1. Write the clip back to the general pasteboard with all its stored representations.
2. Close the overlay and reactivate the app that was frontmost before it opened.
3. After a short delay for focus to settle, send ⌘V with `CGEvent`.
4. Move the pasted clip to the top of the history. Don't create a duplicate entry. The app's own write to the pasteboard must not be recorded as a new copy.

If Accessibility permission is missing, step 3 can't work. In that case the clip is still put on the clipboard, and the app shows a one-time prompt explaining how to grant Accessibility, with a button that opens the right System Settings pane. The menu bar shows a warning item while permission is missing.

### History and retention

- Keep the last **500** clips by default. The limit can be changed from the menu bar (100 / 500 / 1000 / 5000 are enough options).
- Stored on disk under `~/Library/Application Support/ClipboardHistory/`, so history survives restarts and reboots.
- Images larger than about **10 MB** are skipped.
- Duplicates: copying something identical to an existing clip moves that clip to the top instead of adding a new one (match on a content hash).
- A **Clear History** menu item, with a confirmation.

### Menu bar

The menu bar icon opens a menu with:

- Open Clipboard History (shows the current hotkey)
- Pause recording (toggle)
- Settings… opens a small settings window with:
  - Hotkey recorder (default ⌥⌘C)
  - History size
  - Ignored apps list (add/remove)
  - Launch at login (via `SMAppService`)
- Accessibility status/warning item (only shown when permission is missing)
- Clear History…
- About / version
- Quit

### Distribution

> **Update 2026-11-12 (user decision):** both repos are **private**. The app is self-signed and
> needs Accessibility, so it's meant only for the author's own Macs. The tap is cloned over SSH.
> The cask downloads the release asset through the GitHub API URL with
> `Authorization: Bearer $HOMEBREW_GITHUB_API_TOKEN`. CI updates the tap with a write deploy key
> (`TAP_DEPLOY_KEY`) instead of a personal token. Where the text below says "public", this update
> takes precedence.

- Source lives in this repo and will be pushed to a **public** GitHub repo `jorgenbs/clipboard-history`.
- The tap is a **public** repo `jorgenbs/homebrew-tap`. **It doesn't exist yet.** The plan includes creating it (with a README and `Casks/`), and the user is asked before anything is created on GitHub. Install command: `brew install --cask jorgenbs/tap/clipboard-history`.
- Bundle ID: `com.jorgenbs.ClipboardHistory` (my call).
- When a `v*` tag is pushed, GitHub Actions does the following:
  1. Build a release binary with SwiftPM (universal arm64 + x86_64).
  2. Assemble `Clipboard History.app` and ad-hoc sign it.
  3. Zip it and attach it to a GitHub Release.
  4. Update the cask in `jorgenbs/homebrew-tap` with the new version and sha256, using a fine-grained token secret with write access to the tap only. If the token isn't configured, print the values for a manual update.
- Cask: `Casks/clipboard-history.rb` in `jorgenbs/homebrew-tap`. Includes `depends_on macos: ">= :sonoma"`, a `zap` stanza for the Application Support folder and preferences, and a `caveats` block explaining the Gatekeeper and Accessibility steps. Homebrew has removed `--no-quarantine`, so either the cask strips quarantine in `postflight` or the README documents the System Settings approval. The builder picks whichever currently works and documents it.

## Left to the builder

- Internal architecture, module layout, how the pasteboard is polled (`changeCount` polling, about every 0.5 s, is the usual approach) and the storage engine. A JSON or SQLite index with image blobs on disk is fine. SwiftData is fine if it stays fast.
- Global hotkey implementation (Carbon `RegisterEventHotKey` or a small package like `KeyboardShortcuts`; a dependency is acceptable).
- Visual styling of the overlay. It should look native: vibrancy/material background, system fonts, rounded panel.
- App icon and menu bar glyph (an SF Symbol is fine).
- Test strategy. At minimum, unit tests for the capture filter (ignored apps, concealed types, file skipping), dedup and retention.
