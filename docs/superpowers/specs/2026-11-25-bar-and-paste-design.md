# ClipVault: bottom bar, global shortcut and paste-back

Approved by George on 2026-11-25, from a feature-by-feature comparison with the Flotsam
prototype (`~/repos/flotsam`). Flotsam is the reference for behaviour; ClipVault stays the
product. Numbers refer to that comparison.

## What changes for the user

1. **The bar replaces the popover list (#1).** It is a full-width panel docked to the bottom
   of the screen the user is working on (the screen with the frontmost app's focused window,
   otherwise the screen under the mouse pointer). It shows the history as horizontal cards:
   a header coloured by the source app, with the app icon, a title or kind label and a relative
   date; a body per kind; and a footer with details and a ⌘1–⌘9 hint. A row along the top holds
   type-to-search and tabs (History, then pinboards).
2. **Global shortcut (#2).** ⇧⌘V shows and hides the bar from any app. It needs no permission,
   it is consumed (the frontmost app does not see it), and it can be changed in Settings.
3. **Search (#3).** Every word typed must appear in the clip's full text or its title,
   case-insensitively. Esc clears the search, then closes the bar.
4. **Paste into the app (#4).** Return or a double-click pastes into the app that was active.
   This needs Accessibility. Without it, or with "Paste into the active app" switched off, the
   clip is only copied. ⇧Return pastes as plain text. Several selected cards paste together:
   text is joined with newlines; other kinds become separate pasteboard items.
5. **Full fidelity (#5, #6).** Every pasteboard item and type is stored (rich text, HTML,
   URLs, several files), up to 100 MB per clip. There are new kinds: link and colour.
6. **No duplicates (#7).** Copying content that is already stored moves the existing clip to
   the front and keeps its title and pinboard.
7. **Pinboards (#8).** These are named lists shown as tabs and switched with ⌘←/⌘→. You can
   pin, unpin, create, rename and delete a pinboard. Deleting a pinboard keeps its clips in
   history. Clips on a pinboard never expire. Existing pinned clips move to a pinboard named
   "Pinned".
8. **Storage stays hardened (#9).** The store keeps running off the main thread, keeps payload
   files owner-only, keeps secure delete and vacuum, and stays excluded from backups. Existing
   databases are migrated in place; old clips keep working.
9. **Preview (#10).** Space shows the full clip (text, image or file list) above the bar, and
   Space or Esc hides it.
10. **Pause (#13).** It is in the menu-bar menu: 15 minutes, 1 hour, 8 hours, or until resumed.
    The state is remembered across restarts and shown on the menu-bar icon.
11. **Retention (#14).** A slider in 5-day steps (5–365) plus a number field (1–3650), kept in
    sync, or "Keep forever". The default for new installs is 30 days; existing users keep their
    value. Shortening the period asks before deleting older clips.
12. **Exclusions (#15, #16).** The one-click "exclude the current app" stays, and an app picker
    is added. Extra defaults (Apple Passwords, older 1Password, Enpass, Keeper, RoboForm) apply
    to new installs. Concealed, transient and auto-generated markers, plus the older transient
    markers, are always skipped. Apps declared through `org.nspasteboard.source` are checked
    against the exclusions. ClipVault tags its own writes, so it never re-captures them.
13. **Menu-bar icon (#17).** It shows a menu: Show Clipboard (with the shortcut), Pause ▸,
    Settings…, About ClipVault, Quit. Settings, exclusions and About open in a small window that
    reuses the existing MacUtilityKit-styled screens.
14. **Titles (#18).** You can rename a clip from its context menu. The title shows on the card
    and is searched.
15. **Signing (#22).** Packaging signs with the "Local Code Signing" certificate when present
    (as VoxKey does), so the Accessibility grant survives rebuilds.

Not in this change: MCP (#20), launch-at-login changes (#19 keeps MacUtilityKit's).

## MacUtilityKit (additive, version 0.2.0)

- `MUKCarbonHotKey`: a global tap shortcut registered with Carbon. It needs no permission and
  consumes the key press. It takes the existing `MUKHotkey`.
- `MUKKeyboardLayout`: maps key codes to characters in the current keyboard layout and back.
- `MUKPasteInjector`: sends ⌘V using the key that types "v" in the current layout (falling back
  to 9). The public API is unchanged.
- `MUKHotkeyRecorder`: a new `allowsModifierOnly: Bool = true` parameter. Existing callers are
  unchanged.
- A first test target.

VoxKey and upkeep must build and pass their tests against the new version unchanged.
