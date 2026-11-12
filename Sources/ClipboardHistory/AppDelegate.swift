import AppKit
import ClipboardCore
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings()
    private var store: ClipStore!
    private var monitor: PasteboardMonitor!
    private var paster: Paster!
    private var overlay: OverlayController!
    private var hotKey: GlobalHotKey!
    private var hotKeyRegistered = true
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // CLIPBOARD_HISTORY_DATA_DIR lets development runs use a scratch history.
        let dataDirectory = ProcessInfo.processInfo.environment["CLIPBOARD_HISTORY_DATA_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? ClipStore.defaultDirectory
        store = ClipStore(directory: dataDirectory, limit: settings.historyLimit)
        #if DEBUG
        DebugSnapshot.runIfRequested(store: store, settings: settings)
        #endif
        monitor = PasteboardMonitor(store: store, settings: settings)
        paster = Paster(store: store, monitor: monitor)
        overlay = OverlayController(store: store, paster: paster)
        paster.onMissingAccessibility = { [weak self] in self?.accessibilityMissing() }

        hotKey = GlobalHotKey { [weak self] in self?.overlay.toggle() }
        settings.$hotKey
            .sink { [weak self] combo in self?.registerHotKey(combo) }
            .store(in: &cancellables)
        settings.$isPaused
            .sink { [weak self] paused in self?.statusItem?.button?.appearsDisabled = paused }
            .store(in: &cancellables)
        settings.$historyLimit
            .dropFirst()
            .sink { [weak self] limit in self?.store.limit = limit }
            .store(in: &cancellables)

        setUpStatusItem()
        monitor.start()

        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.async { self.overlay.show() }
        }

        if !Paster.isAccessibilityTrusted && !settings.hasShownAccessibilityPrompt {
            // Ask once up front; afterwards the menu shows a warning item.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showAccessibilityPrompt() }
        }
    }

    private func registerHotKey(_ combo: HotKeyCombo) {
        hotKeyRegistered = hotKey.register(combo)
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "Clipboard History")
            ?? NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard History")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.appearsDisabled = settings.isPaused
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let open = NSMenuItem(title: "Open Clipboard History", action: #selector(openOverlay), keyEquivalent: "")
        open.target = self
        let label = settings.hotKey.keyLabel
        let isPlainKey = label.count == 1 && label.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) && $0.isASCII }
        open.keyEquivalent = isPlainKey ? label.lowercased() : ""
        open.keyEquivalentModifierMask = settings.hotKey.cocoaModifiers
        menu.addItem(open)

        if !hotKeyRegistered {
            menu.addItem(warningItem("Shortcut \(settings.hotKey.displayString) is used by another app", action: #selector(openSettings)))
        }
        if !Paster.isAccessibilityTrusted {
            menu.addItem(warningItem("Grant Accessibility to enable auto-paste…", action: #selector(openAccessibility)))
        }

        menu.addItem(.separator())

        let pause = NSMenuItem(title: "Pause Recording", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        pause.state = settings.isPaused ? .on : .off
        menu.addItem(pause)

        let count = NSMenuItem(title: "\(store.clips.count) of \(settings.historyLimit) clips", action: nil, keyEquivalent: "")
        count.isEnabled = false
        menu.addItem(count)

        let clear = NSMenuItem(title: "Clear History…", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = !store.clips.isEmpty
        menu.addItem(clear)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let about = NSMenuItem(title: "About Clipboard History", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(NSMenuItem(title: "Quit Clipboard History", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func warningItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        return item
    }

    @objc private func openOverlay() {
        // Let the menu finish closing so the previously active app is frontmost again.
        DispatchQueue.main.async { self.overlay.show() }
    }

    @objc private func togglePause() {
        settings.isPaused.toggle()
    }

    @objc private func clearHistory() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "All \(store.clips.count) clips will be deleted. This can't be undone."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            store.clear()
        }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(settings: settings, state: SettingsViewState()) { [weak self] recording in
                guard let self else { return }
                if recording { self.hotKey.unregister() } else { self.registerHotKey(self.settings.hotKey) }
            }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Clipboard History Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openAccessibility() {
        Paster.openAccessibilitySettings()
    }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(
                string: "Clipboard history in your menu bar.",
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
            ),
        ])
    }

    // MARK: - Accessibility

    private func accessibilityMissing() {
        if settings.hasShownAccessibilityPrompt {
            // The clip is on the clipboard already; a beep signals that ⌘V wasn't sent.
            NSSound.beep()
        } else {
            showAccessibilityPrompt()
        }
    }

    private func showAccessibilityPrompt() {
        settings.hasShownAccessibilityPrompt = true
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Allow Clipboard History to paste for you"
        alert.informativeText = """
        To paste the selected clip automatically, Clipboard History needs Accessibility access \
        (System Settings › Privacy & Security › Accessibility).

        Until then, the clip is copied to your clipboard and you can paste it with ⌘V.

        If Clipboard History is already listed but auto-paste doesn't work (for example after an update), \
        remove it from the list with the – button and add it again.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            Paster.openAccessibilitySettings()
        }
    }
}
