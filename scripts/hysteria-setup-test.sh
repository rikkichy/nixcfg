#!/usr/bin/env bash
# No root, production credentials, SSH connection, activation or token access.
# Requires the packaged setup's GNU coreutils and jq.
set -euo pipefail
# shellcheck source=scripts/hysteria-setup.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/hysteria-setup.sh"

testdir=$(mktemp -d)
trap 'rm -rf -- "$testdir"' EXIT
repo=$testdir/checkout
mkdir "$repo"

curl() { printf '203.0.113.10\n'; }
public_endpoint <<<'' > "$testdir/prompt"
[[ $endpoint == 203.0.113.10 ]] || fail 'Enter did not accept detected IPv4.'
public_endpoint <<<'server.example.com' > "$testdir/prompt"
[[ $endpoint == server.example.com ]] || fail 'Manual override did not win.'
curl() { return 28; }
public_endpoint <<<'198.51.100.20' > "$testdir/prompt"
[[ $endpoint == 198.51.100.20 ]] || fail 'Lookup failure prevented manual entry.'
curl() { printf '<html>error</html>\n'; }
if (public_endpoint <<<'') > "$testdir/prompt" 2>&1; then fail 'Invalid response became a default.'; fi
curl() { printf '203.0.113.10\n'; }
if (public_endpoint </dev/null) > "$testdir/prompt" 2>&1; then fail 'EOF accepted an address.'; fi
if valid_ipv4 '999.1.2.3' || valid_ipv4 '01.2.3.4'; then fail 'Invalid IPv4 accepted.'; fi
if approve Activate <<<'' > "$testdir/prompt"; then fail 'Empty approval enabled activation.'; fi

printf 'existing credential\n' | create "$testdir/key"
[[ $(stat -c %a -- "$testdir/key") == 600 ]] || fail 'Private file has unsafe permissions.'
if (require_absent "$testdir/key") >/dev/null 2>&1; then fail 'Existing credential was accepted.'; fi
if printf 'replacement\n' | create "$testdir/key" 2>/dev/null; then fail 'Existing credential was overwritten.'; fi
ln -s "$testdir/key" "$testdir/link"
if printf 'replacement\n' | create "$testdir/link" 2>/dev/null; then fail 'Symlink was followed.'; fi
[[ $(<"$testdir/key") == 'existing credential' ]] || fail 'Credential was modified.'
if (private_directory "$repo/secret") >/dev/null 2>&1; then fail 'Secret directory inside checkout was accepted.'; fi
[[ ! -e $repo/secret ]] || fail 'Checkout rejection created a directory.'
ln -s "$repo" "$testdir/checkout-link"
if (private_directory "$testdir/checkout-link/secret") >/dev/null 2>&1; then fail 'Ancestor symlink bypassed checkout protection.'; fi
private_directory "$testdir/private"
[[ $(stat -c %a -- "$testdir/private") == 700 ]] || fail 'Private directory has unsafe permissions.'

printf 'PASS: detected address, override, failure/EOF handling, approval, credential preservation, private modes and checkout exclusion.\n'
printf 'No real SSH, activation or YubiKey authentication was performed.\n'
