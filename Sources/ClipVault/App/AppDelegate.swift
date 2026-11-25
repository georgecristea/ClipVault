import AppKit
import MacUtilityKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState?
    private var bar: BarController?
    private var statusBarController: StatusBarController?
    private var settingsWindow: SettingsWindowController?
    private var hotKey: MUKCarbonHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MUKTheme.brand = MUKBrand(
            name: "ClipVault",
            tagline: "Your clipboard, searchable and private",
            symbol: "doc.on.clipboard",
            accent: Color(red: 0.18, green: 0.55, blue: 0.95),
            accentSecondary: Color(red: 0.30, green: 0.72, blue: 0.98))

        if DemoMode.isEnabled {
            Task { @MainActor in
                do { launch(store: try await DemoMode.makeStore(), settings: AppSettings(defaults: DemoMode.defaults)) } catch { fail(error) }
            }
            return
        }
        do {
            // Installations from before 0.2 keep their old defaults (7 days, the shorter exclusion list).
            AppSettings.preserveLegacyDefaults(existingInstall: SQLiteClipStore.databaseExists())
            launch(store: try SQLiteClipStore(), settings: AppSettings())
        } catch {
            fail(error)
        }
    }

    private func launch(store: SQLiteClipStore, settings: AppSettings) {
        let state = AppState(store: store, settings: settings)
        let bar = BarController(appState: state)
        let hotKey = MUKCarbonHotKey(binding: settings.shortcut) { [weak bar] in bar?.toggle() }
        let settingsWindow = SettingsWindowController(appState: state) { [weak hotKey] binding in
            hotKey?.update(binding: binding) ?? false
        }
        let statusBar = StatusBarController(appState: state, showBar: { [weak bar] in bar?.show() },
                                            showSettings: { [weak settingsWindow] in settingsWindow?.show($0) })
        bar.openSettings = { [weak settingsWindow] in settingsWindow?.show(.settings) }
        state.onHistoryChanged = { [weak bar, weak statusBar] in
            bar?.historyChanged()
            statusBar?.updateIcon()
        }

        appState = state
        self.bar = bar
        self.hotKey = hotKey
        self.settingsWindow = settingsWindow
        statusBarController = statusBar

        // Automation hook (scripts, screenshots): toggle the bar without a key press.
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.georgecristea.ClipVault.toggleBar"), object: nil, queue: .main) { [weak bar] _ in
            Task { @MainActor in bar?.toggle() }
        }

        guard DemoMode.isEnabled else {
            state.start()
            return
        }
        // Demo: show the sample history without ever reading the real clipboard.
        if let path = DemoMode.snapshotPath {
            DemoMode.writeSnapshot(of: bar, to: path)
        }
    }

    private func fail(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "ClipVault could not start"
        alert.informativeText = error.localizedDescription
        alert.runModal()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState?.stop()
    }
}
