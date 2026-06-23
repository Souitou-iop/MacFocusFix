#!/usr/bin/env bash
set -euo pipefail

APP_NAME="MacFocusFix"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
NOTARY_ZIP="$DIST_DIR/$APP_NAME-notary.zip"

: "${APPLE_ID:?APPLE_ID is required for notarization}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required for notarization}"
: "${APPLE_APP_PASSWORD:?APPLE_APP_PASSWORD is required for notarization}"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Missing app bundle: $APP_BUNDLE" >&2
  exit 1
fi

rm -f "$NOTARY_ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$NOTARY_ZIP"

xcrun notarytool submit "$NOTARY_ZIP" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --wait

xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"
spctl -a -vv -t exec "$APP_BUNDLE"

printf '%s\n' "$APP_BUNDLE"
