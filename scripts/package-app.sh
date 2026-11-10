#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="ClipVault"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
BUILD_ARTIFACT_DIR="$ROOT_DIR/builds/latest"
BUILD_ARTIFACT_ZIP="$BUILD_ARTIFACT_DIR/$APP_NAME.app.zip"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"

if swift build -c release --arch arm64 --arch x86_64; then
    BINARY_PATH="$ROOT_DIR/.build/apple/Products/Release/$APP_NAME"
else
    echo "Universal build failed; falling back to host-architecture release build." >&2
    swift build -c release
    BINARY_PATH="$ROOT_DIR/.build/release/$APP_NAME"
fi

if [[ ! -f "$BINARY_PATH" ]]; then
    echo "Could not find built binary at $BINARY_PATH" >&2
    exit 1
fi

if [[ "$APP_DIR" != "$ROOT_DIR/dist/$APP_NAME.app" ]]; then
    echo "Refusing to package unexpected app path: $APP_DIR" >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BINARY_PATH" "$MACOS_DIR/$APP_NAME"
cp "$ROOT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
chmod +x "$MACOS_DIR/$APP_NAME"

# App icon: prefer a prebuilt .icns; otherwise build it from the SVG if tooling is present.
ICON_SRC="$ROOT_DIR/Packaging/ClipVault.icns"
if [[ ! -f "$ICON_SRC" && -f "$ROOT_DIR/Packaging/AppIcon.svg" ]] \
    && command -v rsvg-convert >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
    ICONSET="$(mktemp -d)/ClipVault.iconset"; mkdir -p "$ICONSET"
    for spec in 16:16x16 32:16x16@2x 32:32x32 64:32x32@2x 128:128x128 256:128x128@2x 256:256x256 512:256x256@2x 512:512x512 1024:512x512@2x; do
        px="${spec%%:*}"; name="${spec##*:}"
        rsvg-convert -w "$px" -h "$px" "$ROOT_DIR/Packaging/AppIcon.svg" -o "$ICONSET/icon_$name.png"
    done
    iconutil -c icns "$ICONSET" -o "$ICON_SRC"
fi
if [[ -f "$ICON_SRC" ]]; then
    cp "$ICON_SRC" "$RESOURCES_DIR/ClipVault.icns"
fi

# Base signature. Honors CODE_SIGN_IDENTITY (set by notarize.sh for a Developer ID build);
# otherwise uses an Apple Development cert if present, falling back to ad-hoc (local use only).
if command -v codesign >/dev/null 2>&1; then
    SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
    if [[ -z "$SIGN_IDENTITY" ]] && command -v security >/dev/null 2>&1; then
        SIGN_IDENTITY="$(
            security find-identity -v -p codesigning |
                sed -n 's/.*"\(Apple Development:.*\)".*/\1/p' |
                head -n 1
        )"
    fi
    SIGN_IDENTITY="${SIGN_IDENTITY:--}"
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR" >/dev/null
fi

mkdir -p "$BUILD_ARTIFACT_DIR"
rm -f "$BUILD_ARTIFACT_ZIP"
(
    cd "$ROOT_DIR/dist"
    zip -qry -X "$BUILD_ARTIFACT_ZIP" "$APP_NAME.app"
)

echo "Packaged $APP_DIR"
echo "Wrote $BUILD_ARTIFACT_ZIP"
