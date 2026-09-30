#!/usr/bin/env bash
# Isolated runner-contract check; no Nix builds, activation or live desktop calls.
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
runner=${1:-"$script_dir/check.sh"}
hook=${2:-"$script_dir/../../../../.githooks/pre-push"}
work=$(mktemp -d "${TMPDIR:-/tmp}/nixcfg-check-test.XXXXXX")
work=$(CDPATH= cd -- "$work" && pwd -P)
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
check 1 full ne
contains "$output" 'NOT RUN: Hyprland'
absent "$calls" Hyprland
contains "$calls" 'path:.#darwinConfigurations.ne.system.drvPath'
absent "$calls" nixosConfigurations
export CHECK_OS=Linux

check 0 full nix
contains "$calls" 'path:.#nixosConfigurations.nix.config.system.build.toplevel'
absent "$calls" darwinConfigurations
check 0 full
contains "$calls" nixosConfigurations
contains "$calls" darwinConfigurations
contains "$calls" 'nixosConfigurations.nixos-server.config.system.build.toplevel.drvPath'
check 0 full nixos-server
contains "$calls" 'nixosConfigurations.nixos-server.config.system.build.toplevel.drvPath'
absent "$calls" 'nixosConfigurations.nix.'
absent "$calls" darwinConfigurations

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
check 2 quick all extra extra
contains "$output" usage:

# Committed changes must still be checked when the worktree is clean.
base=$(git rev-parse HEAD)
git add 'space name.nix'
git -c user.name=Validation -c user.email=validation@example.invalid \
  -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m committed
check 0 quick all "$base"
contains "$calls" 'nix-instantiate <--parse> <space name.nix>'
check 2 quick all missing-comparison-revision
[[ -z "$calls" ]]

# Exercise the real Git pre-push protocol against an isolated local remote.
# Only Nix/Hyprland are stubbed; shell syntax and Git publication are real.
export TMPDIR="$work"
mkdir -p "$work/push-repo/.githooks" "$work/push-repo/.omp/skills/nixcfg-validation/scripts"
cp "$hook" "$work/push-repo/.githooks/pre-push"
chmod +x "$work/push-repo/.githooks/pre-push"
cp "$runner" "$work/push-repo/.omp/skills/nixcfg-validation/scripts/check.sh"
cd "$work/push-repo"
git init -q
git config core.hooksPath .githooks
git config user.name Validation
git config user.email validation@example.invalid
git config commit.gpgsign false
git init --bare -q "$work/remote.git"
git remote add origin "$work/remote.git"
printf 'echo committed\n' > publish.sh
git add .
git commit -q -m publishable
good=$(git rev-parse HEAD)

# Dirty and untracked caller files are not part of the pushed snapshot.
printf 'if then\n' > publish.sh
printf 'if then\n' > untracked.sh
: > "$CHECK_LOG"
git push -q origin HEAD:refs/heads/accepted
[[ "$(git --git-dir="$work/remote.git" rev-parse refs/heads/accepted)" == "$good" ]]
[[ "$(cat publish.sh)" == 'if then' && "$(cat untracked.sh)" == 'if then' ]]
contains "$(cat "$CHECK_LOG")" 'nixosConfigurations.nixos-server.'
[[ "$(git worktree list --porcelain | grep -c '^worktree ')" == 1 ]]

# A committed shell syntax failure blocks publication and cleans its worktree.
git add publish.sh
git commit -q -m invalid
if git push -q origin HEAD:refs/heads/accepted; then
  printf 'FAIL: pre-push accepted invalid committed shell syntax\n' >&2
  exit 1
fi
[[ "$(git --git-dir="$work/remote.git" rev-parse refs/heads/accepted)" == "$good" ]]
[[ "$(git worktree list --porcelain | grep -c '^worktree ')" == 1 ]]

# Ref deletion must remain possible even when local HEAD cannot pass validation.
: > "$CHECK_LOG"
git push -q origin :refs/heads/accepted
[[ ! -s "$CHECK_LOG" ]]
if git --git-dir="$work/remote.git" show-ref --verify --quiet refs/heads/accepted; then
  printf 'FAIL: ref deletion did not reach the remote\n' >&2
  exit 1
fi
printf 'PASS: runner routing, pushed revision isolation, failure rejection and deletion\n'
