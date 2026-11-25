# ClipVault

macOS clipboard history (SwiftUI + AppKit, `LSUIElement`). Clips (every pasteboard item and type)
are stored locally under `~/Library/Application Support/ClipVault`; nothing is uploaded. ⇧⌘V (a
Carbon hotkey, configurable) opens a full-width bar at the bottom of the working screen; Return
pastes into the app the user came from, which needs Accessibility. Without it, or with "Paste into
the active app" off, picking a clip only copies it.

## Layout

```
Sources/ClipVault/
  App/        AppDelegate (wiring + hotkey), AppState (clip actions), AppSettings, RetentionPolicy, DemoMode
  Services/   ClipboardMonitor (polling), PasteboardItems (snapshot, markers), ClipboardClassifier, PasteboardWriter
  Storage/    ClipStore protocol, SQLiteClipStore (actor; schema migrations via PRAGMA user_version), PayloadCodec
  UI/Bar/     BarController (show/hide, keys, paste), BarPanel, BarModel (state, unit-tested), BarView, ClipCardView, ScreenLocator
  UI/         StatusBarController (menu), SettingsWindow (MUK shell), SettingsView, ExclusionsView, ClipPreview, AboutView
Tests/ClipVaultTests/   classifier, snapshot, store (incl. 0.1 migration), writer, bar model, settings
```

The UI is built on **MacUtilityKit** (github.com/georgecristea/MacUtilityKit, ≥ 0.2.0), shared
with VoxKey and Upkeep: theme, settings shell, components, launch-at-login, `MUKCarbonHotKey`,
layout-aware `MUKPasteInjector`. Reusable UI goes there, not here. To change both together:
`swift package edit MacUtilityKit --path ../MacUtilityKit` (`swift package unedit MacUtilityKit` to
go back); ship by tagging MacUtilityKit and bumping `Package.resolved` here. Any MacUtilityKit change
must keep VoxKey and Upkeep building unchanged.

## Build, install, verify

```sh
swift build                 # compile
swift test                  # unit tests
./scripts/install.sh        # package, install to /Applications, relaunch — use after every change
```

Always run the app from `/Applications`. Packaging signs with the "Local Code Signing" certificate
when present (VoxKey's `scripts/setup-signing.sh` creates it), so the Accessibility grant survives
rebuilds. To see the bar without a key press: post the distributed notification
`com.georgecristea.ClipVault.toggleBar`. `--demo --snapshot out.png` renders the bar for the README.

## Gotchas learned the hard way

- The bar is a non-activating `NSPanel`: it takes key input while the previous app stays active,
  so ⌘V lands there. Keys are handled in `BarPanel.sendEvent`; there is no text field to focus.
- Activate with `NSApp.activate()` (macOS 14+). The deprecated `activate(ignoringOtherApps:)` is
  ignored on macOS 26. Prompts (rename, new pinboard) hide the bar, activate, then bring it back.
- `MUKPreviewPanel` only places panels beside an anchor; the preview uses a computed anchor to sit
  above the bar.
- `package-app.sh` asks SwiftPM for the binary path (`--show-bin-path`): the universal output folder
  moved between toolchains, and a hard-coded path once shipped a months-old binary.
- **Accessibility "on" but not working:** macOS stores the app's signature when its Accessibility
  entry is first created, and toggling the entry later does not refresh it. After a signing change
  the switch shows on while `AXIsProcessTrusted()` is false. `AccessibilityAccess.request()`
  (Settings → Grant…, first paste) resets ClipVault's own entry before prompting, and
  `install.sh` runs `scripts/check-accessibility-grant.sh`, which removes a stale entry after
  each install (it needs Full Disk Access for the terminal to read TCC.db; otherwise it skips).
- ClipVault tags its own pasteboard writes (`com.georgecristea.ClipVault.marker`) so it never
  captures them.
