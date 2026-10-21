#!/usr/bin/env bash
set +x
set -euo pipefail

repo=/etc/nixos
endpoint=https://cache.kror.net/
local_endpoint=http://127.0.0.1:8080/
cache_name=nixcfg
server_dir=/etc/attic
bootstrap_dir=/var/lib/attic-bootstrap
client_conf=/etc/nix/attic.conf
workdir=

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

report_exit() {
  local status=$1
  [[ -z $workdir ]] || rm -rf -- "$workdir"
  if (( status != 0 )); then
    printf '\nStopped (status %s). Setup may be partially complete; inspect completed steps before retrying. Signing keys were not rotated.\n' "$status" >&2
  fi
}

usage() {
  cat <<'HELP'
Usage: nixcfg-attic-setup {server|client|github|--help}

server  Run as root on nixos-server. Confirm DNS/public TCP 80/443, provision
        a JWT key, enable the module, separately approve activation, create
        the public nixcfg cache, and stage a scoped 90-day publication token.
client  Run as your normal user on nix with the SSH YubiKey. Retrieve the
        independently known public key over verified SSH, compare HTTPS, and
        approve root-owned desktop trust and activation/daemon restart.
github  Run as your normal user with authenticated gh and the SSH YubiKey.
        Compare authenticated server identity with HTTPS, approve repository
        variable/secret upload, then separately approve token cleanup/dispatch.

DNS/port forwarding is manual; CGNAT needs a publicly reachable ingress first.
Existing JWT/signing keys are never rotated. Rerun to resume declined stages or
renew a consumed publication token. Private credentials never enter the checkout.
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

valid_key() { [[ $1 =~ ^nixcfg:[A-Za-z0-9+/]{43}=$ ]]; }
valid_hostname() { [[ ${#1} -le 253 && $1 =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; }

no_symlinks() {
  local path=$1
  [[ $path == /* ]] || fail 'Expected an absolute path.'
  while [[ $path != / ]]; do
    [[ ! -L $path ]] || fail "Refusing symlink path: $path"
    path=$(dirname -- "$path")
  done
}

safe_path() {
  local resolved checkout parent owner mode
  no_symlinks "$1"
  resolved=$(realpath -m -- "$1")
  checkout=$(realpath -m -- "$repo")
  [[ $resolved != "$checkout" && $resolved != "$checkout/"* && $resolved != /nix/store && $resolved != /nix/store/* ]] ||
    fail 'Private/bootstrap configuration must stay outside the checkout and Nix store.'
  parent=$(dirname -- "$resolved")
  while [[ $parent != / ]]; do
    if [[ -e $parent ]]; then
      [[ -d $parent ]] || fail "Non-directory ancestor: $parent"
      owner=$(stat -c %u -- "$parent")
      mode=$(stat -c %a -- "$parent")
      [[ $owner == 0 || $owner == "$EUID" ]] || fail "Unsafe ancestor owner: $parent"
      if (( (8#$mode & 0022) != 0 )); then
        if [[ $owner != 0 || ( $parent != /tmp && $parent != /var/tmp ) ]] ||
          (( (8#$mode & 01000) == 0 )); then
          fail "Writable ancestor: $parent"
        fi
      fi
    fi
    parent=$(dirname -- "$parent")
  done
}

checked_file() {
  safe_path "$1"
  [[ -f $1 && $(stat -c %u -- "$1") == "$2" && $(stat -c %a -- "$1") == "$3" ]] ||
    fail "Refusing nonregular or unsafe owner/permissions: $1"
}

private_directory() {
  safe_path "$1"
  if [[ -e $1 ]]; then
    [[ -d $1 && $(stat -c %u -- "$1") == "$EUID" && $(stat -c %a -- "$1") == 700 ]] ||
      fail "Refusing unsafe private directory: $1"
  else
    mkdir -m 700 -- "$1" || fail "Cannot create private directory: $1"
  fi
}

public_directory() {
  safe_path "$1"
  if [[ -e $1 ]]; then
    [[ -d $1 && $(stat -c %u -- "$1") == "$EUID" && $(stat -c %a -- "$1") == 755 ]] ||
      fail "Refusing unsafe bootstrap directory: $1"
  else
    mkdir -m 755 -- "$1" || fail "Cannot create bootstrap directory: $1"
  fi
}

# noclobber rejects existing files and symlinks; never truncate an identity.
create() ( umask 077; set -o noclobber; cat > "$1" )

new_workdir() {
  if [[ -z $workdir ]]; then
    if (( EUID == 0 )); then
      workdir=$(mktemp -d /run/nixcfg-attic.XXXXXX)
    else
      workdir=$(mktemp -d /tmp/nixcfg-attic.XXXXXX)
    fi
  fi
  private_directory "$workdir"
}

valid_token_file() {
  local token
  [[ -f $1 && ! -L $1 ]] || return 1
  token=$(cat -- "$1")
  [[ $token =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]
}

validate_server_credentials() {
  local value
  checked_file "$server_dir/server.env" "$EUID" 600
  value=$(cat -- "$server_dir/server.env")
  [[ $value =~ ^ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=([A-Za-z0-9+/]+={0,2})$ ]] ||
    fail 'Existing JWT environment file is incompatible; refusing replacement.'
  printf '%s' "${BASH_REMATCH[1]}" | base64 --decode > "$workdir/jwt.pem" || fail 'Invalid base64 JWT key.'
  openssl rsa -in "$workdir/jwt.pem" -check -noout >/dev/null 2>&1 || fail 'Existing JWT key is invalid; restore it, do not regenerate it.'
  rm -f -- "$workdir/jwt.pem"
}

write_server_credentials() {
  private_directory "$server_dir"
  new_workdir
  if [[ -e $server_dir/server.env || -L $server_dir/server.env ]]; then
    validate_server_credentials
    printf 'Preserving the existing JWT key.\n'
    return
  fi
  [[ ! -e /var/lib/atticd/server.db ]] || fail 'An Attic database already exists without its JWT environment file; restore the original key.'
  openssl genrsa -traditional 4096 > "$workdir/jwt.pem" || fail 'JWT key generation failed.'
  { printf 'ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64='; base64 -w0 < "$workdir/jwt.pem"; printf '\n'; } > "$workdir/server.env"
  create "$server_dir/server.env" < "$workdir/server.env" || fail 'JWT file already exists or could not be installed; nothing was replaced.'
  validate_server_credentials
}

enable_server_module() {
  local module source block owner disabled=$'\n    enable = false;\n' enabled=$'\n    enable = true;\n' marker='  services.atticd = {'
  module=$repo/hosts/nixos-server/modules/system/attic.nix
  no_symlinks "$module"
  [[ -f $module ]] || fail 'Expected a regular Attic module.'
  owner=$(stat -c %u -- "$module")
  [[ $owner == "$EUID" || $owner == "$(id -u ri)" ]] || fail 'Attic module must be owned by the operator or root.'
  [[ $(stat -c %a -- "$module") =~ ^[0-7][0145][0145]$ ]] || fail 'Attic module must not be group/other writable.'
  source=$(cat -- "$module")
  [[ $source == *"$marker"* && ${source#*"$marker"} != *"$marker"* ]] || fail 'Expected one services.atticd block; inspect source.'
  block=${source#*"$marker"}
  [[ $block == *$'\n  };'* ]] || fail 'Expected the existing Attic module layout.'
  block=${block%%$'\n  };'*}$'\n'
  if [[ $block == *"$enabled"* && $'\n'${block#*"$enabled"} != *"$enabled"* && $block != *"$disabled"* ]]; then
    printf 'Attic module is already enabled.\n'
    return
  fi
  [[ $block == *"$disabled"* && $'\n'${block#*"$disabled"} != *"$disabled"* && $block != *"$enabled"* &&
    $'\n'${source#*"$disabled"} != *"$disabled"* ]] || fail 'Expected one disabled Attic statement; inspect source.'
  printf '%s\n' "${source/"$disabled"/"$enabled"}" > "$module"
}

verify_cache_info() {
  local key
  jq -e --arg substituter "${endpoint}${cache_name}" '
    type == "object" and .is_public == true and .substituter_endpoint == $substituter and
    (.public_key | type == "string") and
    ((has("store_dir") | not) or .store_dir == "/nix/store")' "$1" >/dev/null 2>&1 ||
    fail 'Cache is private or has incompatible metadata/endpoint; refusing to reconfigure it.'
  key=$(jq -er '.public_key' "$1")
  valid_key "$key" || fail 'Invalid nixcfg signing public key.'
  [[ -z ${2:-} || $key == "$2" ]] || fail 'Cache signing identity differs from the independently known key.'
  printf '%s\n' "$key"
}

https_cache_info() {
  curl --disable --proto '=https' --fail --silent --show-error --connect-timeout 10 --max-time 30 \
    "${endpoint}${cache_name}/attic-cache-info" > "$1" || fail 'Cannot retrieve TLS-verified public cache metadata.'
}

configure_cache() {
  local status key saved
  new_workdir
  public_directory "$bootstrap_dir"
  private_directory "$workdir/attic"
  atticd-atticadm make-token --sub bootstrap --validity '2 hours' \
    --pull "$cache_name" --push "$cache_name" --create-cache "$cache_name" \
    --configure-cache "$cache_name" --configure-cache-retention "$cache_name" > "$workdir/admin-token"
  valid_token_file "$workdir/admin-token" || fail 'Invalid bootstrap token from atticd-atticadm.'
  cat > "$workdir/attic/config.toml" <<EOF
default-server = "kror"
[servers.kror]
endpoint = "$endpoint"
token-file = "$workdir/admin-token"
EOF
  # curl reads authorization from a protected file, not argv or environment.
  { printf 'header = "Authorization: Bearer '; tr -d '\n' < "$workdir/admin-token"; printf '"\n'; } > "$workdir/curl-auth"
  status=$(curl --disable --noproxy '*' --silent --show-error --connect-timeout 10 --max-time 30 --config "$workdir/curl-auth" \
    --header 'Host: cache.kror.net' --output "$workdir/cache.json" --write-out '%{http_code}' \
    "${local_endpoint}_api/v1/cache-config/${cache_name}")
  case "$status" in
    200) verify_cache_info "$workdir/cache.json" >/dev/null ;;
    404)
      [[ ! -e $bootstrap_dir/nixcfg.pub && ! -L $bootstrap_dir/nixcfg.pub ]] ||
        fail 'A saved signing identity exists but its cache is absent; restore the database.'
      XDG_CONFIG_HOME=$workdir attic cache create "kror:$cache_name" --public || fail 'Cache creation failed; existing identity was not reconfigured.'
      XDG_CONFIG_HOME=$workdir attic cache configure "kror:$cache_name" --retention-period '90 days' || fail 'New cache retention setup failed; rerun preserves its signing identity.'
      ;;
    *) fail "Cannot safely establish cache existence (HTTP $status); nothing was recreated." ;;
  esac
  curl --disable --noproxy '*' --fail --silent --show-error --connect-timeout 10 --max-time 30 --header 'Host: cache.kror.net' \
    "${local_endpoint}${cache_name}/attic-cache-info" > "$workdir/local-cache.json" || fail 'Local public cache metadata request failed.'
  key=$(verify_cache_info "$workdir/local-cache.json")
  if [[ -e $bootstrap_dir/nixcfg.pub || -L $bootstrap_dir/nixcfg.pub ]]; then
    checked_file "$bootstrap_dir/nixcfg.pub" "$EUID" 644
    saved=$(cat -- "$bootstrap_dir/nixcfg.pub")
    valid_key "$saved" && [[ $key == "$saved" ]] || fail 'Saved signing identity differs; refusing to overwrite it.'
  fi
  https_cache_info "$workdir/https-cache.json"
  verify_cache_info "$workdir/https-cache.json" "$key" >/dev/null
  if [[ ! -e $bootstrap_dir/nixcfg.pub ]]; then
    printf '%s\n' "$key" | create "$bootstrap_dir/nixcfg.pub" || fail 'Known public key already exists or could not be installed.'
    chmod 644 -- "$bootstrap_dir/nixcfg.pub"
  fi
  rm -f -- "$workdir/admin-token" "$workdir/curl-auth"
  printf 'Public cache verified. Independently known public key: %s\n' "$key"
}

server() {
  local uid gid
  [[ $(uname -s) == Linux && $EUID == 0 ]] || fail 'Run server setup as root on Linux.'
  [[ $(uname -n) == nixos-server ]] || fail 'Server setup must run on nixos-server.'
  uid=$(id -u ri); gid=$(id -g ri)
  printf 'Point the DNS-only A record cache.kror.net at the server public IPv4.\nForward inbound TCP 80/443 if behind NAT; avoid unreachable AAAA records.\nCGNAT requires a reachable public ingress. Keep LAN SSH/console recovery.\n'
  approve 'Are DNS and public inbound TCP 80/443 ready' || return 0
  printf 'Provision/preserve the private JWT key and enable the checkout Attic module.\nActivation accepts ACME terms; it is separately approved.\n'
  approve 'Provision credentials and enable the server module' || return 0
  write_server_credentials
  enable_server_module
  if systemctl is-active --quiet atticd nginx; then
    printf 'Attic and Nginx are already active; validating the existing deployment.\n'
  elif approve 'Activate nixos-server now using nh (as ri)'; then
    runuser -u ri -- nh os switch "path:$repo" --hostname nixos-server --no-update-lock-file
  else
    printf 'Activation pending: nh os switch path:%s --hostname nixos-server --no-update-lock-file\nRerun server setup after activation to finish cache/token provisioning.\n' "$repo"
    return 0
  fi
  systemctl is-active --quiet atticd nginx
  # The root URL need not exist, but a TLS-verified HTTP response proves routing.
  curl --disable --proto '=https' --silent --show-error --connect-timeout 10 --max-time 30 --output /dev/null "$endpoint"
  command -v atticd-atticadm >/dev/null || fail 'Activated system must supply atticd-atticadm.'
  approve 'Create the public-download nixcfg cache if absent and save its signing identity' || return 0
  configure_cache
  if [[ -e $bootstrap_dir/ci-token || -L $bootstrap_dir/ci-token ]]; then
    checked_file "$bootstrap_dir/ci-token" "$uid" 600
    valid_token_file "$bootstrap_dir/ci-token" || fail 'Existing pending publication credential is invalid; inspect it without printing.'
    printf 'Preserving the pending publication token; github mode can upload it.\n'
    return
  fi
  approve 'Stage a scoped pull/push-only GitHub publication token valid for 90 days' || return 0
  atticd-atticadm make-token --sub github-nixcfg --validity '90 days' \
    --pull "$cache_name" --push "$cache_name" > "$workdir/ci-token"
  valid_token_file "$workdir/ci-token" || fail 'Invalid publication token from atticd-atticadm.'
  create "$bootstrap_dir/ci-token" < "$workdir/ci-token" || fail 'Pending publication token already exists or could not be installed.'
  chown "$uid:$gid" -- "$bootstrap_dir/ci-token"
  printf 'Token staged privately. Run github mode on your authenticated GitHub client.\nRenew before 90 days by rerunning server mode after consuming the staged token.\n'
}

ssh_server() {
  local -a terminal=()
  [[ ${2:-} != interactive ]] || terminal=(-t)
  ssh "${terminal[@]}" -o IdentitiesOnly=yes -o StrictHostKeyChecking=ask -o HostKeyAlias=nixos-server.local \
    -o ForwardAgent=no -o ClearAllForwardings=yes -i "$identity" -l ri -- "$ssh_host" "$1"
}

fetch_identity() {
  identity=$HOME/.ssh/nixos-server
  [[ -f $identity && ! -L $identity ]] || fail "Provision the SSH YubiKey credential-handle file at $identity first."
  printf 'Server LAN IP or DNS name [nixos-server.local]: '
  IFS= read -r ssh_host || fail 'Input closed; cancelled.'
  ssh_host=${ssh_host:-nixos-server.local}
  valid_hostname "$ssh_host" || fail 'Enter an IPv4 address or DNS name without a port or URL.'
  printf 'Connect the SSH YubiKey; independently verify the host fingerprint on first connection.\n'
  approve 'Retrieve the root-known public signing key over verified SSH and compare HTTPS' || return 1
  new_workdir
  # These expressions belong to the authenticated remote shell, not this shell.
  # shellcheck disable=SC2016
  ssh_server 'set -eu; p=/var/lib/attic-bootstrap; test ! -L "$p"; test -d "$p"; test "$(stat -c %u "$p")" = 0; test "$(stat -c %a "$p")" = 755; test ! -L "$p/nixcfg.pub"; test -f "$p/nixcfg.pub"; test "$(stat -c %u "$p/nixcfg.pub")" = 0; test "$(stat -c %a "$p/nixcfg.pub")" = 644; cat "$p/nixcfg.pub"' > "$workdir/nixcfg.pub" || fail 'Authenticated server public-key retrieval failed.'
  trusted_key=$(cat -- "$workdir/nixcfg.pub")
  valid_key "$trusted_key" || fail 'Invalid independently known server key.'
  https_cache_info "$workdir/https-cache.json"
  verify_cache_info "$workdir/https-cache.json" "$trusted_key" >/dev/null
}

install_client_config() (
  if (( EUID != 0 )); then
    sudo bash -c 'set +x; set -euo pipefail; repo=$1; client_conf=$2; '"$(declare -f fail no_symlinks safe_path checked_file create install_client_config)"'; install_client_config' \
      bash "$repo" "$client_conf" || fail 'Client trust installation failed.'
    return
  fi
  local staged parent
  safe_path "$client_conf"
  parent=$(dirname -- "$client_conf")
  [[ -d $parent && $(stat -c %u -- "$parent") == 0 && $(stat -c %a -- "$parent") == 755 ]] ||
    fail 'Client configuration parent must be a root-owned 0755 directory.'
  staged=$(mktemp /run/nixcfg-attic-client.XXXXXX)
  trap 'rm -f -- "$staged"' EXIT
  cat > "$staged"
  if [[ -e $client_conf || -L $client_conf ]]; then
    checked_file "$client_conf" 0 644
    cmp --silent -- "$staged" "$client_conf" || fail 'Existing client trust differs; refusing to overwrite it.'
    printf 'Preserving identical existing client trust.\n'
  else
    create "$client_conf" < "$staged" || fail 'Client trust already exists or could not be installed.'
    chmod 644 -- "$client_conf"
  fi
)

client() {
  local snapshot
  [[ $(uname -s) == Linux && $EUID != 0 && $(uname -n) == nix ]] || fail 'Run client setup as your normal user on the Linux host nix.'
  fetch_identity || return 0
  approve 'Install the root-owned public-only /etc/nix/attic.conf trust file' || return 0
  { printf 'extra-substituters = %s%s\n' "$endpoint" "$cache_name"; printf 'extra-trusted-public-keys = %s\n' "$trusted_key"; } | install_client_config
  printf 'Wait for successful GitHub cache publication before activation to avoid heavy uncached native builds.\n'
  if ! approve 'Build desktop nix using this authenticated cache, activate with nh, and restart nix-daemon'; then
    printf 'Activation pending: nix run path:%s#attic-setup -- client\nRerun after cache publication and approve activation. Trust remains inactive until its include is activated and the daemon reloads it.\n' "$repo"
    return 0
  fi
  snapshot=$(sudo nix build --no-link --print-out-paths --no-update-lock-file \
    --option extra-substituters "${endpoint}${cache_name}" --option extra-trusted-public-keys "$trusted_key" \
    "path:$repo#nixosConfigurations.nix.config.system.build.toplevel") || fail 'Desktop snapshot build failed; no activation or daemon restart performed.'
  [[ $snapshot =~ ^/nix/store/[a-z0-9]{32}-[^/[:space:]]+$ && -d $snapshot ]] || fail 'Expected one built NixOS snapshot path.'
  nh os switch "$snapshot" || fail 'Desktop snapshot activation failed; daemon was not restarted.'
  # Do not silently report success when an older generation lacks the include.
  if ! nix_config_has_include; then
    fail 'Activated /etc/nix/nix.conf is missing the Attic include; fix the source include before restarting.'
  fi
  sudo systemctl restart nix-daemon
  printf 'Desktop public-download trust activated; no publication token was installed.\n'
}

nix_config_has_include() {
  local line
  while IFS= read -r line; do
    [[ $line == "!include $client_conf" || $line == "include $client_conf" ]] && return 0
  done < /etc/nix/nix.conf
  return 1
}

github_transfer() {
  local digest
  approve 'Fetch the scoped publication token over SSH and set ATTIC_PUBLIC_KEY/ATTIC_TOKEN on rikkichy/nixcfg' || return 0
  new_workdir
  # Keep remote ownership checks and the token path literal until SSH executes them.
  # shellcheck disable=SC2016
  ssh_server 'set -eu; p=/var/lib/attic-bootstrap; test ! -L "$p"; test -d "$p"; test "$(stat -c %u "$p")" = 0; test "$(stat -c %a "$p")" = 755; test ! -L "$p/ci-token"; test -f "$p/ci-token"; test "$(stat -c %u "$p/ci-token")" = "$(id -u)"; test "$(stat -c %a "$p/ci-token")" = 600; cat "$p/ci-token"' > "$workdir/ci-token" || fail 'Publication-token retrieval failed; remote credential retained.'
  valid_token_file "$workdir/ci-token" || fail 'Invalid staged JWT; no GitHub changes made.'
  gh variable set ATTIC_PUBLIC_KEY --repo rikkichy/nixcfg --body "$trusted_key" || fail 'GitHub public-key update failed; remote staged token retained.'
  gh secret set ATTIC_TOKEN --repo rikkichy/nixcfg < "$workdir/ci-token" || fail 'GitHub secret update failed; remote staged token retained.'
  printf 'GitHub publication key and secret set. The remote staged token remains until approved cleanup.\n'
  if approve 'Remove the successfully uploaded staged token from the server'; then
    digest=$(sha256sum -- "$workdir/ci-token")
    digest=${digest%% *}
    ssh_server "set -eu; p=/var/lib/attic-bootstrap; test ! -L \"\$p\"; test \"\$(stat -c %u \"\$p\")\" = 0; test \"\$(stat -c %a \"\$p\")\" = 755; test ! -L \"\$p/ci-token\"; test -f \"\$p/ci-token\"; test \"\$(stat -c %u \"\$p/ci-token\")\" = \"\$(id -u)\"; test \"\$(stat -c %a \"\$p/ci-token\")\" = 600; printf '%s  %s\\n' '$digest' \"\$p/ci-token\" | sha256sum --check --status; sudo rm -- \"\$p/ci-token\"" interactive || fail 'Remote cleanup failed; inspect the pending server token before renewal.'
  fi
  rm -f -- "$workdir/ci-token"
  if approve 'Dispatch package-cache.yml with target=all now'; then
    gh workflow run package-cache.yml --repo rikkichy/nixcfg -f target=all
  fi
}

github() {
  [[ $(uname -s) == Linux && $EUID != 0 ]] || fail 'Run github setup as your normal user on Linux.'
  gh auth status >/dev/null || fail 'Authenticate gh with access to rikkichy/nixcfg first.'
  fetch_identity || return 0
  github_transfer
}

main() {
  if [[ ${1:-} == --help || ${1:-} == -h ]]; then usage; return; fi
  (( $# == 1 )) || fail 'Expected server, client or github; see --help.'
  umask 077
  trap 'report_exit "$?"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  case "$1" in
    server) server ;;
    client) client ;;
    github) github ;;
    *) fail 'Unknown mode; see --help.' ;;
  esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
