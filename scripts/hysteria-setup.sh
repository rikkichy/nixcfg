#!/usr/bin/env bash
# Also sourced by the non-destructive safety regression script.
set +x
set -euo pipefail

repo=/etc/nixos
server_dir=/etc/hysteria
bootstrap_dir=/var/lib/hysteria-bootstrap
client_dir=$HOME/.config/hysteria
workdir=

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

report_exit() {
  local status=$1
  [[ -z $workdir ]] || rm -rf -- "$workdir"
  if (( status != 0 )); then
    printf '\nStopped (status %s). Existing credentials were retained; inspect before retrying.\n' "$status" >&2
  fi
}

usage() {
  cat <<'HELP'
Usage: nixcfg-hysteria-setup {server|client|connect|--help}

server   Run as root on nixos-server. Detect public IPv4, confirm provisioning,
         generate credentials outside the checkout, and enable its module.
         Rebuild/activation requires separate approval. Never overwrites keys.
client   Run as your normal user with the SSH YubiKey connected. Import private
         client credentials over verified SSH; no system activation required.
connect  Run the configured Hysteria client in the foreground.

Router UDP 443 forwarding remains manual. Existing credentials are not rotated.
HELP
}

approve() {
  local answer
  while :; do
    printf '%s [y/N]: ' "$1"
    IFS= read -r answer || fail 'Input closed; cancelled.'
    case "$answer" in
      y|Y|yes|YES) return 0 ;;
      ''|n|N|no|NO) return 1 ;;
      *) printf 'Enter y or n.\n' ;;
    esac
  done
}

