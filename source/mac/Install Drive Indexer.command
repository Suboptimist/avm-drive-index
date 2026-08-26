#!/bin/bash
#
# Double-click this file to turn on the Drive Indexer.
#
# It sets up a small background helper (a standard macOS "LaunchAgent")
# that runs the indexer automatically every time a drive is connected or
# ejected, and once right now so the index is up to date immediately.

set -u

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
LEGACY_INDEX_DIR="${LEGACY_INDEX_DIR:-$(dirname "$APP_DIR")}"
INDEX_DIR="${DRIVE_INDEX_DIR:-$HOME/Library/Application Support/AVM Drive Index}"
SOURCE_SCRIPT="$APP_DIR/drive_indexer.sh"
SCRIPT="$INDEX_DIR/drive_indexer.sh"
LABEL="com.avm.drive-indexer"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$INDEX_DIR/Logs"

# Prefer launching the app itself to do the scanning. macOS attributes drive
# access to whatever it can identify: the app can be granted access to external
# drives in System Settings, a bare shell cannot. Falls back to running the
# script directly when the installer is used from the source folder, where
# there is no app bundle to launch.
APP_BINARY=""
CANDIDATE="$APP_DIR/../../MacOS/DriveIndexApp"
if [ -x "$CANDIDATE" ]; then
    APP_BINARY="$(cd "$(dirname "$CANDIDATE")" && pwd)/$(basename "$CANDIDATE")"
fi

echo ""
echo "Setting up the Drive Indexer..."
echo ""
echo "  Private index folder : $INDEX_DIR"
echo "  Watching     : /Volumes (every drive connect / eject)"
echo ""

mkdir -p "$HOME/Library/LaunchAgents" "$INDEX_DIR" "$LOG_DIR"

# Move an index made by earlier versions out of the visible app folder. This
# preserves the catalogue and custom drive organisation on the first upgrade.
if [ "$LEGACY_INDEX_DIR" != "$INDEX_DIR" ]; then
    for item in "Drives" "Drives Overview.txt" ".drive-organization.json"; do
        if [ -e "$LEGACY_INDEX_DIR/$item" ] && [ ! -e "$INDEX_DIR/$item" ]; then
            mv "$LEGACY_INDEX_DIR/$item" "$INDEX_DIR/$item"
        fi
    done
fi

cp "$SOURCE_SCRIPT" "$SCRIPT"
chmod +x "$SCRIPT"

if [ -n "$APP_BINARY" ]; then
    PROGRAM_ARGUMENTS="        <string>$APP_BINARY</string>
        <string>--scan</string>"
    echo "  Scanning as       : AVM Drive Index.app (so macOS can grant it drive access)"
else
    PROGRAM_ARGUMENTS="        <string>/bin/bash</string>
        <string>$SCRIPT</string>"
    echo "  Scanning as       : /bin/bash (no app bundle found next to this installer)"
fi
echo ""

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
$PROGRAM_ARGUMENTS
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>DRIVE_INDEX_DIR</key>
        <string>$INDEX_DIR</string>
    </dict>
    <key>WatchPaths</key>
    <array>
        <string>/Volumes</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/indexer.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/indexer.log</string>
</dict>
</plist>
PLIST

# Reload the agent (quietly ignore "not loaded" on first install).
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || launchctl load "$PLIST" 2>/dev/null

# Run once right now so whatever is plugged in gets indexed immediately.
DRIVE_INDEX_DIR="$INDEX_DIR" /bin/bash "$SCRIPT"

echo "Done! The Drive Indexer is now running."
echo ""
echo "From now on, every external drive you connect will show up in:"
echo "  $INDEX_DIR/Drives"
echo ""
if [ -n "$APP_BINARY" ]; then
    echo "One more step, once: open AVM Drive Index and press Rescan with a drive"
    echo "connected. macOS will ask whether the app may access files on a"
    echo "removable volume — click Allow. Without that, drives are still listed"
    echo "but their folders and files cannot be read."
else
    echo "If macOS asks whether it may access files on a removable volume,"
    echo "click Allow — that's the indexer reading the drive's folder names."
fi
echo ""
echo "You can close this window."
