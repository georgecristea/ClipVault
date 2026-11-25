import Foundation
import MacUtilityKit

final class AppSettings: ObservableObject {
    static let defaultRetentionDays = 30
    /// The default before 0.2, kept for people upgrading.
    static let legacyRetentionDays = 7
    static let defaultShortcut = MUKHotkey(keyCode: 9, modifiers: [.command, .shift]) // ⇧⌘V

    /// Password managers excluded from capture by default (belt-and-suspenders on top of the
    /// concealed-pasteboard-type filter). Users can edit this list.
    static let defaultExcludedBundleIDs: [String] = [
        "com.apple.Passwords",
        "com.apple.keychainaccess",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword-osx",
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc",
        "com.lastpass.LastPass",
        "com.dashlane.Dashlane",
        "in.sinew.Enpass-Desktop",
        "com.keepersecurity.passwordmanager",
        "com.siber.RoboForm"
    ]
    /// The default list before 0.2, kept for people upgrading.
    static let legacyExcludedBundleIDs: [String] = [
        "com.agilebits.onepassword7",
        "com.1password.1password",
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc",
        "com.lastpass.LastPass",
        "com.dashlane.Dashlane",
        "com.apple.keychainaccess"
    ]

    @Published private(set) var retentionDays: Int
    @Published private(set) var keepForever: Bool
    /// Capture is paused until this date; `.distantFuture` means until resumed.
    @Published private(set) var pausedUntil: Date?
    @Published private(set) var excludedBundleIDs: [String]
    @Published private(set) var shortcut: MUKHotkey
    /// When false, picking a clip only copies it; the user pastes with ⌘V.
    @Published var pasteIntoActiveApp: Bool { didSet { defaults.set(pasteIntoActiveApp, forKey: Key.pasteIntoActiveApp) } }
    @Published var alwaysPlainText: Bool { didSet { defaults.set(alwaysPlainText, forKey: Key.alwaysPlainText) } }

    private enum Key {
        static let retentionDays = "retentionDays"
        static let keepForever = "keepForever"
        static let capturePaused = "capturePaused" // 0.1: a plain on/off pause
        static let pausedUntil = "pausedUntil"
        static let excludedBundleIDs = "excludedBundleIDs"
        static let shortcut = "shortcut"
        static let pasteIntoActiveApp = "pasteIntoActiveApp"
        static let alwaysPlainText = "alwaysPlainText"
    }

    private let defaults: UserDefaults

    /// For an installation that predates 0.2, stores the old defaults explicitly so the new
    /// defaults (30 days, a longer exclusion list) only apply to new installations.
    static func preserveLegacyDefaults(in defaults: UserDefaults = .standard, existingInstall: Bool) {
        guard existingInstall else { return }
        if defaults.object(forKey: Key.retentionDays) == nil {
            defaults.set(legacyRetentionDays, forKey: Key.retentionDays)
        }
        if defaults.object(forKey: Key.excludedBundleIDs) == nil {
            defaults.set(legacyExcludedBundleIDs, forKey: Key.excludedBundleIDs)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.retentionDays: Self.defaultRetentionDays,
            Key.keepForever: false,
            Key.pasteIntoActiveApp: true,
            Key.alwaysPlainText: false
        ])

        retentionDays = min(max(1, defaults.integer(forKey: Key.retentionDays)), 3650)
        keepForever = defaults.bool(forKey: Key.keepForever)
        excludedBundleIDs = (defaults.array(forKey: Key.excludedBundleIDs) as? [String]) ?? Self.defaultExcludedBundleIDs
        pasteIntoActiveApp = defaults.bool(forKey: Key.pasteIntoActiveApp)
        alwaysPlainText = defaults.bool(forKey: Key.alwaysPlainText)
        shortcut = defaults.data(forKey: Key.shortcut).flatMap { try? JSONDecoder().decode(MUKHotkey.self, from: $0) }
            ?? Self.defaultShortcut

        if defaults.bool(forKey: Key.capturePaused) {
            // Migrate 0.1's on/off pause.
            defaults.removeObject(forKey: Key.capturePaused)
            defaults.set(Date.distantFuture, forKey: Key.pausedUntil)
        }
        pausedUntil = defaults.object(forKey: Key.pausedUntil) as? Date
    }

    var expirationDate: Date? {
        RetentionPolicy.cutoff(days: retentionDays, keepForever: keepForever, now: Date())
    }

    var isCapturePaused: Bool {
        guard let pausedUntil else { return false }
        return pausedUntil > Date()
    }

    func setRetention(days: Int, keepForever: Bool) {
        let safeDays = RetentionPolicy.clampField(days)
        retentionDays = safeDays
        self.keepForever = keepForever
        defaults.set(safeDays, forKey: Key.retentionDays)
        defaults.set(keepForever, forKey: Key.keepForever)
    }

    /// Pauses capture until `date` (`.distantFuture` for until resumed), or resumes with nil.
    func pause(until date: Date?) {
        pausedUntil = date
        if let date { defaults.set(date, forKey: Key.pausedUntil) } else { defaults.removeObject(forKey: Key.pausedUntil) }
    }

    func setExcludedBundleIDs(_ ids: [String]) {
        let unique = Array(Set(ids)).sorted()
        excludedBundleIDs = unique
        defaults.set(unique, forKey: Key.excludedBundleIDs)
    }

    func setShortcut(_ hotkey: MUKHotkey) {
        shortcut = hotkey
        if let data = try? JSONEncoder().encode(hotkey) { defaults.set(data, forKey: Key.shortcut) }
    }
}
