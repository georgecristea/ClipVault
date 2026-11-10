import AppKit
import XCTest
@testable import ClipVault

final class ClipboardClassifierTests: XCTestCase {
    private struct FakePasteboard: PasteboardReading {
        var strings: [NSPasteboard.PasteboardType: String] = [:]
        var datas: [NSPasteboard.PasteboardType: Data] = [:]
        var urls: [URL] = []
        var types: [String] = []

        func string(forType type: NSPasteboard.PasteboardType) -> String? { strings[type] }
        func data(forType type: NSPasteboard.PasteboardType) -> Data? { datas[type] }
        func fileURLs() -> [URL] { urls }
        func typeIdentifiers() -> [String] { types }
    }

    func testTextClassification() {
        let pb = FakePasteboard(strings: [.string: "hello world"])
        let capture = ClipboardClassifier.capture(from: pb)
        XCTAssertEqual(capture?.kind, .text)
        XCTAssertEqual(capture?.preview, "hello world")
        XCTAssertEqual(capture?.fileExtension, "txt")
    }

    func testEmptyTextIsNotCaptured() {
        let pb = FakePasteboard(strings: [.string: ""])
        XCTAssertNil(ClipboardClassifier.capture(from: pb))
    }

    func testMultilineTextPreviewCollapsesWhitespace() {
        let pb = FakePasteboard(strings: [.string: "line one\n\n   line two\t"])
        XCTAssertEqual(ClipboardClassifier.capture(from: pb)?.preview, "line one line two")
    }

    func testFilesTakePrecedenceOverText() {
        let pb = FakePasteboard(
            strings: [.string: "ignored"],
            urls: [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.txt")])
        let capture = ClipboardClassifier.capture(from: pb)
        XCTAssertEqual(capture?.kind, .files)
        XCTAssertEqual(capture?.preview, "2 files")
    }

    func testSingleFilePreviewUsesFilename() {
        let pb = FakePasteboard(urls: [URL(fileURLWithPath: "/tmp/report.pdf")])
        XCTAssertEqual(ClipboardClassifier.capture(from: pb)?.preview, "report.pdf")
    }

    func testImageClassificationFromPNGData() throws {
        let image = NSImage(size: NSSize(width: 12, height: 8))
        image.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 12, height: 8).fill(); image.unlockFocus()
        let png = try XCTUnwrap(image.clipVaultPNGData)
        let pb = FakePasteboard(datas: [.png: png])
        XCTAssertEqual(ClipboardClassifier.capture(from: pb)?.kind, .image)
    }

    func testConcealedTypeIsIgnored() {
        let pb = FakePasteboard(strings: [.string: "secret"], types: ["org.nspasteboard.ConcealedType"])
        XCTAssertTrue(ClipboardClassifier.shouldIgnore(pb))
    }

    func testNormalTypesAreNotIgnored() {
        let pb = FakePasteboard(types: ["public.utf8-plain-text"])
        XCTAssertFalse(ClipboardClassifier.shouldIgnore(pb))
    }
}
