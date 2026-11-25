import CoreGraphics
import XCTest
@testable import ClipVault

final class PasteKeystrokeTests: XCTestCase {
    /// ⌘V goes to the frontmost app through the session tap from a private source, the way the
    /// reference app (and Flotsam) send it; the HID tap follows keyboard focus, which can still
    /// sit with ClipVault's panel after it closes.
    func testUsesPrivateSourceAndSessionTap() {
        XCTAssertEqual(PasteKeystroke.sourceState, .privateState)
        XCTAssertEqual(PasteKeystroke.tap, .cgAnnotatedSessionEventTap)
    }

    func testEventsAreCommandV() throws {
        let (down, up) = try XCTUnwrap(PasteKeystroke.makeEvents(keyCode: 9))
        XCTAssertEqual(down.getIntegerValueField(.keyboardEventKeycode), 9)
        XCTAssertEqual(down.flags, .maskCommand)
        XCTAssertEqual(up.flags, .maskCommand)
        XCTAssertEqual(down.type, .keyDown)
        XCTAssertEqual(up.type, .keyUp)
    }
}
