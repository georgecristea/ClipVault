# ClipVault

macOS menu bar clipboard history (SwiftUI + AppKit, `LSUIElement`). Text, images, and file
references are stored locally under `~/Library/Application Support/ClipVault`; nothing is uploaded.
The app needs no permissions: selecting an item copies it, the user pastes.

## Layout

```
Sources/ClipVault/
  App/        AppDelegate, AppState (central ObservableObject), AppSettings
  Services/   ClipboardMonitor (pasteboard polling), ClipboardClassifier
  Storage/    ClipStore protocol, SQLiteClipStore
  UI/         StatusBarController (NSStatusItem + popover), MainPopoverView, HistoryView, SettingsView, …
Tests/ClipVaultTests/   classifier + SQLite store tests
```

The UI is built on **MacUtilityKit** (github.com/georgecristea/MacUtilityKit), shared with VoxKey
and Upkeep: theme, popover shell, components, launch-at-login. Reusable UI goes there, not here.
To change both together: `swift package edit MacUtilityKit --path ../MacUtilityKit`
(`swift package unedit MacUtilityKit` to go back); ship by tagging MacUtilityKit and bumping
`Package.resolved` here.

## Build, install, verify

```sh
swift build                 # compile
swift test                  # unit tests
./scripts/install.sh        # package, install to /Applications, relaunch — use after every change
```

Always run the app from `/Applications`. After a UI change, open the popover from the menu bar and
confirm the gear/pause/quit header buttons respond and Settings/About navigate in place.

## Gotchas learned the hard way

- Popover uses `.applicationDefined` with an outside-click monitor; `.transient` dismissed on
  in-popover navigation.
- Activate with `NSApp.activate()` (macOS 14+). The deprecated `activate(ignoringOtherApps:)` is
  ignored on macOS 26, leaving the popover inactive and its buttons dead.
- The search field auto-focuses as first responder and eats the first header click; it is cleared
  on show.
