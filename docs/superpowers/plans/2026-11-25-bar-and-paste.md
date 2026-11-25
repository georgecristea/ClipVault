# Bottom bar, global shortcut and paste-back Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace ClipVault's popover list with a Flotsam-style bottom bar opened by ⇧⌘V. Clips
paste straight into the active app. Add full-fidelity capture, global dedup, pinboards,
preview, timed pause and the new retention control.

**Architecture:** Additive MacUtilityKit 0.2.0 provides the Carbon hotkey and the
layout-aware paste. ClipVault keeps its actor-based `SQLiteClipStore` and payload files. The
payload becomes a versioned binary plist of all pasteboard items, and legacy payloads are still
read. The bar is an AppKit non-activating panel hosting SwiftUI. It is ported from
`~/repos/flotsam/Sources/Flotsam/Bar*.swift` and `CardView.swift`, then adapted to
`ClipboardItem`, the async store and MUKTheme.

**Tech Stack:** Swift 5.9 packages, macOS 14+, SwiftUI and AppKit, Carbon, SQLite3, XCTest.

**Spec:** `docs/superpowers/specs/2026-11-25-bar-and-paste-design.md`

## Global Constraints

- macOS 14 minimum (ClipVault); MacUtilityKit stays at macOS 13.
- MacUtilityKit changes are additive only. No existing public signature changes. VoxKey
  (resolved 0.1.1) and upkeep (0.1.0) must build and test unchanged against 0.2.0.
- Default shortcut ⇧⌘V (`keyCode 9`, modifiers `[.command, .shift]`).
- Poll interval stays 0.75 s. Payload cap stays 100 MB per clip.
- Retention: slider 5–365 in steps of 5; field 1–3650; default 30 for new installs only.
- No network and no telemetry. Storage hardening is kept: 0600 permissions, secure delete,
  backup exclusion.
- Work happens on branches `feature/carbon-hotkey-layout-paste` (MacUtilityKit) and
  `feature/bar-and-paste` (ClipVault). Pull requests are merged only after CI is green and the
  validation steps have passed.

## Review Focus

1. **A database from 0.1.x with pinned and legacy payloads:** it migrates, old clips still
   paste, and pinned clips land in "Pinned". *Task 5 migration test.*
2. **A clip copied while ClipVault's own write is on the pasteboard:** it is never
   re-captured. *Task 6 test with the own marker.*
3. **Accessibility not granted:** Return copies only, and the bar closes without posting
   keys. *Task 7 manual check, plus a `PasteAction` unit test.*
4. **An empty history or no search matches:** the bar shows an empty state, and Return or
   ⌘1–9 do nothing. *Task 7 `BarModel` test.*
5. **A retention change that would delete clips:** ClipVault asks first; "Keep previous"
   restores the old value. *Task 8 test on `RetentionPolicy`.*

---

### Task 1 (MacUtilityKit): keyboard layout and layout-aware paste

**Files:**
- Create: `Sources/MacUtilityKit/MUKKeyboardLayout.swift`
- Modify: `Sources/MacUtilityKit/MUKPasteInjector.swift` (keycode lookup in `sendPasteShortcut`)
- Modify: `Package.swift` (add `testTarget MacUtilityKitTests`)
- Test: `Tests/MacUtilityKitTests/MUKKeyboardLayoutTests.swift`

**Interfaces — produces:**
- `public enum MUKKeyboardLayout { static func character(for keyCode: CGKeyCode) -> String?; static func keyCode(for character: String) -> CGKeyCode? }`.
  It uses `UCKeyTranslate` with the current layout input source, and returns lowercase
  characters with no modifiers.

- [ ] Test `testRoundTrip`: for every key code 0..<128 whose `character(for:)` is a single
  letter, `keyCode(for: c) == thatCode` or maps to the same character. `testVExists`:
  `keyCode(for: "v") != nil`.
- [ ] Run `swift test`: it fails because the type is missing.
- [ ] Implement it. Make `sendPasteShortcut` use `MUKKeyboardLayout.keyCode(for: "v") ?? 9`.
- [ ] `swift build && swift test` pass.
- [ ] Commit `feat: layout-aware paste key and keyboard layout helper`.

### Task 2 (MacUtilityKit): Carbon hotkey and recorder option

