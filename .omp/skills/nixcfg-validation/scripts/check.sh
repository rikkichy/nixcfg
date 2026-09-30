#!/usr/bin/env bash

set -u

mode="${1:-quick}"
host="${2:-all}"
base="${3:-HEAD}"
if [[ $# -gt 3 || ! "$mode" =~ ^(quick|full)$ || ! "$host" =~ ^(nix|ne|nixos-server|all)$ ]]; then
  printf 'usage: %s [quick|full] [nix|ne|nixos-server|all] [comparison-revision]\n' "$0" >&2
  exit 2
fi

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'error: not inside a Git worktree\n' >&2
  exit 2
}
cd "$root" || exit 2
if ! git cat-file -e "${base}^{tree}" 2>/dev/null; then
  printf 'error: invalid comparison revision: %s\n' "$base" >&2
  exit 2
fi

failures=0
checks=0
skipped=0

run() {
  local label=$1
  shift
  checks=$((checks + 1))
  printf '\n==> %s\n' "$label"
  if "$@"; then
    printf 'ok: %s\n' "$label"
  else
    local status=$?
    printf 'FAILED (%d): %s\n' "$status" "$label" >&2
    failures=$((failures + 1))
  fi
}

parse_nix() {
  nix-instantiate --parse "$1" > /dev/null
}

run "Git diff whitespace" git diff --check "$base" --

hypr_changed=false
nix_inputs_changed=false

# NUL-delimited paths and read work with macOS Bash 3.2 as well as Linux Bash.
while IFS= read -r -d '' file; do
  case "$file" in
    *.nix)
      [[ ! -f "$file" ]] || run "Parse $file" parse_nix "$file"
      nix_inputs_changed=true
      ;;
    flake.lock|hosts/*/pkgs/*|hosts/*/dotfiles/*|common/dotfiles/*|.secrets/*)
      nix_inputs_changed=true
      ;;
  esac

  case "$file" in
    *.sh)
      [[ ! -f "$file" ]] || run "Shell syntax $file" bash -n "$file"
      ;;
    hosts/nix/dotfiles/ricing/hypr/*)
      hypr_changed=true
      ;;
  esac
done < <(
  git diff --name-only -z "$base" --
  git ls-files --others --exclude-standard -z
)

if [[ "$hypr_changed" == true ]]; then
  if [[ "$(uname -s)" == Linux ]]; then
    run "Hyprland configuration" Hyprland --verify-config \
      --config "$root/hosts/nix/dotfiles/ricing/hypr/hyprland.lua"
  else
    printf '\nNOT RUN: Hyprland configuration requires Linux; verify it on host nix.\n'
    skipped=$((skipped + 1))
  fi
fi

evaluate_nix() {
  local log status derivations store_paths
  log=$(mktemp "${TMPDIR:-/tmp}/nixcfg-eval.XXXXXX") || return 1

  if nix build --dry-run \
    'path:.#nixosConfigurations.nix.config.system.build.toplevel' \
    > "$log" 2>&1; then
    grep '^warning:' "$log" || true
    if ! grep -E \
      '^these [0-9]+ (derivations? will be built|paths? will be fetched)' \
      "$log"; then
      derivations=$(grep -c '\.drv$' "$log" || true)
      store_paths=$(grep -c '^  /nix/store/' "$log" || true)
      printf '%d derivation(s), %d listed store path(s)\n' "$derivations" "$store_paths"
    fi
    rm -f "$log"
    return 0
  else
    status=$?
    tail -n 200 "$log" >&2
    printf 'full evaluation log: %s\n' "$log" >&2
    return "$status"
  fi
}

evaluate_ne() {
  nix eval --raw 'path:.#darwinConfigurations.ne.system.drvPath' && printf '\n'
}

evaluate_server() {
  nix eval --raw 'path:.#nixosConfigurations.nixos-server.config.system.build.toplevel.drvPath' && printf '\n'
}

if [[ "$mode" == full ]]; then
  if [[ "$host" == nix || "$host" == all ]]; then
    run "NixOS system evaluation" evaluate_nix
  fi
  if [[ "$host" == ne || "$host" == all ]]; then
    run "Darwin system evaluation (not a build)" evaluate_ne
  fi
  if [[ "$host" == nixos-server || "$host" == all ]]; then
    run "Server system evaluation (not a build)" evaluate_server
  fi
elif [[ "$nix_inputs_changed" == true ]]; then
  printf '\nnote: Nix-managed inputs changed; full evaluation is owned by pre-push.\n'
fi

printf '\n%d check(s), %d failure(s), %d not run\n' "$checks" "$failures" "$skipped"
if (( failures > 0 )) || [[ "$mode" == full && "$skipped" -gt 0 ]]; then
  exit 1
fi
