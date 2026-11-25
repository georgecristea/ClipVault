import MacUtilityKit
import XCTest
@testable import ClipVault

final class AppSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "ClipVaultTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testNewInstallDefaults() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.retentionDays, 30)
        XCTAssertFalse(settings.keepForever)
        XCTAssertTrue(settings.pasteIntoActiveApp)
        XCTAssertFalse(settings.alwaysPlainText)
        XCTAssertEqual(settings.shortcut, MUKHotkey(keyCode: 9, modifiers: [.command, .shift]))
        XCTAssertTrue(settings.excludedBundleIDs.contains("com.apple.Passwords"))
        XCTAssertFalse(settings.isCapturePaused)
    }

    func testExistingInstallKeepsOldDefaults() {
        AppSettings.preserveLegacyDefaults(in: defaults, existingInstall: true)
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.retentionDays, 7)
        XCTAssertEqual(Set(settings.excludedBundleIDs), Set(AppSettings.legacyExcludedBundleIDs))
    }

    func testExistingRetentionKept() {
        defaults.set(12, forKey: "retentionDays")
        AppSettings.preserveLegacyDefaults(in: defaults, existingInstall: true)
        XCTAssertEqual(AppSettings(defaults: defaults).retentionDays, 12)
    }

    func testLegacyPausedMigrates() {
        defaults.set(true, forKey: "capturePaused")
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.isCapturePaused)
        XCTAssertEqual(settings.pausedUntil, .distantFuture)
    }

    func testTimedPauseExpires() {
        let settings = AppSettings(defaults: defaults)
        settings.pause(until: Date(timeIntervalSinceNow: -1))
        XCTAssertFalse(settings.isCapturePaused)
        settings.pause(until: Date(timeIntervalSinceNow: 600))
        XCTAssertTrue(settings.isCapturePaused)
        XCTAssertTrue(AppSettings(defaults: defaults).isCapturePaused, "pause survives a restart")
        settings.pause(until: nil)
        XCTAssertFalse(settings.isCapturePaused)
    }

    func testShortcutPersists() {
        let settings = AppSettings(defaults: defaults)
        settings.setShortcut(MUKHotkey(keyCode: 11, modifiers: [.option, .command]))
        XCTAssertEqual(AppSettings(defaults: defaults).shortcut, MUKHotkey(keyCode: 11, modifiers: [.option, .command]))
    }
}

final class RetentionPolicyTests: XCTestCase {
    func testCutoff() {
        let now = Date(timeIntervalSince1970: 100 * 86_400)
        XCTAssertEqual(RetentionPolicy.cutoff(days: 30, keepForever: false, now: now), Date(timeIntervalSince1970: 70 * 86_400))
        XCTAssertNil(RetentionPolicy.cutoff(days: 30, keepForever: true, now: now))
    }

    func testSliderAndField() {
        XCTAssertEqual(RetentionPolicy.sliderValue(for: 30), 30)
        XCTAssertEqual(RetentionPolicy.sliderValue(for: 33), 35)
        XCTAssertEqual(RetentionPolicy.sliderValue(for: 1), 5)
        XCTAssertEqual(RetentionPolicy.sliderValue(for: 1000), 365)
        XCTAssertEqual(RetentionPolicy.clampField(0), 1)
        XCTAssertEqual(RetentionPolicy.clampField(5000), 3650)
    }

    func testShorteningNeedsConfirmationOnlyWhenClipsWouldGo() {
        XCTAssertTrue(RetentionPolicy.needsConfirmation(affected: 3))
        XCTAssertFalse(RetentionPolicy.needsConfirmation(affected: 0))
    }
}
