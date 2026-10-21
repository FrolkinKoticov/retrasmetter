#!/bin/bash
# Builds dist/GameLanguageCompanion.app and dist/GameLanguageCompanion.dmg.
#
#   Scripts/release.sh                 # local test build: ad-hoc signed, unsigned-friendly DMG
#   DEVELOPER_ID="Developer ID Application: Name (TEAMID)" Scripts/release.sh
#                                      # + Developer ID signing, hardened runtime
#   DEVELOPER_ID=... NOTARY_PROFILE=retrasmetter-notary Scripts/release.sh
#                                      # + notarization and stapling
#
# No credentials live in this repo. NOTARY_PROFILE is a keychain profile created once with:
#   xcrun notarytool store-credentials retrasmetter-notary --apple-id you@example.com \
#        --team-id TEAMID --password <app-specific-password>
#
# Optional: UNIVERSAL=1 builds for arm64 + x86_64 (default: this Mac's architecture only).
set -euo pipefail
cd "$(dirname "$0")/.."

EXE="GameLanguageCompanion"      # SwiftPM product
NAME="Retrasmetter"               # app / DMG name
VOLNAME="Retrasmetter"
DIST="dist"
APP="$DIST/$NAME.app"
DMG="$DIST/$NAME.dmg"
STAGE="build/dmg-stage"

echo "▸ 1/5 Building Release…"
# Native architecture by default (Intel x86_64 is deprecated on the newest macOS).
# UNIVERSAL=1 builds arm64 + x86_64.
ARCHS_FLAGS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then ARCHS_FLAGS=(--arch arm64 --arch x86_64); fi
swift build -c release ${ARCHS_FLAGS[@]+"${ARCHS_FLAGS[@]}"}
BIN="$(swift build -c release ${ARCHS_FLAGS[@]+"${ARCHS_FLAGS[@]}"} --show-bin-path)/$EXE"
[ -f "$BIN" ] || { echo "Built binary not found at $BIN"; exit 1; }

echo "▸ 2/5 Assembling ${APP}…"
rm -rf "$APP" "$DMG"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$DIST"
cp "$BIN" "$APP/Contents/MacOS/$EXE"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "▸ 3/5 Signing…"
if [ -n "${DEVELOPER_ID:-}" ]; then
  codesign --force --options runtime --timestamp \
           --entitlements Support/Entitlements.plist \
           --sign "$DEVELOPER_ID" "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
else
  echo "  (no DEVELOPER_ID set → ad-hoc signature, for local testing only)"
  codesign --force --sign - "$APP"
fi

echo "▸ 4/5 Creating ${DMG}…"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
if command -v create-dmg >/dev/null 2>&1; then
  # Pretty window if `brew install create-dmg` is available.
  create-dmg --volname "$VOLNAME" --window-size 540 360 --icon-size 96 \
             --icon "$NAME.app" 140 170 --app-drop-link 400 170 \
             --no-internet-enable "$DMG" "$STAGE"
else
  hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
fi
if [ -n "${DEVELOPER_ID:-}" ]; then
  codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"
fi

echo "▸ 5/5 Notarization…"
if [ -n "${DEVELOPER_ID:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl --assess --type open --context context:primary-signature -v "$DMG" || true
else
  echo "  (skipped — set DEVELOPER_ID and NOTARY_PROFILE to notarize)"
fi

rm -rf "$STAGE"
echo "✓ Done:"
ls -lh "$DMG"
echo "  Local unsigned builds: right-click the app → Open the first time (Gatekeeper)."
