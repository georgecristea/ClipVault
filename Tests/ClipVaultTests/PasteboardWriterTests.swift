import AppKit
import XCTest
@testable import ClipVault

final class PasteboardWriterTests: XCTestCase {
    private let rich = Snap.item(("public.rtf", Data("{\\rtf1 bold}".utf8)), ("public.utf8-plain-text", Data("bold".utf8)))

    func testSingleClipKeepsAllRepresentations() {
        let plan = PasteboardWriter.plan([(kind: .text, items: [rich])], plainText: false)
        XCTAssertEqual(plan, [rich])
    }

    func testPlainTextDropsFormatting() {
        let plan = PasteboardWriter.plan([(kind: .text, items: [rich])], plainText: true)
        XCTAssertEqual(plan, [Snap.text("bold")])
    }

    func testSeveralTextClipsAreJoined() {
        let plan = PasteboardWriter.plan([(kind: .text, items: [rich]), (kind: .link, items: [Snap.text("https://a.b")])],
                                         plainText: false)
        XCTAssertEqual(plan, [Snap.text("bold\nhttps://a.b")])
    }

    func testSeveralImagesBecomeSeparateItems() {
        let a = Snap.item(("public.png", Data([1])))
        let b = Snap.item(("public.png", Data([2])))
        let plan = PasteboardWriter.plan([(kind: .image, items: [a]), (kind: .image, items: [b])], plainText: true)
        XCTAssertEqual(plan, [a, b])
    }

    func testWrittenItemsAreTaggedAndNotRecaptured() {
        let pb = NSPasteboard(name: NSPasteboard.Name("clipvault.test.\(UUID())"))
        defer { pb.releaseGlobally() }
        PasteboardWriter.write([Snap.text("x"), Snap.item(("public.png", Data([1, 2])))], to: pb)
        XCTAssertEqual(pb.pasteboardItems?.count, 2)
        XCTAssertEqual(pb.string(forType: .string), "x")
        XCTAssertTrue(ClipboardClassifier.shouldIgnore(PasteboardSnapshot.read(pb, maxBytes: 1_000_000)))
    }
}
