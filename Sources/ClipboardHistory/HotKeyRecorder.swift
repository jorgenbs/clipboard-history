import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click to record a new shortcut. Esc cancels, ⌫ resets to the default.
struct HotKeyRecorder: NSViewRepresentable {
    @Binding var combo: HotKeyCombo
    var onRecordingChange: (Bool) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onChange = { combo = $0 }
        button.onRecordingChange = onRecordingChange
        button.combo = combo
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.onChange = { combo = $0 }
        button.onRecordingChange = onRecordingChange
        if button.combo != combo { button.combo = combo }
    }
}

final class RecorderButton: NSButton {
    var onChange: (HotKeyCombo) -> Void = { _ in }
    var onRecordingChange: (Bool) -> Void = { _ in }
    var combo: HotKeyCombo = .default { didSet { refresh() } }

    private var isRecording = false {
        didSet {
            guard isRecording != oldValue else { return }
            refresh()
            onRecordingChange(isRecording)
        }
    }

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(clicked)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: max(140, super.intrinsicContentSize.width), height: super.intrinsicContentSize.height)
    }

    @objc private func clicked() {
        isRecording.toggle()
        if isRecording { window?.makeFirstResponder(self) }
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // ⌘-combos arrive here rather than in keyDown.
        if isRecording { record(event); return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if isRecording { record(event) } else { super.keyDown(with: event) }
    }

    private func record(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch Int(event.keyCode) {
        case kVK_Escape where flags.isEmpty:
            isRecording = false
            return
        case kVK_Delete where flags.isEmpty, kVK_ForwardDelete where flags.isEmpty:
            combo = .default
            onChange(.default)
            isRecording = false
            return
        default:
            break
        }
        // Require ⌘, ⌥ or ⌃ so plain typing can't become a global hotkey.
        guard !flags.intersection([.command, .option, .control]).isEmpty else { NSSound.beep(); return }
        let label = Self.label(for: event)
        let newCombo = HotKeyCombo(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: HotKeyCombo.carbonModifiers(from: flags),
            keyLabel: label
        )
        combo = newCombo
        onChange(newCombo)
        isRecording = false
    }

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12",
    ]

    private static func label(for event: NSEvent) -> String {
        if let special = specialKeys[Int(event.keyCode)] { return special }
        let chars = event.charactersIgnoringModifiers?.uppercased() ?? ""
        return chars.isEmpty ? "#\(event.keyCode)" : chars
    }

    private func refresh() {
        title = isRecording ? "Type shortcut…" : combo.displayString
    }
}
