#!/bin/bash
# Builds a proper .app bundle (needed so macOS can attach the Screen Recording
# permission to a stable app identity instead of to Terminal).
#
# Usage:   Scripts/build-app.sh            # ad-hoc signed
#          SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" Scripts/build-app.sh
#
# Tip: with ad-hoc signing macOS may forget the Screen Recording grant after every
# rebuild. A stable signing identity (a free Apple Development certificate is enough)
# keeps the permission.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/Retrasmetter.app"

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/GameLanguageCompanion" "$APP/Contents/MacOS/GameLanguageCompanion"
cp "Support/Info.plist" "$APP/Contents/Info.plist"
cp "Support/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign "${SIGN_IDENTITY:--}" "$APP"

echo "Built $APP"
echo "Run with:  open \"$APP\""
