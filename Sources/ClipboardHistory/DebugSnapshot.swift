#if DEBUG
import AppKit
import ClipboardCore
import SwiftUI

/// Debug-only: `ClipboardHistory --snapshot out.png` renders the overlay offscreen and exits.
/// Handy for checking layout without a display (e.g. over SSH or with the screen locked).
enum DebugSnapshot {
    static func runIfRequested(store: ClipStore, settings: Settings) {
        let args = CommandLine.arguments
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
            .background(Color(nsColor: .windowBackgroundColor)))
        render(view, size: OverlayController.size, to: args[i + 1], dark: args.contains("--dark"))
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
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        exit(0)
    }
}
#endif
