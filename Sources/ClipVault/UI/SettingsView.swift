import MacUtilityKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    let onShowAbout: () -> Void
    let onShowExclusions: () -> Void

    @State private var retentionDays: Int
    @State private var keepForever: Bool
    @State private var launchAtLogin: Bool

    init(appState: AppState, onShowAbout: @escaping () -> Void, onShowExclusions: @escaping () -> Void) {
        self.appState = appState
        self.onShowAbout = onShowAbout
        self.onShowExclusions = onShowExclusions
        _retentionDays = State(initialValue: appState.settings.retentionDays)
        _keepForever = State(initialValue: appState.settings.keepForever)
        _launchAtLogin = State(initialValue: appState.launchAtLoginManager.isEnabled)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Button(action: onShowExclusions) {
                    MUKSettingsRow(
                        title: "App exclusions",
                        detail: "Don't save clips from password managers & chosen apps",
                        systemImage: "hand.raised")
                    {
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                MUKSettingsRow(
                    title: "Keep history forever",
                    detail: "Never auto-delete older clips. Pinned items are always kept.",
                    systemImage: "infinity")
                {
                    Toggle("", isOn: $keepForever)
                        .labelsHidden()
                        .onChange(of: keepForever) { _, newValue in applyRetention(keepForever: newValue) }
                }

                MUKSettingsRow(
                    title: "Retention",
                    detail: keepForever ? "Disabled while keeping forever" : "Clips older than this are removed",
                    systemImage: "clock.arrow.circlepath")
                {
                    Stepper("\(retentionDays) \(retentionDays == 1 ? "day" : "days")", value: $retentionDays, in: 1...3650)
                        .labelsHidden()
                        .fixedSize()
                        .disabled(keepForever)
                        .onChange(of: retentionDays) { _, _ in applyRetention(keepForever: keepForever) }
                    Text("\(retentionDays)d")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                MUKSettingsRow(
                    title: "Launch at login",
                    detail: "Open ClipVault automatically when you log in",
                    systemImage: "power")
                {
                    Toggle("", isOn: launchBinding).labelsHidden()
                }

                Button(action: onShowAbout) {
                    MUKSettingsRow(
                        title: "About ClipVault",
                        detail: "Version, license, acknowledgements",
                        systemImage: "info.circle")
                    {
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
    }

    private func applyRetention(keepForever: Bool) {
        appState.updateRetention(days: retentionDays, keepForever: keepForever)
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
