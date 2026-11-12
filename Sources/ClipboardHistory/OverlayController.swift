import AppKit
import ClipboardCore
import SwiftUI

/// Borderless floating panel that can take keyboard focus without activating the app,
/// so the previously active app stays frontmost underneath.
final class OverlayPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        isMovableByWindowBackground = true
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        animationBehavior = .utilityWindow
        isOpaque = false
        backgroundColor = .clear
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class OverlayController: NSObject, NSWindowDelegate {
    static let size = NSSize(width: 760, height: 460)

    let model: OverlayModel
    private let panel: OverlayPanel
    private let paster: Paster
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?

    init(store: ClipStore, paster: Paster) {
        self.paster = paster
        model = OverlayModel(store: store)
        panel = OverlayPanel(contentRect: NSRect(origin: .zero, size: Self.size))
        super.init()

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        let hosting = NSHostingView(rootView: OverlayView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        panel.contentView = effect
        panel.delegate = self

        model.onPaste = { [weak self] clip in self?.paste(clip) }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
        model.reset()
        position()
        panel.makeKeyAndOrderFront(nil)
        // The SwiftUI hierarchy (and the search field) is built lazily on first display.
        panel.contentView?.layoutSubtreeIfNeeded()
        focusSearchField()
        DispatchQueue.main.async { [weak self] in self?.focusSearchField() }
        installKeyMonitor()
    }

    private var searchFieldHasFocus: Bool {
        guard let field = model.searchField else { return false }
        if panel.firstResponder === field { return true }
        // While editing, the first responder is the shared field editor whose delegate is the field.
        return (panel.firstResponder as? NSTextView)?.delegate === field
    }

    private func focusSearchField() {
        guard let field = model.searchField, !searchFieldHasFocus else { return }
        panel.makeFirstResponder(field)
        field.currentEditor()?.selectedRange = NSRange(location: field.stringValue.count, length: 0)
    }

    func hide() {
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    private func paste(_ clip: Clip) {
        hide()
        paster.paste(clip, into: previousApp)
    }

    /// Centered horizontally, slightly above the middle of the screen the user is working on.
    private func position() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let size = Self.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + (frame.height - size.height) * 0.6
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Returns true if the event was handled.
    private func handle(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch Int(event.keyCode) {
        case 53: // Esc
            hide(); return true
        case 36, 76: // Return, Enter
            model.pasteSelected(); return true
        case 125: // ↓
            model.move(by: 1); return true
        case 126: // ↑
            model.move(by: -1); return true
        case 121: // Page down
            model.move(by: 10); return true
        case 116: // Page up
            model.move(by: -10); return true
        case 51 where mods == .command: // ⌘⌫
            model.deleteSelected(); return true
        default:
            break
        }
        if mods == .command, let chars = event.charactersIgnoringModifiers,
           let digit = Int(chars), (1...9).contains(digit) {
            model.paste(at: digit - 1)
            return true
        }
        if mods == .command, event.charactersIgnoringModifiers == "w" {
            hide(); return true
        }
        // Typing after clicking a row or the preview: send the keystroke to the search field.
        if !searchFieldHasFocus, mods.isSubset(of: .shift), let chars = event.characters, !chars.isEmpty {
            focusSearchField()
            return false
        }
        return false
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // Clicking outside the panel (or switching apps) closes it.
        if panel.isVisible { hide() }
    }
}