**Files:**
- Create: `Sources/MacUtilityKit/MUKCarbonHotKey.swift`
- Modify: `Sources/MacUtilityKit/MUKHotkeyRecorder.swift` (an `allowsModifierOnly` init param, default `true`)
- Modify: `README.md`, `CLAUDE.md` (export list)
- Test: `Tests/MacUtilityKitTests/MUKCarbonHotKeyTests.swift`

**Interfaces — produces:**
- `@MainActor public final class MUKCarbonHotKey { init(binding: MUKHotkey, onTrigger: @escaping () -> Void); var isRegistered: Bool { get }; @discardableResult func update(binding: MUKHotkey) -> Bool; func stop() }`.
  - It registers in `init`. A binding without a `keyCode`, or one Carbon refuses, gives
    `isRegistered == false`.
- `static func carbonModifiers(_ m: MUKHotkey.Modifiers) -> UInt32` (internal; tested).
- `MUKHotkeyRecorder(hotkey:allowsModifierOnly:)`: when `false`, a modifier-only release does
  not commit.

- [ ] Tests:
  - `carbonModifiers([.command, .shift]) == UInt32(cmdKey | shiftKey)`.
  - A rare combo (⌃⌥⇧⌘F19) registers: `isRegistered == true`. After `stop()` it is false.
  - `MUKHotkey(keyCode: nil, modifiers: [.command])` gives `isRegistered == false`.
- [ ] Run: fails. Implement (one shared Carbon event handler, ids mapped to closures,
  dispatched on main). Tests pass.
- [ ] Commit `feat: MUKCarbonHotKey (Carbon global shortcut) and recorder option`.

### Task 3 (MacUtilityKit): validate consumers, PR, merge, tag

- [ ] VoxKey: `swift package edit MacUtilityKit --path ../MacUtilityKit`, then
  `swift build && swift test`, then `swift package unedit MacUtilityKit`. `git status` must be
  clean.
- [ ] The same for upkeep and for ClipVault on main (an unchanged build against 0.2.0 code).
- [ ] Push the branch, `gh pr create`, wait for CI to go green, then
  `gh pr merge --squash --delete-branch`.
- [ ] On main: `git tag 0.2.0 && git push origin 0.2.0`.

### Task 4 (ClipVault): capture model and classifier

**Files:**
- Modify: `Sources/ClipVault/Models/ClipboardItem.swift`
- Rewrite: `Sources/ClipVault/Services/ClipboardClassifier.swift`
- Create: `Sources/ClipVault/Services/PasteboardItems.swift`
- Test: `Tests/ClipVaultTests/ClipboardClassifierTests.swift` (rewrite)

**Interfaces — produces:**
- `enum ClipboardKind: String { case text, image, files, link, color }`.
- `struct PasteboardRepresentation: Equatable, Sendable { let type: String; let data: Data }`
  and `typealias PasteboardItemData = [PasteboardRepresentation]`.
- `enum PasteboardMarkers` with:
  - `concealed`, `transient`, `autoGenerated`, `source`, `legacyTransient: [String]`, and
    `own = "com.georgecristea.ClipVault.marker"`;
  - `static func isStorable(_ type: String) -> Bool`, which excludes markers and Office/OLE
    link types.
- `struct PasteboardSnapshot { items: [PasteboardItemData]; types: Set<String>; declaredSource: String? }`,
  plus `static func read(_ pb: NSPasteboard, maxBytes: Int) -> PasteboardSnapshot`.
- `struct ClipboardCapture: Sendable { kind; items: [PasteboardItemData]; preview: String; searchText: String; contentKey: Data }`.
  `preview` is at most 240 characters, collapsed. `searchText` is at most 20 000 characters.
  `contentKey` is the dedup input.
- `ClipboardClassifier.capture(from snapshot: PasteboardSnapshot) -> ClipboardCapture?`
  - Priority: files, then text-like (a single string that is a colour `^#?[A-Fa-f0-9]{6}$`, a
    single string that is an http(s)/mailto link, otherwise text), then image (png, tiff, jpeg,
    heic, gif), otherwise nil.
  - `contentKey`: joined file paths, the joined UTF-8 text, or the first image's bytes.
- `ClipboardClassifier.shouldIgnore(_ snapshot:) -> Bool`: true for the own marker or any
  concealed or transient marker.
- `ClipboardItem` gains `title: String?`, `pinboardID: Int64?`, `lastCopiedAt: Date`.
  `pinned` becomes the computed `pinboardID != nil`.

- [ ] Port Flotsam's `ClassifierTests` and `CaptureFilterTests`, adapted to these names. Add
  `testSnapshotSkipsMarkersAndStoresAllItems` using a named pasteboard (two items, rtf plus
  string).
