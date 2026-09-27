#!/usr/bin/env bash
set -euo pipefail

script=$(dirname -- "$0")/block-updates.sh
tmp=$(mktemp -d)
trap '/usr/bin/chflags nouchg "$tmp/update" 2>/dev/null || true; rm -rf -- "$tmp"' EXIT
bash "$script" "$tmp/update"
if touch "$tmp/update/download" 2>/dev/null; then
    echo 'FAIL: Spotify can stage an update in the locked directory' >&2
    exit 1
fi
bash "$script" "$tmp/update"
/usr/bin/chflags nouchg "$tmp/update"
printf 'preserve me\n' > "$tmp/update/download"
if bash "$script" "$tmp/update" 2>/dev/null; then
    echo 'FAIL: accepted existing staged update data' >&2
    exit 1
fi
[ "$(cat "$tmp/update/download")" = 'preserve me' ]
ln -s "$tmp/update" "$tmp/link"
if bash "$script" "$tmp/link" 2>/dev/null; then
    echo 'FAIL: accepted a symlink update path' >&2
    exit 1
fi
printf 'preserve file\n' > "$tmp/file"
if bash "$script" "$tmp/file" 2>/dev/null; then
    echo 'FAIL: accepted a regular-file update path' >&2
    exit 1
fi
[ "$(cat "$tmp/file")" = 'preserve file' ]
echo 'PASS: update staging blocked, repeated application safe, existing data and symlink targets preserved'
