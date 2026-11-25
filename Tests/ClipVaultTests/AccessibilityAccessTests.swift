import XCTest
@testable import ClipVault

final class AccessibilityAccessTests: XCTestCase {
    func testResetTargetsOnlyThisAppsAccessibilityEntry() {
        XCTAssertEqual(AccessibilityAccess.resetArguments(bundleID: "com.georgecristea.ClipVault"),
                       ["reset", "Accessibility", "com.georgecristea.ClipVault"])
        XCTAssertEqual(AccessibilityAccess.tccutilPath, "/usr/bin/tccutil")
    }

    func testResetsOnlyWhenNotTrusted() {
        XCTAssertTrue(AccessibilityAccess.shouldResetBeforeRequesting(isTrusted: false))
        XCTAssertFalse(AccessibilityAccess.shouldResetBeforeRequesting(isTrusted: true))
    }
}