- [ ] Run: fails. Implement. Tests pass.
- [ ] Commit `feat: full-fidelity capture model with link and colour kinds`.

### Task 5 (ClipVault): store migration, dedup, pinboards, retention queries

**Files:**
- Modify: `Sources/ClipVault/Storage/ClipStore.swift`, `Sources/ClipVault/Storage/ClipboardStore.swift`
- Create: `Sources/ClipVault/Storage/PayloadCodec.swift`
- Test: `Tests/ClipVaultTests/SQLiteClipStoreTests.swift` (extend)

**Interfaces — produces:**
- `struct Pinboard: Identifiable, Equatable, Sendable { let id: Int64; var name: String; var position: Int }`.
- `protocol ClipStore` with these methods:
  - `fetchItems(limit: Int, query: String?, pinboardID: Int64?) async throws -> [ClipboardItem]`:
    history ordered by `last_copied_at DESC`; a pinboard ordered by `pin_order`.
  - `save(_ capture: ClipboardCapture, sourceBundleID: String?, at date: Date) async throws -> ClipboardItem`:
    dedups on `hash(kind, contentKey)` against all rows and bumps `last_copied_at`.
  - `payloadItems(for item: ClipboardItem) async throws -> [PasteboardItemData]`:
    legacy-aware.
  - `touch(_ ids: [String]) async throws`
  - `setTitle(_ title: String?, for id: String) async throws`
  - `delete(_ ids: [String]) async throws`
  - `pinboards() async throws -> [Pinboard]`
  - `createPinboard(name: String) async throws -> Pinboard`
  - `renamePinboard(id: Int64, name: String) async throws`
  - `deletePinboard(id: Int64) async throws`
  - `pin(_ ids: [String], to pinboardID: Int64?) async throws`
  - `deleteItems(olderThan date: Date) async throws -> Int`: unpinned only.
  - `countItems(olderThan date: Date) async throws -> Int`
  - `eraseHistory() async throws -> Int`: unpinned only.
  - `summary() async throws -> (count: Int, bytes: Int)`
- `PayloadCodec`:
  - `encode(_ items: [PasteboardItemData]) throws -> Data`: a binary plist of
    `[[["type": String, "data": Data]]]`.
  - `decode(_ data: Data, format: String, kind: ClipboardKind) throws -> [PasteboardItemData]`:
    - `"items-v1"` decodes the plist.
    - `"legacy"` maps text to `public.utf8-plain-text`, an image to `public.png`, and files
      (a JSON path list) to one `public.file-url` item per path.
- Migration, idempotent and keyed on `PRAGMA user_version` 0 → 1:
  - Add the columns `payload_format TEXT DEFAULT 'legacy'`, `search_text TEXT`, `title TEXT`,
    `pinboard_id INTEGER`, `pin_order INTEGER DEFAULT 0` and `last_copied_at REAL`. Backfill
    `last_copied_at = created_at` and `search_text = preview`.
  - Create the table `pinboards(id, name, position)`.
  - If any row has `pinned = 1`, create a pinboard named "Pinned" and assign those rows to it.

- [ ] Tests:
  - `testMigratesLegacyDatabase`: build a v0 database with raw SQL plus legacy payload files
    (text, png and files, one pinned). Open the store. Then: all rows load; `payloadItems`
    returns the mapped types; "Pinned" exists and holds the pinned row.
  - `testDuplicateMovesToFrontKeepingTitleAndPinboard`.
  - `testSearchAllWordsAcrossTextAndTitle`.
  - `testPinboardOrderAndDeleteKeepsClips`.
  - `testRetentionSparesPinboards` (with `countItems` == `deleteItems`).
  - `testEraseHistoryKeepsPinned`.
- [ ] Run: fails. Implement. Update the `fetchItems` callers (Task 7 replaces the UI ones).
  Tests pass.
- [ ] Commit `feat: store migration, global dedup, pinboards, titles`.

### Task 6 (ClipVault): monitor and pasteboard writer

**Files:**
- Modify: `Sources/ClipVault/Services/ClipboardMonitor.swift`
- Create: `Sources/ClipVault/Services/PasteboardWriter.swift`
- Test: `Tests/ClipVaultTests/PasteboardWriterTests.swift`

