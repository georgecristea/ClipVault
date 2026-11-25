import AppKit
import XCTest
@testable import ClipVault

@MainActor
final class StatusIconTests: XCTestCase {
    func testIconIsAlwaysTheClipboardAndMarksPause() {
        let running = StatusBarController.statusImage(paused: false)
        let paused = StatusBarController.statusImage(paused: true)
        XCTAssertTrue(running.isTemplate)
        XCTAssertTrue(paused.isTemplate)
        XCTAssertEqual(running.accessibilityDescription, "ClipVault")
        XCTAssertEqual(paused.accessibilityDescription, "ClipVault (capture paused)")
        XCTAssertEqual(paused.size, running.size, "the paused icon keeps the same footprint")
    }
}
