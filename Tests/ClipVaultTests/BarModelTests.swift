import AppKit
import XCTest
@testable import ClipVault

@MainActor
final class BarModelTests: XCTestCase {
    private func item(_ id: String) -> ClipboardItem {
        ClipboardItem(id: id, kind: .text, createdAt: Date(), updatedAt: Date(), sha256: id, preview: id,
                      payloadPath: "\(id).clip", byteCount: 1)
    }

    private func model(_ ids: [String]) -> BarModel {
        let model = BarModel()
        model.apply(items: ids.map(item), pinboards: [Pinboard(id: 7, name: "P", position: 0)])
        return model
    }

    func testApplyPutsCursorOnFirstItem() {
        let m = model(["a", "b", "c"])
        XCTAssertEqual(m.cursor, "a")
        XCTAssertEqual(m.selection, ["a"])
    }

    func testApplyKeepsCursorWhenItemStillShown() {
        let m = model(["a", "b"])
        m.move(by: 1)
        m.apply(items: ["c", "a", "b"].map(item), pinboards: [], resetCursor: false)
        XCTAssertEqual(m.cursor, "b")
    }

    func testMoveClampsAtBothEnds() {
        let m = model(["a", "b", "c"])
        m.move(by: -1)
        XCTAssertEqual(m.cursor, "a")
        m.move(by: 10)
        XCTAssertEqual(m.cursor, "c")
        m.move(by: -1, extend: true)
        XCTAssertEqual(m.selection, ["b", "c"])
    }

    func testCommandClickTogglesAndShiftClickSelectsRange() {
        let m = model(["a", "b", "c", "d"])
        m.click(item("c"), modifiers: .command)
        XCTAssertEqual(m.selection, ["a", "c"])
        m.click(item("a"), modifiers: .command)
        XCTAssertEqual(m.selection, ["c"])
        m.click(item("d"), modifiers: .shift)
        XCTAssertEqual(m.selection, ["c", "d"])
        XCTAssertEqual(m.selectedItems.map(\.id), ["c", "d"])
        m.click(item("b"), modifiers: [])
        XCTAssertEqual(m.selection, ["b"])
    }

    func testSwitchTabWraps() {
        let m = model(["a"])
        XCTAssertEqual(m.tab, .history)
        m.switchTab(by: 1)
        XCTAssertEqual(m.tab, .pinboard(7))
        m.switchTab(by: 1)
        XCTAssertEqual(m.tab, .history)
        m.switchTab(by: -1)
        XCTAssertEqual(m.tab, .pinboard(7))
    }

    func testEmptyHistoryHasNoSelection() {
        let m = model([])
        XCTAssertNil(m.cursor)
        XCTAssertEqual(m.selectedItems, [])
        m.move(by: 1)
        XCTAssertNil(m.cursor)
    }

    func testNothingIsActionableWhileLoading() {
        let m = model(["a", "b"])
        m.beginLoading()
        XCTAssertEqual(m.actionableItems, [])
        XCTAssertNil(m.quickItem(at: 1))
        m.apply(items: ["c"].map(item), pinboards: [])
        XCTAssertEqual(m.actionableItems.map(\.id), ["c"])
        XCTAssertEqual(m.quickItem(at: 1)?.id, "c")
        XCTAssertNil(m.quickItem(at: 2))
    }
}
