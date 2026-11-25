import AppKit
import ApplicationServices

/// Asking for the Accessibility permission that pasting into other apps needs.
///
/// macOS stores the app's code signature with its Accessibility entry when the entry is first
/// created, and switching an existing entry back on does not refresh it. After a rebuild with a
/// different signature the switch shows "on" while macOS still refuses the app. So before asking,
/// ClipVault removes its own entry (only its own, and only when it is not trusted); the prompt then
/// creates a fresh entry that matches the running app.
enum AccessibilityAccess {
    static let tccutilPath = "/usr/bin/tccutil"

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func resetArguments(bundleID: String) -> [String] {
        ["reset", "Accessibility", bundleID]
    }

    static func shouldResetBeforeRequesting(isTrusted: Bool) -> Bool { !isTrusted }

    /// Clears a stale entry if needed, shows the system prompt, and opens the Accessibility pane.
    static func request() {
        if shouldResetBeforeRequesting(isTrusted: isTrusted), let bundleID = Bundle.main.bundleIdentifier {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tccutilPath)
            process.arguments = resetArguments(bundleID: bundleID)
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
