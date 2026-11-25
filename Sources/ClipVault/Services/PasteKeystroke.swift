import AppKit
import MacUtilityKit

/// Sends ⌘V to the frontmost app.
///
/// The events come from a private event source (so keys the user is still holding, such as ⇧
/// from ⇧Return, don't leak in) and are posted at the session level, which delivers them to the
/// frontmost application. Posting at the HID level instead follows keyboard focus, which can
/// still be on ClipVault's panel just after it closes; the keystroke then lands in ClipVault and
/// the user hears a beep.
enum PasteKeystroke {
    static let sourceState: CGEventSourceStateID = .privateState
    static let tap: CGEventTapLocation = .cgAnnotatedSessionEventTap

    static func makeEvents(keyCode: CGKeyCode) -> (down: CGEvent, up: CGEvent)? {
        let source = CGEventSource(stateID: sourceState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return nil }
        down.flags = .maskCommand
        up.flags = .maskCommand
        return (down, up)
    }

    /// Posts ⌘V, using the key that types "v" with ⌘ held in the current layout. Returns false
    /// without Accessibility permission.
    @MainActor
    @discardableResult
    static func send() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let keyCode = MUKKeyboardLayout.keyCode(for: "v", commandHeld: true) ?? 9
        guard let (down, up) = makeEvents(keyCode: keyCode) else { return false }
        down.post(tap: tap)
        up.post(tap: tap)
        return true
    }
}
