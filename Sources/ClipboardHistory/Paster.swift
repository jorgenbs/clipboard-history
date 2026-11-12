import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ClipboardCore

/// Puts a clip back on the pasteboard and sends ⌘V to the target app.
final class Paster {
    private let store: ClipStore
    private let monitor: PasteboardMonitor
    /// Called when ⌘V can't be sent because Accessibility permission is missing.
    var onMissingAccessibility: (() -> Void)?

    init(store: ClipStore, monitor: PasteboardMonitor) {
        self.store = store
        self.monitor = monitor
    }

    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Writes the clip to the pasteboard. Returns false if its data is gone.
    @discardableResult
    func copyToPasteboard(_ clip: Clip) -> Bool {
        let reps = store.representations(for: clip)
        guard !reps.isEmpty else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()
        for rep in reps {
            item.setData(rep.data, forType: NSPasteboard.PasteboardType(rep.type))
        }
        pb.writeObjects([item])
        monitor.noteOwnWrite()
        store.promote(id: clip.id)
        return true
    }

    /// Copies the clip, re-activates `target` and sends ⌘V.
    func paste(_ clip: Clip, into target: NSRunningApplication?) {
        guard copyToPasteboard(clip) else { NSSound.beep(); return }

        guard Self.isAccessibilityTrusted else {
            onMissingAccessibility?()
            return
        }
        if let target, target.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            target.activate()
        }
        // Give the target app a moment to become key before sending the keystroke.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Self.sendCommandV()
        }
    }

    private static func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode = CGKeyCode(keyCodeForV())
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        // Explicit flags so modifiers still held by the user (e.g. ⌘ from ⌘1) don't leak in.
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// Key code that produces "v" in the current keyboard layout (handles Dvorak etc.).
    private static func keyCodeForV() -> Int {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return kVK_ANSI_V }
        let layoutData = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { raw -> Int in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return kVK_ANSI_V }
            for code in 0..<128 {
                var deadKeys: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars
                )
                if status == noErr, length == 1, chars[0] == UniChar(("v" as Unicode.Scalar).value) {
                    return code
                }
            }
            return kVK_ANSI_V
        }
    }
}
