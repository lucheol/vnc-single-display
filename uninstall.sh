#!/bin/bash
# Removes the launch agent and binaries. Restores the display layout first, so
# uninstalling can never leave the machine stuck mirrored.

set -uo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
LABEL="${LABEL:-io.github.lucheol.vnc-single-display}"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
STATE_DIR="${VNCSD_STATE_DIR:-$HOME/.local/state/vnc-single-display}"

echo "==> unloading launch agent"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true

if [ -e "$STATE_DIR/owned-by-watcher" ] && [ -x "$PREFIX/bin/vncdisplay" ]; then
    echo "==> restoring display layout"
    "$PREFIX/bin/vncdisplay" unmirror || true
    rm -f "$STATE_DIR/owned-by-watcher"
fi

rm -f "$AGENT" "$PREFIX/bin/vncdisplay" "$PREFIX/bin/vnc-single-display-watch"
rmdir "$STATE_DIR" 2>/dev/null || true

echo "Removed. Logs kept at $HOME/Library/Logs/vnc-single-display*.log"
