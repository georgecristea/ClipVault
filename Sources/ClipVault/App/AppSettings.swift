import Foundation

final class AppSettings: ObservableObject {
    static let defaultRetentionDays = 7

    /// Password managers excluded from capture by default (belt-and-suspenders on top of the
    /// concealed-pasteboard-type filter). Users can edit this list.
    static let defaultExcludedBundleIDs: [String] = [
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
    @Published private(set) var capturePaused: Bool
    @Published private(set) var excludedBundleIDs: [String]

    private enum Key {
        static let retentionDays = "retentionDays"
        static let keepForever = "keepForever"
        static let capturePaused = "capturePaused"
        static let excludedBundleIDs = "excludedBundleIDs"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.retentionDays: Self.defaultRetentionDays,
            Key.keepForever: false,
            Key.capturePaused: false
        ])

        retentionDays = max(1, defaults.integer(forKey: Key.retentionDays))
        keepForever = defaults.bool(forKey: Key.keepForever)
        capturePaused = defaults.bool(forKey: Key.capturePaused)
        excludedBundleIDs = (defaults.array(forKey: Key.excludedBundleIDs) as? [String])
            ?? Self.defaultExcludedBundleIDs
    }

    var expirationDate: Date? {
        guard !keepForever else { return nil }
        return Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date())
    }

    func setRetention(days: Int, keepForever: Bool) {
        let safeDays = min(max(days, 1), 3650)
        retentionDays = safeDays
        self.keepForever = keepForever
        defaults.set(safeDays, forKey: Key.retentionDays)
        defaults.set(keepForever, forKey: Key.keepForever)
    }

    func setCapturePaused(_ paused: Bool) {
        capturePaused = paused
        defaults.set(paused, forKey: Key.capturePaused)
    }

    func setExcludedBundleIDs(_ ids: [String]) {
        let unique = Array(Set(ids)).sorted()
        excludedBundleIDs = unique
        defaults.set(unique, forKey: Key.excludedBundleIDs)
    }
}
