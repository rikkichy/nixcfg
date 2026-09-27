#!/usr/bin/env bash
set -euo pipefail

update=$1
if [[ -L "$update" || ( -e "$update" && ! -d "$update" ) ]]; then
    printf 'Refusing to lock a non-directory Spotify update path: %s\n' "$update" >&2
    exit 1
fi
shopt -s nullglob dotglob
entries=("$update"/*)
if (( ${#entries[@]} != 0 )); then
    printf 'Spotify has staged updates in %s; close Spotify and inspect/move them before activation. Nothing was removed.\n' "$update" >&2
    exit 1
fi
mkdir -p -- "$update"
/usr/bin/chflags uchg "$update"
