#!/bin/bash
# Installs vncdisplay, the watcher, and the launch agent into a user prefix.
# Everything lives under $PREFIX and $HOME; nothing needs root.

set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
LABEL="${LABEL:-io.github.lucheol.vnc-single-display}"
LOGDIR="$HOME/Library/Logs"
AGENT_DIR="$HOME/Library/LaunchAgents"
AGENT="$AGENT_DIR/$LABEL.plist"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v swiftc >/dev/null || {
    echo "swiftc not found. Install the Xcode command line tools: xcode-select --install" >&2
    exit 1
}

echo "==> building vncdisplay"
mkdir -p "$HERE/build"
swiftc -O -o "$HERE/build/vncdisplay" "$HERE/src/vncdisplay.swift"

echo "==> installing into $PREFIX"
mkdir -p "$PREFIX/bin" "$AGENT_DIR" "$LOGDIR"
install -m 755 "$HERE/build/vncdisplay" "$PREFIX/bin/vncdisplay"
install -m 755 "$HERE/bin/vnc-single-display-watch" "$PREFIX/bin/vnc-single-display-watch"

echo "==> writing $AGENT"
sed -e "s|@LABEL@|$LABEL|g" \
    -e "s|@PREFIX@|$PREFIX|g" \
    -e "s|@LOGDIR@|$LOGDIR|g" \
    "$HERE/launchd/vnc-single-display.plist.in" >"$AGENT"
plutil -lint "$AGENT" >/dev/null

echo "==> loading launch agent"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$AGENT"

echo
echo "Installed. The watcher is running and will mirror on connect, restore on disconnect."
echo "  status:    $PREFIX/bin/vncdisplay status"
echo "  activity:  tail -f $LOGDIR/vnc-single-display.log"
echo "  uninstall: ./uninstall.sh"
