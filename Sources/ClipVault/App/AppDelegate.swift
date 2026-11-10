import AppKit
import MacUtilityKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MUKTheme.brand = MUKBrand(
            name: "ClipVault",
            tagline: "Your clipboard, searchable and private",
            symbol: "doc.on.clipboard",
            accent: Color(red: 0.18, green: 0.55, blue: 0.95),
            accentSecondary: Color(red: 0.30, green: 0.72, blue: 0.98))

        if DemoMode.isEnabled {
            Task { @MainActor in
                do { launch(store: try await DemoMode.makeStore()) } catch { fail(error) }
            }
            return
        }
        do {
            launch(store: try SQLiteClipStore())
        } catch {
            fail(error)
        }
    }

    private func launch(store: SQLiteClipStore) {
        let state = AppState(store: store)
        let statusBarController = StatusBarController(appState: state)

        state.requestClosePopover = { [weak statusBarController] in statusBarController?.closePopover() }

        self.appState = state
        self.statusBarController = statusBarController

        guard DemoMode.isEnabled else {
            state.start()
            return
        }
        // Demo: show the sample history without ever reading the real clipboard.
        state.reload()
        if let path = DemoMode.snapshotPath {
            DemoMode.writeSnapshot(of: state, to: path)
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
