#!/bin/bash
# Builds a drag-to-install DMG from the current AVM Drive Index app bundle.
set -e

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$APP_DIR")"
APP_BUNDLE="$ROOT_DIR/AVM Drive Index.app"
STAGING_DIR="$APP_DIR/.dmg-staging"
OUTPUT="$ROOT_DIR/AVM Drive Index Installer.dmg"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "Build the app first by double-clicking Build App.command."
    exit 1
fi

rm -rf "$STAGING_DIR" "$OUTPUT"
mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
cp "$APP_DIR/Installer Read Me.txt" "$STAGING_DIR/Read Me.txt"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create -volname "AVM Drive Index" -srcfolder "$STAGING_DIR" \
    -ov -format UDZO "$OUTPUT"
rm -rf "$STAGING_DIR"

echo "Created: $OUTPUT"