valid_hostname() {
  [[ ${#1} -le 253 && $1 =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]
}

valid_ipv4() {
  local part
  local -a parts
  [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  IFS=. read -r -a parts <<<"$1"
  for part in "${parts[@]}"; do
    [[ ${#part} -le 3 && ( $part == 0 || $part != 0* ) ]] || return 1
    (( 10#$part <= 255 )) || return 1
  done
}

public_endpoint() {
  local detected='' answer
  printf 'Detecting public IPv4 via https://ifconfig.me/ip (10-second timeout).\n'
  if detected=$(curl -4 --fail --silent --show-error --max-time 10 https://ifconfig.me/ip 2>/dev/null) && valid_ipv4 "$detected"; then
    printf 'Check this address: VPN/proxy egress may differ from the inbound address.\n'
  else
    detected=
    printf 'Automatic detection failed; enter the public IPv4 address or DNS name manually.\n'
  fi
  printf 'Server public IPv4 address or DNS name%s: ' "${detected:+ [$detected]}"
  IFS= read -r answer || fail 'Input closed; cancelled.'
  endpoint=${answer:-$detected}
  valid_hostname "$endpoint" || fail 'Enter an IPv4 address or DNS name, without a port or URL.'
}

require_absent() {
  local path
  for path in "$@"; do
    [[ ! -e $path && ! -L $path ]] || fail "Refusing to overwrite $path; existing credentials are not rotated."
  done
}

private_directory() {
  local path resolved checkout
  path=$1
  [[ ! -L $path ]] || fail "Refusing symlink directory: $path"
  resolved=$(realpath -m -- "$path")
  checkout=$(realpath -m -- "$repo")
  [[ $resolved != "$checkout" && $resolved != "$checkout/"* ]] || fail 'Private configuration must stay outside the checkout.'
  mkdir -p -- "$path"
  chmod 700 -- "$path"
}

# noclobber also rejects symlinks; umask protects files even when sourced by tests.
create() ( umask 077; set -o noclobber; cat > "$1" )

# Read passwords from a private file, never argv or a printed shell expansion.
render_config() {
  jq -nr --rawfile template "$1" --slurpfile data "$2" --arg cert "${3:-}" '
    $data[0] as $d |
    {"REPLACE_WITH_AUTH_PASSWORD": $d.auth,
     "REPLACE_WITH_OBFS_PASSWORD": $d.obfs,
     "PUBLIC_IP_OR_DNS:443": ($d.server + ":443"),
     "/REPLACE_WITH_ABSOLUTE_PATH_TO/server.crt": $cert} as $values |
    if ($template | contains("REPLACE_WITH_AUTH_PASSWORD") and contains("REPLACE_WITH_OBFS_PASSWORD"))
    then reduce ($values | to_entries[]) as $v ($template; split($v.key) | join($v.value | tojson))
    else error("Missing configuration template placeholders") end
  '
}

server() {
  local module source disabled uid gid
  [[ $(uname -s) == Linux && $EUID == 0 ]] || fail 'Run server setup as root on nixos-server.'
  [[ $(uname -n) == nixos-server ]] || fail 'Server setup must run on the host named nixos-server.'
  uid=$(id -u ri)
  gid=$(id -g ri)
  module=$repo/hosts/nixos-server/modules/system/hysteria.nix
  [[ ! -L $module ]] || fail 'Refusing to edit a symlinked Hysteria module.'
  source=$(cat -- "$module")
  disabled='    enable = false;'
  [[ $source == *"$disabled"* && ${source#*"$disabled"} != *"$disabled"* ]] || fail 'Expected the disabled Hysteria module; inspect existing setup.'
  require_absent "$server_dir/server.yaml" "$server_dir/server.crt" "$server_dir/server.key" "$bootstrap_dir/client.json"
  public_endpoint
  printf 'Generate passwords and a one-year certificate; enable the checkout module. Private credentials stay outside the repo.\n'
  approve 'Provision Hysteria (activation is a separate question)' || return 0
  private_directory "$server_dir"
  [[ $(stat -c %u -- "$server_dir") == 0 ]] || fail 'Server credential directory must be root-owned.'
  [[ ! -L $bootstrap_dir ]] || fail 'Refusing symlink bootstrap directory.'
  mkdir -p -- "$bootstrap_dir"
  [[ $(stat -c %u -- "$bootstrap_dir") == 0 ]] || fail 'Bootstrap directory must be root-owned.'
  chmod 755 -- "$bootstrap_dir"
  workdir=$(mktemp -d /tmp/nixcfg-hysteria.XXXXXX)
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 365 \
    -subj /CN=nixos-server -addext subjectAltName=DNS:nixos-server \
    -keyout "$workdir/key" -out "$workdir/cert" >/dev/null
  { openssl rand -hex 32; openssl rand -hex 32; } |
    jq -Rn --arg server "$endpoint" --rawfile certificate "$workdir/cert" \
      '{server: $server, auth: input, obfs: input, certificate: $certificate}' > "$workdir/bootstrap.json"
  render_config "$server_template" "$workdir/bootstrap.json" > "$workdir/server.yaml"
  create "$server_dir/server.key" < "$workdir/key"
  create "$server_dir/server.crt" < "$workdir/cert"
  create "$server_dir/server.yaml" < "$workdir/server.yaml"
  create "$bootstrap_dir/client.json" < "$workdir/bootstrap.json"
  chown "$uid:$gid" -- "$bootstrap_dir/client.json"
  printf '%s\n' "${source/"$disabled"/'    enable = true;'}" > "$module"
  printf 'Provisioned. Secrets were not printed. Certificate expires in 365 days.\n'
  printf 'Forward router UDP 443 to this server if needed; do not forward TCP 22.\n'
  if approve 'Rebuild and activate nixos-server now'; then
    nixos-rebuild switch --flake "path:$repo#nixos-server"
    systemctl is-active --quiet hysteria
    printf 'Hysteria is active; remote-network connectivity is not yet verified.\n'
  else
    printf 'Activation pending: sudo nixos-rebuild switch --flake path:%s#nixos-server\n' "$repo"
  fi
}

client() {
  local identity host
  (( EUID != 0 )) || fail 'Run client setup as your normal user, not root.'
  require_absent "$client_dir/client.yaml" "$client_dir/server.crt"
  identity=$HOME/.ssh/nixos-server
  [[ -f $identity ]] || fail "Provision the existing YubiKey credential-handle file at $identity first."
  printf 'Server LAN IP or DNS name [nixos-server.local]: '
  IFS= read -r host || fail 'Input closed; cancelled.'
  host=${host:-nixos-server.local}
  valid_hostname "$host" || fail 'Enter an IPv4 address or DNS name, without a port or URL.'
  printf 'Connect the SSH YubiKey. Verify the SSH host fingerprint on first connection.\n'
  approve 'Fetch private client credentials over SSH and configure this client' || return 0
  workdir=$(mktemp -d /tmp/nixcfg-hysteria.XXXXXX)
  ssh -o IdentitiesOnly=yes -o StrictHostKeyChecking=ask -o HostKeyAlias=nixos-server.local -o ForwardAgent=no -o ClearAllForwardings=yes \
    -i "$identity" -l ri -- "$host" 'cat /var/lib/hysteria-bootstrap/client.json' > "$workdir/bootstrap.json"
  jq -e 'type == "object" and (.server | type == "string") and
    (.certificate | type == "string") and
    (.auth | type == "string" and test("^[0-9a-f]{64}$")) and
    (.obfs | type == "string" and test("^[0-9a-f]{64}$"))' "$workdir/bootstrap.json" >/dev/null 2>&1 || fail 'Invalid bootstrap data.'
  endpoint=$(jq -r '.server' "$workdir/bootstrap.json")
  valid_hostname "$endpoint" || fail 'Invalid bootstrap server address.'
  jq -r '.certificate' "$workdir/bootstrap.json" > "$workdir/cert"
  openssl x509 -in "$workdir/cert" -noout -checkend 0 >/dev/null
  render_config "$client_template" "$workdir/bootstrap.json" "$client_dir/server.crt" > "$workdir/client.yaml"
  private_directory "$client_dir"
  chmod 700 -- "$HOME/.ssh"
  chmod 600 -- "$identity"
  create "$client_dir/server.crt" < "$workdir/cert"
  create "$client_dir/client.yaml" < "$workdir/client.yaml"
  printf 'Client configured; no system activation needed. From a phone hotspot, run:\n'
  printf '  nix run path:%s#hysteria-setup -- connect\n' "$repo"
  printf 'Then in another terminal (touch the YubiKey when prompted):\n'
  printf '  ssh -o IdentitiesOnly=yes -o HostKeyAlias=nixos-server.local -i ~/.ssh/nixos-server -p 2222 ri@127.0.0.1\n'
  printf 'With shared Home Manager configuration activated: ssh nixos-server-remote\n'
}

main() {
  if [[ ${1:-} == --help || ${1:-} == -h ]]; then usage; return; fi
  (( $# == 1 )) || fail 'Expected server, client or connect; see --help.'
  umask 077
  trap 'report_exit "$?"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  server_template=${NIXCFG_HYSTERIA_SERVER_TEMPLATE:-$repo/hosts/nixos-server/dotfiles/hysteria/server.example.yaml}
  client_template=${NIXCFG_HYSTERIA_CLIENT_TEMPLATE:-$repo/common/dotfiles/hysteria/client.example.yaml}
  case "$1" in
    server) server ;;
    client) client ;;
    connect)
      (( EUID != 0 )) || fail 'Run the Hysteria client as your normal user.'
      exec hysteria client --config "$client_dir/client.yaml"
      ;;
    *) fail 'Unknown mode; see --help.' ;;
  esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
