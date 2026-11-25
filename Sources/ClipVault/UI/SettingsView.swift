import AppKit
import MacUtilityKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: AppSettings
    let onShortcutChange: (MUKHotkey) -> Bool
    let onShowAbout: () -> Void
    let onShowExclusions: () -> Void

    @State private var retentionDays: Int
    @State private var sliderDays: Double
    @State private var keepForever: Bool
    @State private var launchAtLogin: Bool
    @State private var accessibilityGranted = MUKPasteInjector.isTrusted
    @State private var shortcutRejected = false
    @State private var storage = ""

    init(appState: AppState, onShortcutChange: @escaping (MUKHotkey) -> Bool,
         onShowAbout: @escaping () -> Void, onShowExclusions: @escaping () -> Void) {
        self.appState = appState
        self._settings = ObservedObject(wrappedValue: appState.settings)
        self.onShortcutChange = onShortcutChange
        self.onShowAbout = onShowAbout
        self.onShowExclusions = onShowExclusions
        _retentionDays = State(initialValue: appState.settings.retentionDays)
        _sliderDays = State(initialValue: Double(RetentionPolicy.sliderValue(for: appState.settings.retentionDays)))
        _keepForever = State(initialValue: appState.settings.keepForever)
        _launchAtLogin = State(initialValue: appState.launchAtLoginManager.isEnabled)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                MUKSettingsRow(title: "Show the bar",
                               detail: shortcutRejected ? "That shortcut is taken; kept the previous one" : "Global shortcut, from any app",
                               systemImage: "keyboard") {
                    MUKHotkeyRecorder(hotkey: shortcutBinding, allowsModifierOnly: false)
                }

                MUKSettingsRow(title: "Paste into the active app",
                               detail: "Otherwise picking a clip only copies it",
                               systemImage: "arrow.down.doc") {
                    Toggle("", isOn: $settings.pasteIntoActiveApp).labelsHidden()
                }

                if settings.pasteIntoActiveApp {
                    MUKSettingsRow(title: accessibilityGranted ? "Accessibility granted" : "Accessibility needed",
                                   detail: accessibilityGranted ? "ClipVault can paste for you" : "Required to paste; until then clips are copied",
                                   systemImage: accessibilityGranted ? "checkmark.shield" : "exclamationmark.shield") {
                        if !accessibilityGranted {
                            Button("Grant…") {
                                BarController.requestAccessibility()
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                            }
                        }
                    }
                }

                MUKSettingsRow(title: "Always paste as plain text",
                               detail: "⇧Return pastes as plain text either way",
                               systemImage: "textformat") {
                    Toggle("", isOn: $settings.alwaysPlainText).labelsHidden()
                }

                MUKSettingsRow(title: "Keep history forever",
                               detail: "Never auto-delete older clips. Pinboards are always kept.",
                               systemImage: "infinity") {
                    Toggle("", isOn: $keepForever).labelsHidden()
                }

                if !keepForever {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Keep clips for").font(.callout)
                            Spacer()
                            TextField("", value: $retentionDays, format: .number)
                                .labelsHidden()
                                .frame(width: 54)
                                .multilineTextAlignment(.trailing)
                            Text("days").foregroundStyle(.secondary)
                        }
                        Slider(value: $sliderDays, in: Double(RetentionPolicy.sliderRange.lowerBound)...Double(RetentionPolicy.sliderRange.upperBound))
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: MUKTheme.cardRadius).fill(Color.primary.opacity(0.05)))
                }

                Button(action: onShowExclusions) {
                    MUKSettingsRow(title: "App exclusions",
                                   detail: "Don't save clips from password managers & chosen apps",
                                   systemImage: "hand.raised") {
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                MUKSettingsRow(title: "Erase history", detail: storage, systemImage: "trash") {
                    Button("Erase…", role: .destructive) { eraseHistory() }
                }

                MUKSettingsRow(title: "Launch at login",
                               detail: "Open ClipVault automatically when you log in",
                               systemImage: "power") {
                    Toggle("", isOn: launchBinding).labelsHidden()
                }

                Button(action: onShowAbout) {
                    MUKSettingsRow(title: "About ClipVault", detail: "Version, license, acknowledgements", systemImage: "info.circle") {
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .onAppear(perform: refreshStorage)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            // The grant happens in System Settings, which does not notify us.
            accessibilityGranted = MUKPasteInjector.isTrusted
        }
        .onChange(of: sliderDays) { _, value in
            let stepped = RetentionPolicy.sliderValue(for: Int(value.rounded()))
            if Double(stepped) != value { sliderDays = Double(stepped); return }
            if RetentionPolicy.sliderValue(for: retentionDays) != stepped { retentionDays = stepped }
        }
        .onChange(of: retentionDays) { _, value in
            let clamped = RetentionPolicy.clampField(value)
            if clamped != value { retentionDays = clamped; return }
            sliderDays = Double(RetentionPolicy.sliderValue(for: clamped))
            scheduleRetentionChange()
        }
        .onChange(of: keepForever) { _, _ in scheduleRetentionChange() }
    }

    private var shortcutBinding: Binding<MUKHotkey> {
        Binding(
            get: { settings.shortcut },
            set: { newValue in
                if onShortcutChange(newValue) {
                    settings.setShortcut(newValue)
                    shortcutRejected = false
                } else {
                    _ = onShortcutChange(settings.shortcut)
                    shortcutRejected = true
                }
            })
    }

    @State private var pendingRetention: Task<Void, Never>?

    /// Applies a retention change after the controls settle, asking first if clips would go.
    private func scheduleRetentionChange() {
        pendingRetention?.cancel()
        let days = retentionDays
        let forever = keepForever
        pendingRetention = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled, days != settings.retentionDays || forever != settings.keepForever else { return }
            let affected = await appState.clipsAffected(days: days, keepForever: forever)
            if RetentionPolicy.needsConfirmation(affected: affected) {
                let alert = NSAlert()
                alert.messageText = "Delete \(affected) older clip\(affected == 1 ? "" : "s")?"
                alert.informativeText = "Clips not copied in the last \(days) days will be removed. Clips on a pinboard are kept."
                alert.addButton(withTitle: "Delete")
                alert.addButton(withTitle: "Keep Previous Setting")
                guard alert.runModal() == .alertFirstButtonReturn else {
                    retentionDays = settings.retentionDays
                    keepForever = settings.keepForever
                    return
                }
            }
            appState.updateRetention(days: days, keepForever: forever)
            refreshStorage()
        }
    }

    private func eraseHistory() {
        let alert = NSAlert()
        alert.messageText = "Erase clipboard history?"
        alert.informativeText = "Every clip is deleted except those on a pinboard. This cannot be undone."
        alert.addButton(withTitle: "Erase")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            await appState.eraseHistory()
            refreshStorage()
        }
    }

    private func refreshStorage() {
        Task {
            guard let summary = try? await appState.store.summary() else { return }
            let size = ByteCountFormatter.string(fromByteCount: Int64(summary.bytes), countStyle: .file)
            storage = "\(summary.count) clip\(summary.count == 1 ? "" : "s"), \(size). Pinboards are kept."
        }
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                try? appState.launchAtLoginManager.setEnabled(newValue)
                launchAtLogin = appState.launchAtLoginManager.isEnabled
            })
    }
}
