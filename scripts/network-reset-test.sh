#!/usr/bin/env bash
set -euo pipefail

# Exercise the rendered command without touching live processes or networking.
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export XDG_CONFIG_HOME="$tmp/config" XDG_STATE_HOME="$tmp/state"
export RESET_TEST_LOG="$tmp/processes"
nix eval --raw 'path:.#nixosConfigurations.nix.config.home-manager.users.ri.home.packages' \
  --apply 'packages: (builtins.head (builtins.filter (p: (p.name or "") == "network-reset") packages)).text' > "$tmp/reset"

pkill() {
  [[ "$1" == -KILL && "$2" == -u && "$3" == "$UID" && "$4" == -f ]] || return 90
  local pattern="$5" binary
  for binary in brave chrome_crashpad_handler; do
    [[ "/nix/store/test-brave-origin-1.96.59/opt/brave.com/brave-origin/$binary --test" =~ $pattern ]] || return 90
    [[ ! "/nix/store/test-brave-1.96.59/opt/brave.com/brave/$binary --test" =~ $pattern ]] || return 90
    [[ ! "/nix/store/test-helium/opt/helium/$binary --test" =~ $pattern ]] || return 90
  done
  printf '%s\n' "$pattern" >> "$RESET_TEST_LOG"
  return 1
}
pidwait() { return 1; }
timeout() { shift; "$@"; }
nmcli() { return 90; }
curl() { return 90; }
notify-send() { return 0; }
export -f pkill pidwait timeout nmcli curl notify-send

profile="$XDG_CONFIG_HOME/BraveSoftware/Brave-Origin/Default"
other="$XDG_CONFIG_HOME/BraveSoftware/Brave-Browser/Default"
mkdir -p "$profile" "$other"
printf '%s\n' '{"net":{"http_server_properties":{"broken_alternative_services":[{"host":"example.test"}],"servers":[{"server":"https://example.test"}]}},"keep":true}' > "$tmp/original"
cp "$tmp/original" "$profile/Network Persistent State"
cp "$tmp/original" "$other/Network Persistent State"
printf 'session-data\n' > "$profile/Cookies"
bash "$tmp/reset" brave-origin
jq -e '.keep and (.net.http_server_properties.servers == [{"server":"https://example.test"}]) and (.net.http_server_properties | has("broken_alternative_services") | not)' "$profile/Network Persistent State" > /dev/null
cmp "$tmp/original" "$other/Network Persistent State"
[[ $(cat "$profile/Cookies") == session-data ]]
backups=("$XDG_STATE_HOME"/network-reset/backup.*/BraveSoftware/Brave-Origin/Default/"Network Persistent State")
[[ ${#backups[@]} == 1 ]]
cmp "$tmp/original" "${backups[0]}"
[[ -s "$RESET_TEST_LOG" ]]
printf 'PASS: Brave Origin recovery preserves other browsers, profile data and backups.\n'
