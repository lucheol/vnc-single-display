#!/bin/bash
#
# vnc-single-display - give screen-sharing clients a single display
# Copyright (C) 2026 Lucio Oliveira
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see <https://www.gnu.org/licenses/>.
#
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
# bootout returns before the job is actually gone, and bootstrapping a label
# that is still tearing down fails with "Input/output error". Wait it out.
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
for _ in $(seq 1 50); do
    launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || break
    sleep 0.2
done
launchctl bootstrap "gui/$(id -u)" "$AGENT"

echo
echo "Installed. The watcher is running and will mirror on connect, restore on disconnect."
echo "  status:    $PREFIX/bin/vncdisplay status"
echo "  activity:  tail -f $LOGDIR/vnc-single-display.log"
echo "  uninstall: ./uninstall.sh"