**Interfaces — produces:**
- `PasteboardWriter.plan(_ sources: [(kind: ClipboardKind, items: [PasteboardItemData])], plainText: Bool) -> [PasteboardItemData]`
  - One clip: its items unchanged; with `plainText`, its plain string only (images and files
    are unchanged).
  - Several text, link or colour clips: one item with the texts joined by "\n".
  - Several clips of other kinds: their items concatenated.
- `PasteboardWriter.write(_ items: [PasteboardItemData], to pb: NSPasteboard) -> Int` tags every
  item with `PasteboardMarkers.own` and returns the change count.
- The monitor:
  - Reads a `PasteboardSnapshot` and drops it when `shouldIgnore` is true.
  - Drops it when the frontmost or declared source is excluded.
  - Classifies it and saves it.
  - Checks `settings.isCapturePaused` (timed or indefinite).
  - Removes `restore(_:)`; `AppState.copy/paste` (Task 7) replaces it.

- [ ] Port Flotsam's `PasteboardWriterTests`, adapted, including the round trip in which the
  own marker makes `shouldIgnore == true`.
- [ ] Run: fails. Implement. Tests pass.
- [ ] Commit `feat: pasteboard writer and marker-aware monitor`.

### Task 7 (ClipVault): the bar, shortcut, paste, preview, menu

**Files:**
- Create: `Sources/ClipVault/UI/Bar/BarPanel.swift`, `BarModel.swift`, `BarController.swift`,
  `BarView.swift`, `ClipCardView.swift`, `ScreenLocator.swift`
- Create: `Sources/ClipVault/UI/SettingsWindowController.swift`
- Modify: `StatusBarController.swift` (menu, not popover), `MainPopoverView.swift` (settings
  screens only: `.settings`, `.exclusions`, `.about`), `AppState.swift`, `AppDelegate.swift`,
  `AppSettings.swift` (shortcut, pause-until, paste mode, plain text)
- Delete: `UI/HistoryView.swift`, `UI/HistoryRowView.swift`, `UI/KeyboardMonitor.swift`
- Test: `Tests/ClipVaultTests/BarModelTests.swift`

**Interfaces:**
- Consumes the `ClipStore` methods (Task 5), `PasteboardWriter` (Task 6), `MUKCarbonHotKey`,
  `MUKPasteInjector`, `MUKPreviewPanel` and `ClipPreview`/`ClipPreviewView` (existing).
- `@MainActor final class BarModel: ObservableObject`:
  - Published state: `items`, `pinboards`, `tab: BarTab (.history | .pinboard(Int64))`,
    `query`, `cursor: String?`, `selection: Set<String>`.
  - Methods: `move(by:extend:)`, `click(_:modifiers:)`, `switchTab(by:)`, `apply(items:pinboards:)`
    (pure, tested), and `selectedItems` in display order.
- `AppState`:
  - `paste(_ items: [ClipboardItem], plainText: Bool)` writes, touches, closes the bar, then
    calls `MUKPasteInjector().paste()` if `settings.pasteIntoActiveApp`. If not trusted, it
    calls `AXIsProcessTrustedWithOptions(prompt)` once per session.
  - `copy(_:)` writes and touches only.
- Keys in the bar:
  - ←/→ move (⇧ extends); ⌘←/⌘→ switch tabs.
  - Return pastes; ⇧Return pastes as plain text; ⌘1–9 quick-paste.
  - Typing searches; ⌫ edits the search; ⌘⌫ deletes.
  - ⌘C copies; ⌘A selects all; ⌘P pins to "Pinned" (it creates it if missing) or unpins.
  - Space toggles the preview; ⌘, opens settings; Esc clears the search or closes the bar.
- Menu items: Show Clipboard (⇧⌘V, shown as the current shortcut); Pause ▸ (15 min, 1 h, 8 h,
  Until Resumed, or Resume when paused); Settings…; About ClipVault; Quit. The icon is
  `doc.on.clipboard`, or `pause.circle` while paused.

- [ ] `BarModelTests`:
  - The cursor resets to the first item on `apply`.
  - `move` clamps at both ends.
  - ⌘-click toggles selection, and ⇧-click selects a range.
  - `switchTab` wraps around.
  - Empty items mean the cursor is nil and `selectedItems` is empty.
- [ ] Run: fails. Implement by porting the Flotsam bar. Styling: use `MUKTheme.accent` for the
  selection, `.regularMaterial`/`.hudWindow` for the background, and `MUKTheme.cardRadius`.
  Tests pass, and `swift build` is clean of warnings in new files.
