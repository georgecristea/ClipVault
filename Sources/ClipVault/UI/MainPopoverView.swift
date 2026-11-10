import MacUtilityKit
import SwiftUI

enum PopoverScreen {
    case history
    case settings
    case about
    case exclusions
}

struct MainPopoverView: View {
    @ObservedObject var appState: AppState
    // Observe settings directly so the pause icon/subtitle react to capturePaused changes
    // (a change one level down on appState.settings doesn't re-render an appState observer).
    @ObservedObject var settings: AppSettings

    init(appState: AppState) {
        self.appState = appState
        self._settings = ObservedObject(wrappedValue: appState.settings)
    }

    var body: some View {
        MUKPopoverShell(message: appState.lastMessage) {
            header
        } content: {
            content
        }
    }

    @ViewBuilder private var header: some View {
        switch appState.popoverScreen {
        case .history:
            MUKHeader(
                title: "ClipVault",
                subtitle: subtitle,
                systemImage: "doc.on.clipboard")
            {
                MUKIconButton(
                    systemImage: settings.capturePaused ? "play.circle.fill" : "pause.circle",
                    help: settings.capturePaused ? "Resume capture" : "Pause capture")
                {
                    appState.setCapturePaused(!settings.capturePaused)
                }
                MUKIconButton(systemImage: "gearshape", help: "Settings") {
                    navigate(to: .settings)
                }
                MUKIconButton(systemImage: "power", help: "Quit ClipVault") {
                    appState.quit()
                }
            }
        case .settings:
            MUKBackHeader(title: "Settings", onBack: { navigate(to: .history) })
        case .about:
            MUKBackHeader(title: "About", onBack: { navigate(to: .settings) })
        case .exclusions:
            MUKBackHeader(title: "App Exclusions", onBack: { navigate(to: .settings) })
        }
    }

    @ViewBuilder private var content: some View {
        switch appState.popoverScreen {
        case .history:
            HistoryView(appState: appState)
        case .settings:
            SettingsView(
                appState: appState,
                onShowAbout: { navigate(to: .about) },
                onShowExclusions: { navigate(to: .exclusions) })
        case .about:
            AboutView()
        case .exclusions:
            ExclusionsView(appState: appState)
        }
    }

    private var subtitle: String {
        if settings.capturePaused { return "Capture paused" }
        let count = appState.items.count
        return count == 1 ? "1 item" : "\(count) items"
    }

    private func navigate(to screen: PopoverScreen) {
        withAnimation(.easeInOut(duration: 0.18)) { appState.popoverScreen = screen }
    }
}
