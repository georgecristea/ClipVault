import AppKit
import XCTest
@testable import ClipVault

@MainActor
final class SequentialPasterTests: XCTestCase {
    private func image(_ byte: UInt8) -> [PasteboardItemData] { [Snap.item(("public.png", Data([byte])))] }

    /// A fake target app: on each ⌘V it reads the image a little later, like an app that fetches
    /// the clipboard asynchronously.
    func testEachClipIsReadInOrderAndTheLastStaysOnTheClipboard() {
        let pb = NSPasteboard(name: NSPasteboard.Name("clipvault.test.\(UUID())"))
        defer { pb.releaseGlobally() }
        var received: [Data] = []
        let done = expectation(description: "sequence finished")
        let paster = SequentialPaster(pasteboard: pb, stepTimeout: 2) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let data = pb.data(forType: .png) { received.append(data) }
            }
        }
        paster.paste([image(1), image(2), image(3)]) { done.fulfill() }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(received, [Data([1]), Data([2]), Data([3])])
        XCTAssertEqual(pb.data(forType: .png), Data([3]))
        XCTAssertTrue(pb.types?.contains(NSPasteboard.PasteboardType(PasteboardMarkers.own)) ?? false)
    }

    /// An app that never reads the clipboard must not stall the sequence.
    func testMovesOnWhenTheTargetNeverReads() {
        let pb = NSPasteboard(name: NSPasteboard.Name("clipvault.test.\(UUID())"))
        defer { pb.releaseGlobally() }
        var presses = 0
        let done = expectation(description: "sequence finished")
        let paster = SequentialPaster(pasteboard: pb, stepTimeout: 0.1) { presses += 1 }
        paster.paste([image(1), image(2)]) { done.fulfill() }
        wait(for: [done], timeout: 3)
        XCTAssertEqual(presses, 2)
    }

    func testASingleBatchIsOnePress() {
        let pb = NSPasteboard(name: NSPasteboard.Name("clipvault.test.\(UUID())"))
        defer { pb.releaseGlobally() }
        var presses = 0
        let done = expectation(description: "done")
        SequentialPaster(pasteboard: pb, stepTimeout: 1) { presses += 1 }.paste([image(9)]) { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(presses, 1)
    }
}
