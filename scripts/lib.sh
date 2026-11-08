# shellcheck shell=bash
# Shared helpers; the root *.nix packages prepend this file to each script.

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

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

valid_hostname() { [[ ${#1} -le 253 && $1 =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; }

# noclobber rejects existing files and symlinks; umask keeps new files private.
create() ( umask 077; set -o noclobber; cat > "$1" )

# Server setup modes: private umask, workdir cleanup via report_exit, signal exits.
setup_traps() {
  umask 077
  trap 'report_exit "$?"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
}
