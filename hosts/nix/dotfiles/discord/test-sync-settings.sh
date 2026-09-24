#!/usr/bin/env bash
set -euo pipefail

sync=$(dirname -- "$(realpath -- "$0")")/sync-settings.sh
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

printf '%s\n' '{"Selected":{"enabled":true,"choice":2,"nested":{"managed":true}}}' > "$tmp/declared.json"
printf '%s\n' '{"cloud":{"token":"private-test-value"},"enabledThemes":["custom.css"],"plugins":{"Selected":{"enabled":false,"choice":1,"nested":{"local":7}},"Other":{"enabled":true,"local":8}}}' > "$tmp/settings.json"
bash "$sync" "$tmp/declared.json" "$tmp/settings.json"
jq -e '
    .cloud.token == "private-test-value" and .enabledThemes == ["custom.css"]
    and .plugins.Selected == {enabled:true,choice:2,nested:{managed:true,local:7}}
    and .plugins.Other == {enabled:false,local:8}
' "$tmp/settings.json" > /dev/null
[ "$(stat -c %a "$tmp/settings.json")" = 600 ]
cp "$tmp/settings.json" "$tmp/expected.json"
bash "$sync" "$tmp/declared.json" "$tmp/settings.json"
cmp "$tmp/expected.json" "$tmp/settings.json"

bash "$sync" "$tmp/declared.json" "$tmp/fresh/settings.json"
jq -e '.plugins.Selected.enabled and .plugins.Selected.choice == 2' "$tmp/fresh/settings.json" > /dev/null

for invalid in '{broken' '[]' 'null'; do
    printf '%s\n' "$invalid" > "$tmp/settings.json"
    cp "$tmp/settings.json" "$tmp/expected.json"
    if bash "$sync" "$tmp/declared.json" "$tmp/settings.json" 2>/dev/null; then
        echo "FAIL: invalid settings were accepted" >&2
        exit 1
    fi
    cmp "$tmp/expected.json" "$tmp/settings.json"
done
printf '%s\n' 'PASS: declarations, private state, disabled plugins, fresh install, idempotence, permissions and invalid-input preservation'
