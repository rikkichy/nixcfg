#!/usr/bin/env bash
# Isolated policy checks only: no live provisioning, activation or remote writes.
set +x
set -euo pipefail
umask 077

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
checkout=$(realpath -- "$script_dir/..")
tmp_base=$(realpath -- "${TMPDIR:-/tmp}")
case "$tmp_base/" in
  "$checkout/"*|/nix/store/*) printf 'TMPDIR must be outside the checkout and Nix store.\n' >&2; exit 1 ;;
esac
scratch=$(mktemp -d "$tmp_base/nixcfg-attic-test.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
export TMPDIR="$scratch"
export HOME="$scratch/home"
mkdir -p -- "$HOME" "$scratch/repo"

# Sourcing must not run the operator entry point.
source "$script_dir/attic-setup.sh"
repo=$scratch/repo
server_dir=$scratch/server
bootstrap_dir=$scratch/bootstrap
client_conf=$scratch/client/attic.conf
workdir=$scratch/runtime
mkdir -m 700 -- "$workdir"

check_fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
reject() {
  local status
  # Keep errexit active inside the child; an if/! around it would disable it.
  set +e
  ( set -e; "$@" ) > "$scratch/rejected.log" 2>&1
  status=$?
  set -e
  (( status != 0 )) || check_fail "Unexpected acceptance: $1"
}
same_file() { cmp -s -- "$1" "$2" || check_fail 'Existing identity/content was changed'; }

# Approval defaults to cancellation and cannot create files as a side effect.
reject approve 'Decline provisioning' <<< 'n'
reject approve 'Default cancellation' <<< ''
reject approve 'Closed input' < /dev/null
approve 'Explicit approval' <<< 'y' > /dev/null
[[ ! -e $server_dir && ! -e $bootstrap_dir && ! -e $client_conf ]] || check_fail 'Approval mutated configuration'

# Actual no-clobber writes, including dangling and resolving symlinks.
openssl rand -hex 32 > "$scratch/original"
create "$scratch/secret" < "$scratch/original"
same_file "$scratch/original" "$scratch/secret"
[[ $(stat -c %a -- "$scratch/secret") == 600 ]] || check_fail 'Secret file is not private'
reject create "$scratch/secret" <<< 'replacement'
same_file "$scratch/original" "$scratch/secret"
ln -s -- "$scratch/secret" "$scratch/secret-link"
reject create "$scratch/secret-link" <<< 'replacement'
same_file "$scratch/original" "$scratch/secret"
ln -s -- "$scratch/missing-target" "$scratch/dangling-link"
reject create "$scratch/dangling-link" <<< 'replacement'
[[ ! -e $scratch/missing-target ]] || check_fail 'Followed a dangling symlink'

# Private directory policy must reject unsafe existing paths without repairing them.
private_directory "$scratch/private"
[[ $(stat -c %a -- "$scratch/private") == 700 ]] || check_fail 'Private directory is not private'
private_directory "$scratch/private"
mkdir -m 755 -- "$scratch/unsafe"
reject private_directory "$scratch/unsafe"
[[ $(stat -c %a -- "$scratch/unsafe") == 755 ]] || check_fail 'Unsafe existing permissions were silently changed'
ln -s -- "$scratch/private" "$scratch/private-link"
reject private_directory "$scratch/private-link"
reject private_directory "$scratch/repo/secret"
reject private_directory "$scratch/repo/../repo/secret"
[[ ! -e $scratch/repo/secret ]] || check_fail 'Private directory created inside checkout'
ln -s -- "$scratch/repo" "$scratch/repo-alias"
reject private_directory "$scratch/repo-alias/secret"
reject private_directory /nix/store/nixcfg-attic-test-must-not-exist
printf 'not a directory\n' > "$scratch/regular-file"
reject private_directory "$scratch/regular-file"

# Signing trust accepts only the expected cache name and one 32-byte key.
key="nixcfg:$(openssl rand -base64 32)"
if [[ $key == nixcfg:A* ]]; then
  other_key="nixcfg:B${key#nixcfg:?}"
else
  other_key="nixcfg:A${key#nixcfg:?}"
fi
valid_key "$key" || check_fail 'Rejected a valid signing key'
reject valid_key ''
reject valid_key 'nixcfg:not-base64'
reject valid_key "foreign:${key#nixcfg:}"
reject valid_key "$key extra"
reject valid_key "$key"$'\n'"$other_key"

# Module cutover changes the one disabled statement, then becomes a safe rerun.
module=$repo/hosts/nixos-server/modules/system/attic.nix
mkdir -p -- "$(dirname -- "$module")"
printf '{\n  services.atticd = {\n    enable = false;\n  };\n}\n' > "$module"
enable_server_module
[[ $(nix eval --file "$module" --apply 'c: c.services.atticd.enable') == true ]] ||
  check_fail 'Module activation did not enable the Attic service'
cp -- "$module" "$scratch/enabled.nix"
enable_server_module
same_file "$module" "$scratch/enabled.nix"
printf '{\n  services.atticd = {\n    enable = false;\n    enable = false;\n  };\n}\n' > "$module"
cp -- "$module" "$scratch/module-before"
reject enable_server_module
same_file "$module" "$scratch/module-before"
printf '{\n  services.atticd = {\n    enable = true;\n    enable = false;\n  };\n}\n' > "$module"
cp -- "$module" "$scratch/module-before"
reject enable_server_module
same_file "$module" "$scratch/module-before"
rm -- "$module"
cp -- "$scratch/enabled.nix" "$scratch/symlink-target-before"
ln -s -- "$scratch/enabled.nix" "$module"
reject enable_server_module
same_file "$scratch/enabled.nix" "$scratch/symlink-target-before"
[[ -L $module ]] || check_fail 'Replaced a symlinked module'

# Real JSON trust-boundary inputs: HTTPS may confirm SSH trust, not replace it.
jq -n --arg key "$key" --arg url "${endpoint}${cache_name}" \
  '{is_public: true, public_key: $key, substituter_endpoint: $url}' > "$scratch/cache-info.json"
[[ $(verify_cache_info "$scratch/cache-info.json" "$key") == "$key" ]] ||
  check_fail 'Rejected a matching public cache identity'
reject verify_cache_info "$scratch/cache-info.json" "$other_key"
jq '.is_public = false' "$scratch/cache-info.json" > "$scratch/private-cache.json"
reject verify_cache_info "$scratch/private-cache.json" "$key"
jq '.substituter_endpoint = "https://foreign.example/nixcfg"' "$scratch/cache-info.json" > "$scratch/foreign-cache.json"
reject verify_cache_info "$scratch/foreign-cache.json" "$key"
jq '.public_key = "nixcfg:invalid"' "$scratch/cache-info.json" > "$scratch/invalid-key.json"
reject verify_cache_info "$scratch/invalid-key.json"
printf 'not JSON\n' > "$scratch/bad-json"
reject verify_cache_info "$scratch/bad-json"

# Rejections may not follow symlink ancestors, even outside the checkout.
mkdir -m 700 -- "$scratch/real-parent"
ln -s -- "$scratch/real-parent" "$scratch/linked-parent"
reject safe_path "$scratch/linked-parent/new-secret"
[[ ! -e $scratch/real-parent/new-secret ]] || check_fail 'Followed a symlink ancestor'
checked_file "$scratch/secret" "$EUID" 600
reject checked_file "$scratch/secret-link" "$EUID" 600
reject checked_file "$scratch/private" "$EUID" 700
reject checked_file "$scratch/secret" "$EUID" 644
wrong_uid=$(( EUID + 1 ))
reject checked_file "$scratch/secret" "$wrong_uid" 600

# An actual disposable signed JWT; no production signing key or token is read.
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
  -out "$scratch/jwt-key.pem" > /dev/null 2>&1
header=$(printf '{"alg":"RS256","typ":"JWT"}' | openssl base64 -A | tr '/+' '_-' | tr -d '=')
payload=$(printf '{"sub":"disposable-check"}' | openssl base64 -A | tr '/+' '_-' | tr -d '=')
printf '%s.%s' "$header" "$payload" > "$scratch/jwt-message"
openssl dgst -sha256 -sign "$scratch/jwt-key.pem" "$scratch/jwt-message" |
  openssl base64 -A | tr '/+' '_-' | tr -d '=' > "$scratch/jwt-signature"
{ cat "$scratch/jwt-message"; printf '.'; cat "$scratch/jwt-signature"; printf '\n'; } > "$scratch/token"
valid_token_file "$scratch/token" || check_fail 'Rejected a signed JWT'
printf 'not-a-jwt\n' > "$scratch/invalid-token"
reject valid_token_file "$scratch/invalid-token"
cp -- "$scratch/token" "$scratch/token-with-extra-line"
printf 'extra\n' >> "$scratch/token-with-extra-line"
reject valid_token_file "$scratch/token-with-extra-line"

# Reusing a real server RSA identity must not rotate it or repair bad input.
private_directory "$server_dir"
{
  printf 'ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64='
  base64 -w0 -- "$scratch/jwt-key.pem"
  printf '\n'
} | create "$server_dir/server.env"
cp -- "$server_dir/server.env" "$scratch/server-env-before"
write_server_credentials > "$scratch/reused-credentials.log"
same_file "$server_dir/server.env" "$scratch/server-env-before"
write_server_credentials > "$scratch/reused-credentials.log"
same_file "$server_dir/server.env" "$scratch/server-env-before"
{
  printf 'ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64='
  printf 'not a PEM key' | base64 -w0
  printf '\n'
} > "$server_dir/server.env"
cp -- "$server_dir/server.env" "$scratch/invalid-server-env-before"
reject write_server_credentials
same_file "$server_dir/server.env" "$scratch/invalid-server-env-before"
rm -- "$server_dir/server.env"
cp -- "$scratch/server-env-before" "$scratch/server-env-target-before"
ln -s -- "$scratch/server-env-before" "$server_dir/server.env"
reject write_server_credentials
same_file "$scratch/server-env-before" "$scratch/server-env-target-before"

# Substitute only the unavailable remote transport and a failed GitHub API.
# The transport reads a real disposable staged token, never a canned reply.
# Requested reads/removals operate on the scratch token, not the real server.
mkdir -m 755 -- "$bootstrap_dir"
remote_token=$bootstrap_dir/ci-token
cp -- "$scratch/token" "$remote_token"
trusted_key=$key
ssh_host=disposable.invalid
identity=$scratch/no-ssh-identity
ssh_server() {
  printf '%s\n' operation >> "$scratch/ssh-operations"
  case "$1" in
    *'rm -- '*) rm -- "$remote_token" ;;
    *'cat '*) cat -- "$remote_token" ;;
    *) check_fail 'Unsupported remote operation in isolated transfer' ;;
  esac
}
gh() { : > "$scratch/gh-called"; return 69; }
# No test may fall through to a real SSH connection.
ssh() { check_fail 'Attempted an unisolated SSH connection'; }

github_transfer <<< 'n' > "$scratch/declined-transfer.log" 2>&1
same_file "$remote_token" "$scratch/token"
[[ ! -e $scratch/ssh-operations && ! -e $scratch/gh-called ]] ||
  check_fail 'Declining transfer contacted a remote boundary'
[[ ! -e $workdir/ci-token ]] || check_fail 'Declining transfer staged a token'

reject github_transfer <<< $'y\ny\nn'
same_file "$remote_token" "$scratch/token"
[[ -e $scratch/gh-called ]] || check_fail 'Transfer failed before reaching the GitHub boundary'

# A successful public-key update must not consume the token if secret upload fails.
gh() {
  case "$1" in
    variable) return 0 ;;
    secret) : > "$scratch/secret-update-attempted"; return 69 ;;
    *) check_fail 'Unsupported GitHub operation in isolated transfer' ;;
  esac
}
reject github_transfer <<< $'y\ny\nn'
same_file "$remote_token" "$scratch/token"
[[ -e $scratch/secret-update-attempted ]] || check_fail 'Transfer did not reach secret upload'

printf 'PASS: isolated Attic provisioning and trust policy checks\n'
