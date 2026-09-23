#!/usr/bin/env bash
# Isolated runner-contract check; no Nix builds, activation or live desktop calls.
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
runner=${1:-"$script_dir/check.sh"}
work=$(mktemp -d "${TMPDIR:-/tmp}/nixcfg-check-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/repo"
export CHECK_LOG="$work/calls"
export CHECK_OS=Linux
export PATH="$work/bin:$PATH"

cat > "$work/bin/nix" <<'SH'
#!/bin/sh
printf '%s' "${0##*/}" >> "$CHECK_LOG"
printf ' <%s>' "$@" >> "$CHECK_LOG"
printf '\n' >> "$CHECK_LOG"
case "${0##*/}" in
  nix-instantiate) exit "${CHECK_PARSE_STATUS:-0}" ;;
  nix) printf '/nix/store/fixture.drv\n'; exit "${CHECK_EVAL_STATUS:-0}" ;;
esac
SH
cp "$work/bin/nix" "$work/bin/nix-instantiate"
cp "$work/bin/nix" "$work/bin/Hyprland"
cat > "$work/bin/uname" <<'SH'
#!/bin/sh
printf '%s\n' "$CHECK_OS"
SH
chmod +x "$work/bin/"*
cd "$work/repo"
git init -q
git -c user.name=Validation -c user.email=validation@example.invalid \
  -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q --allow-empty -m fixture

check() {
  local expected=$1
  shift
  : > "$CHECK_LOG"
  status=0
  output=$(bash "$runner" "$@" 2>&1) || status=$?
  if [[ "$status" != "$expected" ]]; then
    printf 'Expected exit %s, got %s:\n%s\n' "$expected" "$status" "$output" >&2
    exit 1
  fi
  calls=$(cat "$CHECK_LOG")
}
contains() {
  case "$1" in
    *"$2"*) ;;
    *) printf 'Missing %s in:\n%s\n' "$2" "$1" >&2; exit 1 ;;
  esac
}
absent() {
  case "$1" in
    *"$2"*) printf 'Unexpected %s in:\n%s\n' "$2" "$1" >&2; exit 1 ;;
  esac
}

# An obsolete root hypr tree must not trigger validation of the live desktop.
mkdir -p hypr
printf 'return {}\n' > hypr/unused.lua
check 0 quick
absent "$calls" Hyprland

# Shared assets require full evaluation even without a changed Nix expression.
mkdir -p common/dotfiles
printf 'theme\n' > common/dotfiles/palette.conf
check 0 quick
contains "$output" 'Nix-managed inputs changed'

mkdir -p hosts/nix/dotfiles/ricing/hypr
printf 'return {}\n' > hosts/nix/dotfiles/ricing/hypr/hyprland.lua
printf '{}\n' > 'space name.nix'
check 0 quick
contains "$calls" 'nix-instantiate <--parse> <space name.nix>'
contains "$calls" "Hyprland <--verify-config> <--config> <$work/repo/hosts/nix/dotfiles/ricing/hypr/hyprland.lua>"
absent "$calls" 'nix <'

export CHECK_OS=Darwin
check 0 full ne
contains "$output" 'NOT RUN: Hyprland'
absent "$calls" Hyprland
contains "$calls" 'path:.#darwinConfigurations.ne.system.drvPath'
absent "$calls" nixosConfigurations

check 0 full nix
contains "$calls" 'path:.#nixosConfigurations.nix.config.system.build.toplevel'
absent "$calls" darwinConfigurations
check 0 full
contains "$calls" nixosConfigurations
contains "$calls" darwinConfigurations

export CHECK_PARSE_STATUS=1
check 1 full ne
contains "$output" 'FAILED (1): Parse space name.nix'
contains "$calls" darwinConfigurations
unset CHECK_PARSE_STATUS
export CHECK_EVAL_STATUS=1
check 1 full ne
contains "$output" 'FAILED (1): Darwin system evaluation'
unset CHECK_EVAL_STATUS

check 2 full unknown
contains "$output" usage:
[[ -z "$calls" ]]
check 2 quick all extra
contains "$output" usage:
printf 'PASS: relocated paths, shared assets, spaced filenames, host selection, platform skips and failure propagation\n'
