#!/bin/bash
# Double-click this file to build "Drive Index.app" — a normal Mac app.
# It only needs to be run once (or again after you change the code).
# The finished app is placed in the Drive Index folder, next to "Drives".
set -e
cd "$(dirname "$0")"

APP_DISPLAY_NAME="AVM Drive Index"
EXECUTABLE_NAME="DriveIndexApp"
APP_BUNDLE="$APP_DISPLAY_NAME.app"
DEST_DIR=".."   # the Drive Index folder itself

echo "Building $APP_DISPLAY_NAME..."
echo ""

if ! command -v swift &> /dev/null; then
  echo "Swift isn't installed on this Mac yet."
  echo ""
  echo "Open Terminal and run this command:"
  echo "    xcode-select --install"
  echo ""
  echo "That installs Apple's free Command Line Tools. Once that finishes,"
  echo "double-click this file again."
  echo ""
  read -p "Press Enter to close this window..."
  exit 1
fi

echo "Compiling (this can take a minute the first time)..."
swift build -c release

rm -rf "$DEST_DIR/$APP_BUNDLE"
mkdir -p "$DEST_DIR/$APP_BUNDLE/Contents/MacOS"
mkdir -p "$DEST_DIR/$APP_BUNDLE/Contents/Resources"
mkdir -p "$DEST_DIR/$APP_BUNDLE/Contents/Resources/Drive Indexer Support"

cp ".build/release/$EXECUTABLE_NAME" "$DEST_DIR/$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
cp "AppResources/Info.plist" "$DEST_DIR/$APP_BUNDLE/Contents/Info.plist"
cp "drive_indexer.sh" "Install Drive Indexer.command" \
   "$DEST_DIR/$APP_BUNDLE/Contents/Resources/Drive Indexer Support/"
chmod +x "$DEST_DIR/$APP_BUNDLE/Contents/Resources/Drive Indexer Support/"*.sh \
         "$DEST_DIR/$APP_BUNDLE/Contents/Resources/Drive Indexer Support/"*.command

if [ -d "AppResources/AppIcon.iconset" ]; then
  echo "Building app icon..."
  iconutil -c icns "AppResources/AppIcon.iconset" -o "$DEST_DIR/$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

chmod +x "$DEST_DIR/$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

# Ad-hoc sign so macOS doesn't call it "damaged" — no Apple Developer
# account needed.
codesign --force --deep --sign - "$DEST_DIR/$APP_BUNDLE"

echo ""
echo "Done!"
echo "\"$APP_BUNDLE\" is ready in the Drive Index folder — double-click it to open."
echo ""
open "$DEST_DIR"
read -p "Press Enter to close this window..."
