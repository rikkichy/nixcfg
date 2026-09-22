#!/usr/bin/env bash
set -euo pipefail

quickshell=${1:?usage: quickshell-hyprland.sh /absolute/path/to/quickshell}
: "${HYPRLAND_INSTANCE_SIGNATURE:?Run inside a Hyprland session}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/shell.qml" <<'QML'
import QtQuick
import Quickshell
import Quickshell.Hyprland
ShellRoot {
    property var monitors: Hyprland.monitors.values
    Timer {
        interval: 1500
        running: true
        onTriggered: {
            if (Hyprland.monitors.values.some(monitor => monitor.name.length > 0))
                console.log("HYPRLAND_IPC_OK");
            Qt.quit();
        }
    }
}
QML
output=$(timeout 10 "$quickshell" --no-color --path "$tmp" 2>&1) || {
    printf '%s\n' "$output" >&2
    exit 1
}
case "$output" in
    *HYPRLAND_IPC_OK*) printf 'PASS: native Hyprland discovery survives socket callbacks\n' ;;
    *) printf '%s\n' "$output" >&2; exit 1 ;;
esac