- [ ] Install with `./scripts/install.sh`. Then use the hook notification
  `com.georgecristea.ClipVault.toggleBar` (debug/automation, as in Flotsam) and `screencapture`
  to check that the bar renders with history, tabs and the empty states.
- [ ] Commit `feat: bottom bar with ⇧⌘V, paste into app, preview, menu-bar menu`.

### Task 8 (ClipVault): settings — shortcut, paste, retention, exclusions

**Files:**
- Modify: `UI/SettingsView.swift`, `UI/ExclusionsView.swift`, `App/AppSettings.swift`
- Create: `App/RetentionPolicy.swift`
- Test: `Tests/ClipVaultTests/RetentionPolicyTests.swift`, `AppSettingsTests.swift`

**Interfaces — produces:**
- `enum RetentionPolicy`:
  - `sliderRange = 5...365`, `step = 5`, `fieldRange = 1...3650`.
  - `sliderValue(for:) -> Int`, `clampField(_:) -> Int`.
  - `cutoff(days: Int, keepForever: Bool, now: Date) -> Date?`.
- `AppSettings`:
  - New stored values: `shortcut: MUKHotkey` (default ⇧⌘V), `pasteIntoActiveApp: Bool = true`,
    `alwaysPlainText: Bool = false`, and `pausedUntil: Date?`, which replaces `capturePaused`.
    The old `capturePaused == true` migrates to `.distantFuture`.
  - Computed: `isCapturePaused`.
  - New installs default to `retentionDays = 30`: register only when the key is absent and
    `excludedBundleIDs` is unset.
- Settings rows (MUKSettingsRow):
  - Show the bar: `MUKHotkeyRecorder(hotkey:, allowsModifierOnly: false)`; a refused
    registration reverts with a warning.
  - Paste into the active app (toggle), plus an Accessibility status row with "Grant…".
  - Always paste as plain text.
  - Retention: forever toggle, slider and field. Shortening asks to delete N clips through
    `countItems`; "Keep previous" reverts.
  - App exclusions, now with "Add app…" (`NSOpenPanel`, `.application`).
  - Erase history, with a confirmation; it keeps pinboards.
  - Launch at login (unchanged) and About.

- [ ] Tests:
  - `RetentionPolicyTests` (as in Flotsam's).
  - `AppSettingsTests.testLegacyPausedMigrates` (a suite `UserDefaults` with
    `capturePaused = true` gives `isCapturePaused == true`).
  - `testExistingRetentionKept` (a suite with `retentionDays = 7` keeps 7).
- [ ] Run: fails. Implement. Tests pass.
- [ ] Commit `feat: settings for shortcut, paste mode, retention and exclusions`.

### Task 9 (ClipVault): demo snapshot, signing, docs, version

**Files:**
- Modify: `App/DemoMode.swift` (sample clips include a link, a colour and a "Snippets"
  pinboard; the snapshot renders `BarView` at 1400×320), `scripts/package-app.sh`
  (`LOCAL_SIGN_NAME` "Local Code Signing", as in VoxKey), `Packaging/Info.plist` (0.2.0),
  `Package.swift` (MacUtilityKit `from: "0.2.0"`), `Package.resolved`, `README.md`,
  `CLAUDE.md`, `docs/screenshot.png`

- [ ] Run `swift run ClipVault --demo --snapshot docs/screenshot.png` and look at the PNG.
- [ ] Rewrite the README to cover the bar, ⇧⌘V, the keyboard table, paste and Accessibility,
  pinboards, preview, retention and pause.
- [ ] `swift build && swift test` pass. Commit `docs: bar screenshot, README, 0.2.0`.

### Task 10: validate, PR, merge, reinstall

- [ ] `swift test` (all), `./scripts/install.sh`, and check that the signature uses the local
  certificate (`codesign -d -r-`).
- [ ] Smoke test through the hook and screenshots on George's real ClipVault database: the
  migration keeps the history, and the bar shows it.
  - Live capture with the general pasteboard is not exercised here. Paste.app is running and
    would record the test copies. Capture is covered by named-pasteboard unit tests.
  - Back up `~/Library/Application Support/ClipVault` first.
- [ ] Fresh-eyes code review of the full diff (superpowers:requesting-code-review), then fix
  the findings.
- [ ] Push, open the PR, wait for CI to go green, then `gh pr merge --squash --delete-branch`.
  `git switch main && git pull`, and `./scripts/install.sh` from main.
- [ ] Report the manual checks George must do (keys, paste, two displays).
