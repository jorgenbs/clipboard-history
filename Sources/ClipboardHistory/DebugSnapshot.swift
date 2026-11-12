#if DEBUG
import AppKit
import ClipboardCore
import SwiftUI

/// Debug-only: `ClipboardHistory --snapshot out.png` renders the overlay offscreen and exits.
/// Handy for checking layout without a display (e.g. over SSH or with the screen locked).
enum DebugSnapshot {
    static func runIfRequested(store: ClipStore, settings: Settings) {
        let args = CommandLine.arguments
        if args.contains("--demo") { seedDemo(into: store) }
        if let i = args.firstIndex(of: "--snapshot-settings"), args.indices.contains(i + 1) {
            let view = NSHostingView(rootView: SettingsView(settings: settings, state: SettingsViewState()) { _ in })
            render(view, size: view.fittingSize, to: args[i + 1], dark: args.contains("--dark"))
        }
        guard let i = args.firstIndex(of: "--snapshot"), args.indices.contains(i + 1) else { return }
        let model = OverlayModel(store: store)
        model.reset()
        if let q = args.firstIndex(of: "--query"), args.indices.contains(q + 1) { model.query = args[q + 1] }
        if let s = args.firstIndex(of: "--select"), args.indices.contains(s + 1), let n = Int(args[s + 1]) { model.move(by: n) }

        let view = NSHostingView(rootView: OverlayView(model: model)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12)))
        render(view, size: OverlayController.size, to: args[i + 1], dark: args.contains("--dark"))
    }

    /// Fills the store with sample clips for screenshots (never touches the real pasteboard).
    private static func seedDemo(into store: ClipStore) {
        store.clear()
        func text(_ s: String, _ app: String, _ name: String, rtf: Bool = false) {
            var reps: [(type: String, data: Data)] = [(PBType.plainText, Data(s.utf8))]
            if rtf {
                let a = NSMutableAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: 13)])
                let firstLine = (s as NSString).lineRange(for: NSRange(location: 0, length: 0))
                a.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 17), range: firstLine)
                if let data = try? a.data(from: NSRange(location: 0, length: a.length),
                                          documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
                    reps.append((PBType.rtf, data))
                }
            }
            if let clip = ClipFactory.make(representations: reps, source: SourceApp(bundleID: app, name: name)) {
                store.add(clip)
            }
        }
        // Gradient "screenshot".
        let image = NSImage(size: NSSize(width: 1440, height: 900), flipped: false) { rect in
            NSGradient(colors: [.systemIndigo, .systemPurple, .systemPink])!.draw(in: rect, angle: 30)
            return true
        }
        if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]),
           var clip = ClipFactory.make(representations: [(PBType.png, png)], source: SourceApp(bundleID: "com.apple.Preview", name: "Preview")) {
            clip.pixelWidth = 1440
            clip.pixelHeight = 900
            clip.thumbnail = image.pngThumbnail(maxPixels: 96)
            store.add(clip)
        }
        text("Sprint review\nShipped: clipboard history overlay, ignored apps, auto-paste.\nNext: release via Homebrew tap.\n\nAction items\n• Write the README\n• Tag v0.1.0", "notion.id", "Notion", rtf: true)
        text("https://developer.apple.com/documentation/appkit/nspasteboard", "com.apple.Safari", "Safari")
        text("brew install --cask jorgenbs/tap/clipboard-history", "com.mitchellh.ghostty", "Ghostty")
        text("Can you review the release PR when you get a chance?", "com.tinyspeck.slackmacgap", "Slack")
        text("""
        func decide(types: [String], sourceBundleIDs: [String]) -> CaptureDecision {
            if let marker = PBType.sensitiveMarkers.first(where: types.contains) {
                return .skip(.sensitiveMarker(marker))
            }
            if let ignored = sourceBundleIDs.first(where: ignoredBundleIDs.contains) {
                return .skip(.ignoredApp(ignored))
            }
            // …
        }
        """, "com.microsoft.VSCode", "Code")
        text("git log --oneline --graph --decorate", "com.mitchellh.ghostty", "Ghostty")
    }

    private static func render(_ view: NSView, size: NSSize, to path: String, dark: Bool) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        view.appearance = appearance
        view.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        // Render at 2x for crisp README images.
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { exit(1) }
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        exit(0)
    }
}
#endif
