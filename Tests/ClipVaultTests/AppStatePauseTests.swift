import XCTest
@testable import ClipVault

@MainActor
final class AppStatePauseTests: XCTestCase {
    func testSetCapturePausedTogglesAndNotifies() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClipVaultTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "ClipVaultTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(store: try SQLiteClipStore(rootDirectory: root), settings: AppSettings(defaults: defaults))
        var notified = 0
        state.onHistoryChanged = { notified += 1 }

        state.setCapturePaused(true)
        XCTAssertTrue(state.settings.isCapturePaused)
        XCTAssertEqual(state.settings.pausedUntil, .distantFuture)
        state.setCapturePaused(false)
        XCTAssertFalse(state.settings.isCapturePaused)
        XCTAssertNil(state.settings.pausedUntil)
        XCTAssertEqual(notified, 2, "the menu-bar icon and the bar refresh on each change")
    }
}
