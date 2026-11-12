import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Transient view state. (A class instead of `@State`: the Command Line Tools SDK lacks the
/// SwiftUI macro plugin that `@State` needs on newer SDKs, and this keeps `swift build` working without Xcode.)
final class SettingsViewState: ObservableObject {
    @Published var selectedIgnored: Set<String> = []
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var launchAtLoginError: String?
    @Published var accessibilityTrusted = Paster.isAccessibilityTrusted
}

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var state: SettingsViewState
    var onRecordingHotKey: (Bool) -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent("Open history") {
                    HotKeyRecorder(combo: $settings.hotKey, onRecordingChange: onRecordingHotKey)
                        .fixedSize()
                }
                Picker("Keep", selection: $settings.historyLimit) {
                    ForEach(Settings.historyLimitOptions, id: \.self) { Text("\($0) clips").tag($0) }
                }
                Toggle("Launch at login", isOn: $state.launchAtLogin)
                    .onChange(of: state.launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let launchAtLoginError = state.launchAtLoginError {
                    Text(launchAtLoginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                LabeledContent("Auto-paste") {
                    if state.accessibilityTrusted {
                        Label("Accessibility granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        HStack {
                            Label("Needs Accessibility", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Button("Open Settings…") { Paster.openAccessibilitySettings() }
                        }
                    }
                }
            }

            Section {
                List(selection: $state.selectedIgnored) {
                    ForEach(settings.ignoredApps) { app in
                        HStack {
                            AppIconView(bundleID: app.bundleID)
                            Text(app.name)
                            Spacer()
                            Text(app.bundleID).foregroundStyle(.secondary).font(.caption)
                        }
                        .tag(app.bundleID)
                    }
                }
                .frame(minHeight: 160)
                HStack {
                    Menu("Add Running App") {
                        ForEach(runningApps(), id: \.bundleID) { app in
                            Button(app.name) { add(app) }
                        }
                    }
                    .fixedSize()
                    Button("Choose App…") { chooseApp() }
                    Spacer()
                    Button("Remove") {
                        settings.ignoredApps.removeAll { state.selectedIgnored.contains($0.bundleID) }
                        state.selectedIgnored = []
                    }
                    .disabled(state.selectedIgnored.isEmpty)
                    Button("Reset to Defaults") { settings.ignoredApps = Settings.defaultIgnoredApps }
                }
            } header: {
                Text("Ignored apps")
            } footer: {
                Text("Nothing copied while these apps are frontmost is recorded. Data marked as concealed or auto-generated (most password managers do this) is never recorded.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            state.accessibilityTrusted = Paster.isAccessibilityTrusted
            state.launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func runningApps() -> [IgnoredApp] {
        let ignored = settings.ignoredBundleIDs
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier, !ignored.contains(id),
                      id != Bundle.main.bundleIdentifier else { return nil }
                return IgnoredApp(bundleID: id, name: app.localizedName ?? id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func add(_ app: IgnoredApp) {
        guard !settings.ignoredApps.contains(where: { $0.bundleID == app.bundleID }) else { return }
        settings.ignoredApps.append(app)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            add(IgnoredApp(bundleID: id, name: name))
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
            state.launchAtLoginError = nil
        } catch {
            state.launchAtLoginError = "Couldn't change login item: \(error.localizedDescription)"
            state.launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
