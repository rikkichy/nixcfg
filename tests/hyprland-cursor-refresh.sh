#!/usr/bin/env bash
set -euo pipefail
renderer=${1:?usage: hyprland-cursor-refresh.sh RENDERER GRIM}
grim=${2:?usage: hyprland-cursor-refresh.sh RENDERER GRIM}
if [[ ${HYPRLAND_CURSOR_TEST:-} != 1 ]]; then
  echo 'Run only in a disposable Hyprland with an empty desktop, private HOME and software cursors; set HYPRLAND_CURSOR_TEST=1.' >&2
  exit 2
fi
: "${HYPRLAND_INSTANCE_SIGNATURE:?Disposable compositor required}"
tmp=$(mktemp -d)
theme="Cursor-Refresh-Test-$$"
dest="$HOME/.local/share/icons/$theme"
previous=${HYPRCURSOR_THEME:-${XCURSOR_THEME:-default}}
size=${XCURSOR_SIZE:-24}
trap 'hyprctl setcursor "$previous" "$size" >/dev/null 2>&1 || true; rm -rf -- "$tmp" "$dest"' EXIT

"$renderer" '#f08080' "$dest" hypr
hyprctl setcursor "$theme" "$size" >/dev/null
hyprctl repl 'hl.dispatch(hl.dsp.cursor.move({ x = 300, y = 250 }))' >/dev/null
sleep 0.1
position=$(hyprctl cursorpos)
"$grim" -c -g '296,246 48x48' "$tmp/before.png"

"$renderer" '#79b8ff' "$dest" hypr
hyprctl setcursor "$theme" "$size" >/dev/null
sleep 0.1
"$grim" -c -g '296,246 48x48' "$tmp/after.png"
test "$(hyprctl cursorpos)" = "$position"
if cmp -s "$tmp/before.png" "$tmp/after.png"; then
  echo 'The stationary cursor retained its old pixels after theme reload' >&2
  exit 1
fi
printf 'cursor refresh: stationary cursor repainted after same-name theme reload\n'
