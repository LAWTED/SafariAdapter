#!/bin/zsh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Info.plist")"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
APP_DIR="$PROJECT_DIR/dist/SafariAdapter.app"
RELEASE_DIR="$PROJECT_DIR/release"
ZIP_PATH="$RELEASE_DIR/SafariAdapter-$VERSION.zip"
DMG_PATH="$RELEASE_DIR/SafariAdapter-$VERSION.dmg"
CHECKSUM_PATH="$RELEASE_DIR/SHA256SUMS.txt"
STAGING_DIR="$(mktemp -d /tmp/SafariAdapter-release.XXXXXX)"
NOTARY_KEY_PATH="${NOTARY_KEY_PATH:-}"
NOTARY_KEY_ID="${NOTARY_KEY_ID:-}"
NOTARY_ISSUER="${NOTARY_ISSUER:-}"

cleanup() {
  case "$STAGING_DIR" in
    /tmp/SafariAdapter-release.*) rm -rf "$STAGING_DIR" ;;
  esac
}
trap cleanup EXIT

"$PROJECT_DIR/build.sh"
mkdir -p "$RELEASE_DIR"
rm -f "$ZIP_PATH" "$DMG_PATH" "$CHECKSUM_PATH"

if [[ -n "$NOTARY_KEY_PATH" && -n "$NOTARY_KEY_ID" && -n "$NOTARY_ISSUER" ]]; then
  NOTARY_ZIP="$STAGING_DIR/SafariAdapter-notarization.zip"
  ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$NOTARY_ZIP"
  xcrun notarytool submit "$NOTARY_ZIP" \
    --key "$NOTARY_KEY_PATH" \
    --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER" \
    --wait
  xcrun stapler staple "$APP_DIR"
  xcrun stapler validate "$APP_DIR"
fi

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
ditto "$APP_DIR" "$STAGING_DIR/SafariAdapter.app"
ln -s /Applications "$STAGING_DIR/Applications"
cp "$PROJECT_DIR/INSTALL.md" "$STAGING_DIR/先看安装说明.md"

hdiutil create \
  -volname "SafariAdapter $VERSION" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ "$SIGNING_IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"
fi

if [[ -n "$NOTARY_KEY_PATH" && -n "$NOTARY_KEY_ID" && -n "$NOTARY_ISSUER" ]]; then
  xcrun notarytool submit "$DMG_PATH" \
    --key "$NOTARY_KEY_PATH" \
    --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER" \
    --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
fi

(
  cd "$RELEASE_DIR"
  shasum -a 256 "SafariAdapter-$VERSION.dmg" "SafariAdapter-$VERSION.zip" > "$(basename "$CHECKSUM_PATH")"
)

echo "Packaged:"
echo "  $DMG_PATH"
echo "  $ZIP_PATH"
echo "  $CHECKSUM_PATH"
