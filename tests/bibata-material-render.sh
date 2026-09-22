#!/usr/bin/env bash
set -euo pipefail
renderer=${1:?usage: bibata-material-render.sh /absolute/path/bin/bibata-material-render}
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
dest="$tmp/Cached Cursor"
hypr="$dest/hyprcursors/left_ptr.hlc"
x11="$dest/cursors/left_ptr"
stamp() { stat -c '%i:%y' "$1"; }

"$renderer" '#79b8ff' "$dest"
hypr_before=$(stamp "$hypr")
x11_before=$(stamp "$x11")
"$renderer" '#79b8ff' "$dest"
test "$(stamp "$hypr")" = "$hypr_before"
test "$(stamp "$x11")" = "$x11_before"

# A different accent must actually change the rendered cursor.
x11_hash=$(sha256sum "$x11")
"$renderer" '#f08080' "$dest"
test "$(sha256sum "$x11")" != "$x11_hash"

# Repair a missing individual cursor without regenerating the other format.
x11_before=$(stamp "$x11")
rm "$hypr"
"$renderer" '#f08080' "$dest"
test -s "$hypr"
test "$(stamp "$x11")" = "$x11_before"

# A corrupt cursor must be repaired, not accepted as a complete render.
x11_hash=$(sha256sum "$x11")
hypr_before=$(stamp "$hypr")
printf 'broken\n' > "$x11"
"$renderer" '#f08080' "$dest"
test "$(sha256sum "$x11")" = "$x11_hash"
test "$(stamp "$hypr")" = "$hypr_before"

# Changing renderer identity must invalidate otherwise identical inputs.
cp "$renderer" "$tmp/renderer"
chmod +x "$tmp/renderer"
"$tmp/renderer" '#f08080' "$dest"
test "$(stamp "$hypr")" != "$hypr_before"

# Failed generation must preserve the usable render and its cache.
hypr_before=$(stamp "$hypr")
if "$tmp/renderer" not-a-colour "$dest" 2>/dev/null; then
  echo 'Invalid colour unexpectedly succeeded' >&2
  exit 1
fi
test "$(stamp "$hypr")" = "$hypr_before"
"$tmp/renderer" '#f08080' "$dest"
test "$(stamp "$hypr")" = "$hypr_before"
printf 'cursor cache: reuse, accent/renderer invalidation, missing/corrupt repair and failed generation passed\n'
