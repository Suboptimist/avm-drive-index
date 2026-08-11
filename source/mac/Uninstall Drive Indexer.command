#!/bin/bash
#
# Double-click this file to turn the Drive Indexer off.
#
# It removes the background helper. The Drive Index folder and everything
# already indexed stays exactly where it is — this just stops new updates.

set -u

LABEL="com.avm.drive-indexer"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
INDEX_DIR="$HOME/Library/Application Support/AVM Drive Index"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f "$PLIST"
rm -rf "$INDEX_DIR/.mounted" "$INDEX_DIR/Logs"

echo ""
echo "The Drive Indexer has been turned off."
echo "Your private drive index and its contents were left untouched."
echo ""
echo "To turn it back on later, double-click \"Install Drive Indexer.command\"."
echo ""
echo "You can close this window."
