import AppKit
import XCTest
@testable import ClipVault

final class PasteBatchTests: XCTestCase {
    private let png1 = Snap.item(("public.png", Data([1])))
    private let png2 = Snap.item(("public.png", Data([2])))

    func testOneClipIsOneBatch() {
        XCTAssertEqual(PasteboardWriter.batches([(kind: .image, items: [png1])], plainText: false), [[png1]])
    }

    func testSeveralTextClipsAreOneJoinedBatch() {
        let batches = PasteboardWriter.batches([(kind: .text, items: [Snap.text("a")]), (kind: .link, items: [Snap.text("b")])],
                                               plainText: false)
        XCTAssertEqual(batches, [[Snap.text("a\nb")]])
    }

    func testSeveralImagesArePastedOneByOne() {
        let batches = PasteboardWriter.batches([(kind: .image, items: [png1]), (kind: .image, items: [png2])], plainText: false)
        XCTAssertEqual(batches, [[png1], [png2]])
    }

    func testMixedClipsArePastedOneByOneAndPlainTextAppliesToText() {
        let rich = Snap.item(("public.rtf", Data("{\\rtf1 x}".utf8)), ("public.utf8-plain-text", Data("x".utf8)))
        let batches = PasteboardWriter.batches([(kind: .text, items: [rich]), (kind: .image, items: [png1])], plainText: true)
        XCTAssertEqual(batches, [[Snap.text("x")], [png1]])
    }
}

final class LazyPasteboardWriterTests: XCTestCase {
    func testReportsTheFirstReadOnceAndServesTheData() {
        let pb = NSPasteboard(name: NSPasteboard.Name("clipvault.test.\(UUID())"))
        defer { pb.releaseGlobally() }
        let writer = LazyPasteboardWriter()
        var reads = 0
        writer.write([Snap.text("hello"), Snap.item(("public.png", Data([7, 8])))], to: pb) { reads += 1 }
        XCTAssertEqual(reads, 0, "writing alone is not a read")
        XCTAssertTrue(pb.types?.contains(NSPasteboard.PasteboardType(PasteboardMarkers.own)) ?? false)
        // ClipVault's own monitor checks types only, so it never counts as a read.
        _ = PasteboardSnapshot.readIfAllowed(pb, frontmost: nil, excluded: [], maxBytes: 1_000_000)
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(pb.string(forType: .string), "hello")
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(pb.pasteboardItems?[1].data(forType: .png), Data([7, 8]))
        XCTAssertEqual(reads, 1, "reported once")
    }
}
