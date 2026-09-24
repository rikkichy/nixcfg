#!/usr/bin/env bash
set -euo pipefail

# Run with Discord closed: its in-memory settings can overwrite external edits.
declared=$1
settings=$2
mkdir -p -- "$(dirname -- "$settings")"
input=/dev/null
if [ -e "$settings" ]; then
    input=$settings
fi

tmp=$(mktemp "$settings.tmp.XXXXXX")
trap 'rm -f -- "$tmp"' EXIT
jq -s --slurpfile declared "$declared" '
    (if length == 0 then {} elif length == 1 and (.[0] | type) == "object"
     then .[0] else error("Equicord settings must be a JSON object") end)
    | .plugins = ((.plugins // {}) | map_values(.enabled = false))
    | .plugins *= $declared[0]
' "$input" > "$tmp"
mv -- "$tmp" "$settings"
