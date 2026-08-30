#!/usr/bin/env bash

set -u

mode="${1:-quick}"
case "$mode" in
  quick|full) ;;
  *)
    printf 'usage: %s [quick|full]\n' "$0" >&2
    exit 2
    ;;
esac

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'error: not inside a Git worktree\n' >&2
  exit 2
}
cd "$root"

mapfile -t changed_files < <(
  {
    git diff --name-only HEAD --
    git ls-files --others --exclude-standard
  } | awk 'NF' | sort -u
)

failures=0
checks=0

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

run "Git diff whitespace" git diff --check HEAD --

nix_files=()
shell_files=()
hypr_changed=false
nix_inputs_changed=false

for file in "${changed_files[@]}"; do
  case "$file" in
    *.nix)
      [[ -f "$file" ]] && nix_files+=("$file")
      nix_inputs_changed=true
      ;;
    flake.lock|dotfiles/*)
      nix_inputs_changed=true
      ;;
  esac

  case "$file" in
    *.sh)
      [[ -f "$file" ]] && shell_files+=("$file")
      ;;
    hypr/*)
      hypr_changed=true
      ;;
  esac
done

parse_nix() {
  nix-instantiate --parse "$1" > /dev/null
}

for file in "${nix_files[@]}"; do
  run "Parse $file" parse_nix "$file"
done

for file in "${shell_files[@]}"; do
  run "Shell syntax $file" bash -n "$file"
done

if [[ "$hypr_changed" == true ]]; then
  run "Hyprland configuration" Hyprland --verify-config
fi

evaluate_system() {
  local log status derivations store_paths
  log=$(mktemp "${TMPDIR:-/tmp}/nixcfg-eval.XXXXXX.log")

  if nix build --dry-run \
    'path:.#nixosConfigurations.nix.config.system.build.toplevel' \
    > "$log" 2>&1; then
    grep '^warning:' "$log" || true
    if ! grep -E \
      '^these [0-9]+ (derivations? will be built|paths? will be fetched)' \
      "$log"; then
      derivations=$(grep -c '\.drv$' "$log" || true)
      store_paths=$(grep -c '^  /nix/store/' "$log" || true)
      printf '%d derivation(s), %d listed store path(s)\n' \
        "$derivations" "$store_paths"
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

if [[ "$mode" == full ]]; then
  run "NixOS system evaluation" evaluate_system
elif [[ "$nix_inputs_changed" == true ]]; then
  printf '\nnote: Nix-managed inputs changed; run `%s full` before completion.\n' "$0"
fi

printf '\n%d check(s), %d failure(s)\n' "$checks" "$failures"
if (( failures > 0 )); then
  exit 1
fi
