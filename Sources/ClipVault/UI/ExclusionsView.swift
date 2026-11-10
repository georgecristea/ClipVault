import AppKit
import MacUtilityKit
import SwiftUI

/// Manage the list of apps ClipVault won't capture from (password managers, etc.).
struct ExclusionsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: AppSettings

    init(appState: AppState) {
        self.appState = appState
        self._settings = ObservedObject(wrappedValue: appState.settings)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("ClipVault never saves clips copied while one of these apps is frontmost. Password managers are excluded by default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)

                Button {
                    addFrontmostApp()
                } label: {
                    MUKSettingsRow(
                        title: "Exclude the current app",
                        detail: "Add whatever app is frontmost right now",
                        systemImage: "plus.circle")
                    {
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                ForEach(settings.excludedBundleIDs, id: \.self) { bundleID in
                    MUKSettingsRow(
                        title: displayName(for: bundleID),
                        detail: bundleID,
                        systemImage: "nosign")
                    {
                        Button { remove(bundleID) } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove")
                    }
                }

                if settings.excludedBundleIDs.isEmpty {
                    Text("No apps excluded.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
            .padding(16)
        }
    }

    private func addFrontmostApp() {
        // ClipVault is frontmost while the popover is open, so use the most recent *other* app.
        let others = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier
        }
        guard let bundleID = others.first(where: { $0.isActive })?.bundleIdentifier
            ?? others.first?.bundleIdentifier else { return }
        var ids = appState.settings.excludedBundleIDs
        ids.append(bundleID)
        appState.settings.setExcludedBundleIDs(ids)
    }

    private func remove(_ bundleID: String) {
        appState.settings.setExcludedBundleIDs(appState.settings.excludedBundleIDs.filter { $0 != bundleID })
    }

    private func displayName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
