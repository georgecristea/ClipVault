import XCTest
@testable import ClipVault

final class PasteTimingTests: XCTestCase {
    func testWaitsUntilTheTargetHasFocusAndClipVaultHasLetGo() {
        // ClipVault still active or still holding a key window: not yet.
        XCTAssertFalse(BarController.readyToPaste(frontmostPID: 1, targetPID: 2, clipVaultIsActive: false, clipVaultHasKeyWindow: false))
        XCTAssertFalse(BarController.readyToPaste(frontmostPID: 2, targetPID: 2, clipVaultIsActive: true, clipVaultHasKeyWindow: false))
        XCTAssertFalse(BarController.readyToPaste(frontmostPID: 2, targetPID: 2, clipVaultIsActive: false, clipVaultHasKeyWindow: true))
        // The target app is frontmost and ClipVault has no focus.
        XCTAssertTrue(BarController.readyToPaste(frontmostPID: 2, targetPID: 2, clipVaultIsActive: false, clipVaultHasKeyWindow: false))
        // Unknown target: only require that ClipVault let go.
        XCTAssertTrue(BarController.readyToPaste(frontmostPID: 5, targetPID: nil, clipVaultIsActive: false, clipVaultHasKeyWindow: false))
    }
}
