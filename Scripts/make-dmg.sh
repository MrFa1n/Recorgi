#!/bin/sh
# Builds a Release, ad-hoc-signed Recorgi.app and packages it into a
# double-clickable .dmg under dist/, ready to hand to someone on another
# Mac. Ad-hoc signing (see project.yml's Release config override) needs no
# certificate — unlike the Debug build's "Recorgi Local Dev" identity,
# which only exists on the machine that created it.
#
# This DMG is NOT notarized (that needs a paid Apple Developer Program
# membership, which this project doesn't have). Gatekeeper will mark the
# app as from an "unidentified developer" on first launch — see the
# README's "Installing a downloaded build" section for how to open it
# anyway. That warning is expected, not a sign anything went wrong here.
set -eu

cd "$(dirname "$0")/.."

DERIVED_DATA=".build/release"
APP_NAME="Recorgi"
SCHEME="Recorgi"

xcodegen generate

echo "Building Release..."
xcodebuild -project "${APP_NAME}.xcodeproj" -scheme "$SCHEME" -configuration Release \
    -derivedDataPath "$DERIVED_DATA" build

APP_PATH="$DERIVED_DATA/Build/Products/Release/${APP_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
    echo "error: expected app bundle at $APP_PATH, not found" >&2
    exit 1
fi

echo "Verifying code signature..."
codesign --verify --deep --strict "$APP_PATH"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")

STAGING_DIR=$(mktemp -d)
trap 'rm -rf "$STAGING_DIR"' EXIT

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
cp CHANGELOG.md "$STAGING_DIR/Changelog.md"

mkdir -p dist
DMG_PATH="dist/${APP_NAME}-${VERSION}.dmg"
rm -f "$DMG_PATH"

echo "Creating $DMG_PATH ..."
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"

echo "Done: $DMG_PATH"
