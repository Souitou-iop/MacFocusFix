#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${CONFIGURATION:-debug}"
APP_ARCH="${APP_ARCH:-native}"
APP_NAME="MacFocusFix"
BUNDLE_ID="win.ebato.MacFocusFix"
MIN_SYSTEM_VERSION="14.0"
APP_VERSION="${APP_VERSION:-0.0.0-dev}"
APP_BUILD="${APP_BUILD:-1}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_SOURCE="$ROOT_DIR/macOS-Windows-FIX Exports/macOS-Windows-FIX.icon/Assets/icon待定.png"
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
APP_ICON="$APP_RESOURCES/AppIcon.icns"

cd "$ROOT_DIR"
mkdir -p "$DIST_DIR"

if [[ "$CONFIGURATION" == "release" ]]; then
  if [[ "$APP_ARCH" == "native" ]]; then
    APP_ARCH="$(uname -m)"
  fi

  case "$APP_ARCH" in
    arm64|x86_64)
      BUILD_TRIPLE="$APP_ARCH-apple-macosx$MIN_SYSTEM_VERSION"
      ;;
    *)
      echo "Unsupported APP_ARCH: $APP_ARCH" >&2
      exit 2
      ;;
  esac

  BUILD_DIR="$(swift build --configuration release --triple "$BUILD_TRIPLE" --show-bin-path)"
  swift build --configuration release --triple "$BUILD_TRIPLE"
  BUILD_BINARY="$BUILD_DIR/$APP_NAME"
else
  swift build
  BUILD_DIR="$(swift build --show-bin-path)"
  BUILD_BINARY="$BUILD_DIR/$APP_NAME"
fi
RESOURCE_BUNDLE="$BUILD_DIR/MacFocusFix_MacFocusFix.bundle"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$APP_RESOURCES/"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
    <string>zh-Hans</string>
  </array>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

if [[ -f "$ICON_SOURCE" ]]; then
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"
  sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$ICONSET_DIR" -o "$APP_ICON"
fi

sign_item() {
  local item="$1"
  local args=(--force --sign "$SIGN_IDENTITY")

  if [[ "$SIGN_IDENTITY" != "-" ]]; then
    args+=(--options runtime --timestamp)
  fi

  codesign "${args[@]}" "$item" >/dev/null
}

if [[ -d "$APP_RESOURCES/MacFocusFix_MacFocusFix.bundle" ]]; then
  sign_item "$APP_RESOURCES/MacFocusFix_MacFocusFix.bundle"
fi

sign_item "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

printf '%s\n' "$APP_BUNDLE"
