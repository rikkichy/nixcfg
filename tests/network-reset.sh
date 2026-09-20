#!/usr/bin/env bash
set -euo pipefail
reset=${1:?usage: network-reset.sh /absolute/store/path/bin/network-reset}
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export XDG_CONFIG_HOME="$tmp/config" XDG_STATE_HOME="$tmp/state"
export RESET_CALLS="$tmp/calls"

function pkill { printf 'kill\n' >> "$RESET_CALLS"; return 1; }
function timeout { [[ "$1" = 5s && "$2" = pidwait ]] || return 2; return 1; }
function notify-send { :; }
function nmcli {
  printf 'nmcli %s\n' "$*" >> "$RESET_CALLS"
  if [[ "$*" = '-g GENERAL.CON-UUID device show enp11s0' ]]; then
    printf '11111111-2222-3333-4444-555555555555\n'
  elif [[ "$*" = '--wait 15 device disconnect enp11s0' ]]; then
    return "${RESET_DISCONNECT_STATUS:-0}"
  fi
}
function curl { printf 'curl %s\n' "$*" >> "$RESET_CALLS"; return "${RESET_CURL_STATUS:-0}"; }
export -f pkill timeout notify-send nmcli curl

helium="$XDG_CONFIG_HOME/net.imput.helium/Default/Network Persistent State"
discord="$XDG_CONFIG_HOME/discord/Network Persistent State"
cache_names=(Cache 'Code Cache' GPUCache DawnGraphiteCache DawnWebGPUCache)
preserved_names=(Cookies 'Local Storage' 'Session Storage' IndexedDB WebStorage 'Service Worker' modules)
fixture() {
  rm -rf -- "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"
  mkdir -p "$(dirname "$helium")" "$(dirname "$discord")" "$XDG_CONFIG_HOME/Equicord"
  printf '%s\n' '{"net":{"http_server_properties":{"broken_alternative_services":[{"fixture":true}],"servers":[{"positive":"hint"}],"supports_quic":true},"network_qualities":{"retained":true}},"other":"retained"}' > "$helium"
  cp -- "$helium" "$discord"
  cp -- "$helium" "$tmp/original"
  for name in "${cache_names[@]}" "${preserved_names[@]}"; do
    mkdir -p "$XDG_CONFIG_HOME/discord/$name"
    printf 'keep or cache\n' > "$XDG_CONFIG_HOME/discord/$name/sentinel"
  done
  printf 'keep\n' > "$XDG_CONFIG_HOME/Equicord/sentinel"
  : > "$RESET_CALLS"
}

fixture
"$reset" all
for file in "$helium" "$discord"; do
  jq -e '.net.http_server_properties | has("broken_alternative_services") | not' "$file" >/dev/null
  jq 'del(.net.http_server_properties.broken_alternative_services)' "$tmp/original" > "$tmp/expected"
  cmp "$tmp/expected" "$file"
done
for name in "${cache_names[@]}"; do test ! -e "$XDG_CONFIG_HOME/discord/$name"; done
for name in "${preserved_names[@]}"; do test -s "$XDG_CONFIG_HOME/discord/$name/sentinel"; done
test -s "$XDG_CONFIG_HOME/Equicord/sentinel"
for file in "$XDG_STATE_HOME"/network-reset/backup.*/{net.imput.helium/Default,discord}/'Network Persistent State'; do
  cmp "$tmp/original" "$file"
done

fixture
printf 'invalid JSON\n' > "$discord"
if "$reset" all; then echo 'Corrupt state unexpectedly accepted' >&2; exit 1; fi
cmp "$tmp/original" "$helium"
test -s "$XDG_CONFIG_HOME/discord/Cache/sentinel"
[[ $(cat "$RESET_CALLS") = kill ]]

fixture
rm -rf -- "$XDG_CONFIG_HOME/discord/Cache"
mkdir -p "$tmp/outside"
printf 'untouched\n' > "$tmp/outside/sentinel"
ln -s "$tmp/outside" "$XDG_CONFIG_HOME/discord/Cache"
if "$reset" discord; then echo 'Symlink cache unexpectedly accepted' >&2; exit 1; fi
test -s "$tmp/outside/sentinel"
cmp "$tmp/original" "$discord"

fixture
"$reset" helium
cmp "$tmp/original" "$discord"
test -s "$XDG_CONFIG_HOME/discord/Cache/sentinel"
[[ $(cat "$RESET_CALLS") = kill ]]

fixture
"$reset" system
cmp "$tmp/original" "$helium"
cmp "$tmp/original" "$discord"
[[ $(cat "$RESET_CALLS") != *kill* ]]
test -s "$XDG_CONFIG_HOME/discord/Cache/sentinel"

fixture
if RESET_CURL_STATUS=7 "$reset" all; then echo 'Network failure unexpectedly succeeded' >&2; exit 1; fi
staged=("$XDG_CONFIG_HOME"/discord/.network-reset.*/Cache/sentinel)
test -s "${staged[0]}"

fixture
if RESET_DISCONNECT_STATUS=10 "$reset" reconnect; then echo 'Disconnect failure unexpectedly succeeded' >&2; exit 1; fi
[[ $(cat "$RESET_CALLS") = *'connection up uuid 11111111-2222-3333-4444-555555555555 ifname enp11s0'* ]]
printf 'network-reset: data preservation, scope isolation and failure handling passed\n'
