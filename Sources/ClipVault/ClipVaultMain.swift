import AppKit

@main
struct ClipVaultMain {
    @MainActor
    static func main() {
        let appDelegate = AppDelegate()
        let app = NSApplication.shared
        app.delegate = appDelegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

