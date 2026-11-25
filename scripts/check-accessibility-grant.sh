#!/usr/bin/env bash
# After installing a new build: if macOS's stored Accessibility grant for ClipVault no longer
# matches the installed app's signature, remove it, so the next "Grant…" creates a fresh one.
#
# Why: macOS records the app's signature when the Accessibility entry is first created, and
# switching the entry back on later does not refresh it. A stale entry shows as "on" in System
# Settings while macOS refuses the app, so pasting silently stops working.
#
#   ./scripts/check-accessibility-grant.sh [/Applications/ClipVault.app]
#
# Reading the permission database needs Full Disk Access for the terminal; without it the check
# is skipped. TCC_DB can point at another database (used to test this script).
set -uo pipefail

APP="${1:-/Applications/ClipVault.app}"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")"
TCC_DB="${TCC_DB:-/Library/Application Support/com.apple.TCC/TCC.db}"
TCCUTIL="${TCCUTIL:-/usr/bin/tccutil}"

if ! HEX="$(sqlite3 "$TCC_DB" "SELECT hex(csreq) FROM access WHERE service='kTCCServiceAccessibility' AND client='$BUNDLE_ID';" 2>/dev/null)"; then
    echo "Accessibility check skipped (the permission database is not readable from this terminal)."
    exit 0
fi
if [[ -z "$HEX" ]]; then
    echo "Accessibility: not granted yet. Use Settings → Grant… in the app."
    exit 0
fi

REQ="$(mktemp)"
trap 'rm -f "$REQ"' EXIT
echo "$HEX" | xxd -r -p > "$REQ"
if codesign --verify -R "$REQ" "$APP" >/dev/null 2>&1; then
    echo "Accessibility: the existing grant matches this build."
else
    "$TCCUTIL" reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1
    echo "Accessibility: the stored grant was for an older build and has been removed."
    echo "Open the app's Settings → Grant… and switch it on once; it will survive later rebuilds."
fi
