#!/usr/bin/env bash
# Non-destructive checks: only disposable test credentials, no devices or installed state.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

# Missing/failed token discovery must stop before enrollment approval or erasure.
for status in 0 1; do
  if bash -c 'source scripts/install.sh; discovery_status=$1; systemd-cryptenroll() { return "$discovery_status"; }; select_fido' -- "$status"; then
    printf 'FAIL: accepted missing token\n' >&2
    exit 1
  fi
done

# Exercise real approval parsing and fail-fast orchestration without a USB token.
for answers in $'n\n' $'y\nn\n' $'\n' $'y\n'; do
  if bash -c 'source scripts/install.sh; select_fido() { :; }; plan_enrollment' <<<"$answers"; then
    printf 'FAIL: accepted missing enrollment approval\n' >&2
    exit 1
  fi
done
bash -c 'source scripts/install.sh; select_fido() { :; }; plan_enrollment' <<<'y
y'

# Mandatory menus cannot accept the former skip selection.
bash -c 'source scripts/install.sh; choose "Required token" "" "Token"; [[ $choice == 1 ]]' <<<'0
1'
printf 'PASS: required token discovery and both enrollment approvals\n'

# Real key generation outside the checkout; preserve existing private/public keys.
(
  source scripts/install.sh
  target=$(mktemp -d)
  trap 'rm -rf -- "$target"' EXIT
  prepare_initrd_ssh "$target"
  key="$target/etc/secrets/initrd/ssh_host_ed25519_key"
  [[ $(stat -c %a "$key") == 600 ]]
  [[ $(stat -c %a "${key%/*}") == 700 ]]
  original=$(sha256sum "$key" "$key.pub")
  if (prepare_initrd_ssh "$target"); then
    printf 'FAIL: overwrote an existing initrd host key\n' >&2
    exit 1
  fi
  [[ $(sha256sum "$key" "$key.pub") == "$original" ]]
  rm -- "$key"
  if (prepare_initrd_ssh "$target"); then
    printf 'FAIL: overwrote an orphaned public key\n' >&2
    exit 1
  fi
)
printf 'PASS: isolated initrd host key generation and overwrite refusal\n'
