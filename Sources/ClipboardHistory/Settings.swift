import AppKit
import Carbon.HIToolbox
import Combine

struct HotKeyCombo: Codable, Equatable {
    var keyCode: UInt32
    /// Carbon modifier mask (cmdKey, optionKey, controlKey, shiftKey).
    var carbonModifiers: UInt32
    /// Character shown for the key, e.g. "C".
    var keyLabel: String

    static let `default` = HotKeyCombo(keyCode: UInt32(kVK_ANSI_C), carbonModifiers: UInt32(optionKey | cmdKey), keyLabel: "C")

    var displayString: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + keyLabel
    }

    var cocoaModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        return mods
    }
}

struct IgnoredApp: Codable, Equatable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var id: String { bundleID }
}

/// User preferences, persisted in UserDefaults.
final class Settings: ObservableObject {
    static let historyLimitOptions = [100, 500, 1000, 5000]

    static let defaultIgnoredApps: [IgnoredApp] = [
        IgnoredApp(bundleID: "com.1password.1password", name: "1Password"),
        IgnoredApp(bundleID: "com.agilebits.onepassword7", name: "1Password 7"),
        IgnoredApp(bundleID: "me.proton.pass.electron", name: "Proton Pass"),
        IgnoredApp(bundleID: "ch.protonmail.desktop", name: "Proton Mail"),
        IgnoredApp(bundleID: "com.apple.Passwords", name: "Passwords"),
        IgnoredApp(bundleID: "com.apple.keychainaccess", name: "Keychain Access"),
        IgnoredApp(bundleID: "com.apple.Passbook", name: "Wallet"),
    ]

    private let defaults: UserDefaults

    @Published var hotKey: HotKeyCombo { didSet { store(hotKey, "hotKey") } }
    @Published var historyLimit: Int { didSet { defaults.set(historyLimit, forKey: "historyLimit") } }
    @Published var ignoredApps: [IgnoredApp] { didSet { store(ignoredApps, "ignoredApps") } }
    @Published var isPaused: Bool { didSet { defaults.set(isPaused, forKey: "isPaused") } }
    @Published var hasShownAccessibilityPrompt: Bool {
        didSet { defaults.set(hasShownAccessibilityPrompt, forKey: "hasShownAccessibilityPrompt") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hotKey = Self.load("hotKey", defaults) ?? .default
        let limit = defaults.integer(forKey: "historyLimit")
        historyLimit = limit > 0 ? limit : 500
        ignoredApps = Self.load("ignoredApps", defaults) ?? Self.defaultIgnoredApps
        isPaused = defaults.bool(forKey: "isPaused")
        hasShownAccessibilityPrompt = defaults.bool(forKey: "hasShownAccessibilityPrompt")
    }

    var ignoredBundleIDs: Set<String> { Set(ignoredApps.map(\.bundleID)) }

    private func store<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ key: String, _ defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}
