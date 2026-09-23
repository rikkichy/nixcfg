#!/usr/bin/env bash
# This file is also sourced by the non-destructive safety regression script.
set +x
set -euo pipefail

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

report_exit() {
  local status=$1
  if (( status != 0 )); then
    printf '\nStopped (status %s). Nothing is automatically unmounted, closed, erased again, or unenrolled.\nKeep this root/recovery shell; inspect /mnt and cryptroot before recovery.\n' "$status" >&2
  fi
}
usage() {
  cat <<'HELP'
Usage: nixcfg-install [--help | --list-disks | --plan] [REPOSITORY]

Without a mode, interactively install nix or nixos-server from a mutable Git
checkout. Run from a trusted, public-source-only checkout on an x86_64 NixOS
UEFI live ISO, with networking and a root KVM terminal:
  sudo nix --extra-experimental-features 'nix-command flakes' run path:.#install -- "$PWD"

--help        No privilege requirements or device access.
--list-disks  Read-only disk inventory and exclusion reasons; no selection.
--plan        The same read-only inventory plus installation/recovery steps.

Installation ERASES ONE WHOLE DISK after exact typed confirmation. It creates
GPT, a 4 GiB FAT32 EFI partition, and a passphrase-protected LUKS2/XFS root.
The source checkout is never modified. Tracked and nonignored untracked files
are copied; .git, .omp, result links and Python cache state are excluded.
Never keep plaintext secrets, private keys or identities in this checkout:
path: flakes include ignored files even before this program starts.

YubiKey/FIDO2 discovery happens BEFORE erase; absence requires explicit DEFER.
Boot and sudo enrollment each require separate approval. Boot enrollment also
requires a protected header backup on mounted, encrypted, off-target media.
Passwords are entered directly into cryptsetup/passwd, never command arguments.
No reboot, forced unmount, enrollment removal, or automatic recovery cleanup.
HELP
}

plan() {
  cat <<'PLAN'
Plan: select host -> review public source -> snapshot and evaluate build plan
-> verify FIDO2 visibility (or explicitly defer) -> select unused whole disk
-> exact ERASE confirmation -> recheck disk -> GPT/EFI/LUKS2/XFS -> mount /mnt
-> copy repository and generate hosts/HOST/hardware.nix from actual hardware
-> nixos-install -> set root and ri passwords -> optional separate boot/sudo
FIDO2 enrollment -> retain mounted system and recovery shell; NEVER auto-reboot.

nix is the repository's AMD 9950X3D/NVIDIA desktop, NOT a generic desktop.
nixos-server is the generic headless/KVM host. Both use user ri.
A build plan is not a completed build or a boot/authentication test. Network,
build, hardware, or token failures can still require recovery after erase.
PLAN
}

# Conservative by design: an unmounted active mapper/RAID holder is still busy.
# Mounted Btrfs components are collected through sysfs, including secondary disks.
classify_disks() {
  jq --arg used "$2" '
    ($used | split("\n") | map(select(length > 0))) as $used |
    [.blockdevices[] | select(.type == "disk") |
      [recurse(.children[]?)] as $nodes |
      . + {reason:
        if any($nodes[]; .ro == true or .ro == 1) then "read-only"
        elif (.name | test("^/dev/(zram|ram)[0-9]+$")) then "RAM device"
        elif any($nodes[]; any(.mountpoints[]?; . != null and . != "")) then "mounted or swap"
        elif any($nodes[]; .type != "disk" and .type != "part") then "active device-mapper/RAID holder"
        elif any($nodes[]; .["maj:min"] as $id | $used | index($id)) then "mounted, source, swap or loop backing device"
        elif any($nodes[]; .fstype == "zfs_member") then "ZFS member; usage cannot be excluded"
        elif .size < 8589934592 then "smaller than 8 GiB"
        else "" end} | del(.children)]
  ' <<<"$1"
}

file_device() {
  local id
  if [[ -b $1 ]]; then
    id=$(lsblk --nodeps --noheadings --raw --output MAJ:MIN "$1") || return 1
  else
    id=$(findmnt --noheadings --raw --output MAJ:MIN --target "$1") || return 1
  fi
  [[ $id =~ ^[0-9]+:[0-9]+$ ]] || return 1
  printf '%s\n' "$id"
}

mounted_btrfs_devices() {
  local entry id
  for entry in /sys/fs/btrfs/*/devices/*/dev; do
    [[ -e $entry ]] || continue
    id=$(cat "$entry") || return 1
    [[ $id =~ ^[0-9]+:[0-9]+$ ]] || return 1
    printf '%s\n' "$id"
  done
}

scan_disks() {
  local blocks used swaps loops file id
  blocks=$(lsblk --json --bytes --paths --output NAME,TYPE,SIZE,MODEL,SERIAL,RO,MAJ:MIN,MOUNTPOINTS,FSTYPE) || return 1
  used=$(findmnt --kernel --noheadings --raw --output MAJ:MIN) || return 1
  id=$(mounted_btrfs_devices) || return 1
  used+=$'\n'"$id"
  if [[ -n ${source:-} ]]; then
    id=$(file_device "$source") || return 1
    used+=$'\n'"$id"
  fi
  swaps=$(swapon --show=NAME --noheadings --raw) || return 1
  while IFS= read -r file; do
    [[ -n $file ]] || continue
    file=$(printf '%b' "$file")
    [[ -f $file || -b $file ]] || return 1
    id=$(file_device "$file") || return 1
    used+=$'\n'"$id"
  done <<<"$swaps"
  # Include every loop backing file, including unmounted loops used by live ISOs.
  loops=$(losetup --list --json --output BACK-FILE) || return 1
  loops=$(jq -r '.loopdevices[]?.["back-file"]' <<<"$loops") || return 1
  while IFS= read -r file; do
    [[ -n $file ]] || continue
    [[ -f $file || -b $file ]] || return 1
    id=$(file_device "$file") || return 1
    used+=$'\n'"$id"
  done <<<"$loops"
  classify_disks "$blocks" "$used"
}

show_disks() {
  printf '\nWhole disks (all usage is rechecked immediately before erase):\n'
  jq -r '.[] | [.name, (.size|tostring)+" bytes", (.model // "unknown model"), (.serial // "no serial"), (if .reason == "" then "candidate" else "EXCLUDED: "+.reason end)] | @tsv' <<<"$disks"
  if (( EUID != 0 )); then
    printf 'Non-root inventory is advisory; root must repeat all usage checks.\n'
  fi
}

require_exact() {
  local answer
  printf '\nType exactly %s: ' "$1" >&2
  IFS= read -r answer || return 1
  [[ $answer == "$1" ]]
}

fido_visible() {
  local listing device found=1
  listing=$(systemd-cryptenroll --fido2-device=list) || return 1
  printf '%s\n' "$listing" >&2
  while read -r device _; do
    if [[ $device == "$1" && $device =~ ^/dev/hidraw[0-9]+$ && -c $device ]]; then found=0; fi
  done <<<"$listing"
  return "$found"
}

check_mount_target() {
  [[ ! -L /mnt && ! -e /dev/mapper/cryptroot ]] || fail '/mnt is a symlink or cryptroot already exists; recover manually.'
  if [[ -d /mnt ]]; then
    [[ $(realpath /mnt) == /mnt ]] || fail 'Unexpected /mnt path.'
    [[ -z $(find /mnt -mindepth 1 -maxdepth 1 -print -quit) ]] || fail '/mnt is not empty; no automatic cleanup.'
  elif [[ -e /mnt ]]; then
    fail '/mnt is not a directory.'
  fi
  if findmnt --mountpoint /mnt --noheadings >/dev/null; then fail '/mnt is already mounted.'; fi
}

backup_header() {
  local parent id ancestry uuid
  printf '\nHeader backups can restore revoked access. Keep them protected, outside the\nrepository and target disk, with your recovery passphrase and a tested ISO.\n'
  printf 'Existing directory on mounted encrypted OFF-TARGET media: '
  IFS= read -r parent
  parent=$(realpath -e -- "$parent")
  [[ -d $parent && $parent != "$source" && $parent != "$source/"* && $parent != /mnt && $parent != /mnt/* ]] || fail 'Unsafe header backup location.'
  id=$(file_device "$parent")
  [[ -b /dev/block/$id ]] || fail 'Backup must be on a mounted block filesystem, not tmpfs/network storage.'
  ancestry=$(lsblk --inverse --json --paths --output NAME,TYPE "/dev/block/$id")
  jq -e --arg disk "$disk" '
    [.. | objects | select(has("type"))] as $nodes |
    any($nodes[]; .type == "crypt") and any($nodes[]; .type == "disk") and
    all($nodes[]; .name != $disk)
  ' <<<"$ancestry" >/dev/null || fail 'Cannot prove backup is encrypted and off the target disk.'
  require_exact 'BACK UP HEADER' || fail 'Header backup not approved; no enrollment performed.'
  uuid=$(cryptsetup luksUUID "$rootpart")
  backup="$parent/$host-$uuid"
  [[ ! -e $backup && ! -L $backup ]] || fail 'Backup directory exists; will not overwrite it.'
  mkdir -m 0700 -- "$backup"
  cryptsetup luksHeaderBackup "$rootpart" --header-backup-file "$backup/before-fido2.header"
  chmod 0600 -- "$backup/before-fido2.header"
  [[ -s $backup/before-fido2.header && -r $backup/before-fido2.header ]] || fail 'Header backup is not readable.'
  sync
}

enroll_boot() {
  local metadata token
  fido_visible "$fido" || fail 'Selected FIDO2 device disappeared or changed; enrollment stopped.'
  printf '\nBoot enrollment adds a slot; it never replaces or removes passphrase slots.\n'
  if ! require_exact 'ENROLL BOOT'; then printf 'Boot FIDO2 enrollment deferred.\n'; return; fi
  printf 'Test the recovery passphrase (NOT the token):\n'
  cryptsetup open --test-passphrase --disable-external-tokens "$rootpart"
  backup_header
  systemd-cryptenroll "$rootpart" --fido2-device="$fido" \
    --fido2-with-client-pin=no --fido2-with-user-presence=yes --fido2-with-user-verification=no
  cryptsetup luksHeaderBackup "$rootpart" --header-backup-file "$backup/after-fido2.header"
  chmod 0600 -- "$backup/after-fido2.header"
  sync
  metadata=$(cryptsetup luksDump --dump-json-metadata "$rootpart")
  token=$(jq -er '[.tokens | to_entries[] | select(.value.type == "systemd-fido2") |
    select(.value["fido2-clientPin-required"] == false and .value["fido2-up-required"] == true and .value["fido2-uv-required"] == false) | .key] |
    if length == 1 then .[0] else error("unexpected FIDO2 token policy/count") end' <<<"$metadata")
  printf '\nTest token-only unlock now; touch the selected token. No PIN is expected.\n'
  LD_LIBRARY_PATH="${NIXCFG_CRYPTSETUP_PLUGINS:?Run the packaged installer}" \
    cryptsetup open --test-passphrase --token-only --token-id "$token" "$rootpart"
  printf '\nRetest the original passphrase after enrollment:\n'
  cryptsetup open --test-passphrase --disable-external-tokens "$rootpart"
  printf 'Live token and passphrase checks passed; cold boot remains UNTESTED.\n'
}

enroll_sudo() {
  local mapping=/mnt/etc/u2f-mappings registration
  [[ ! -e $mapping && ! -L $mapping ]] || fail 'Existing /etc/u2f-mappings must be backed up and merged manually, never overwritten.'
  printf '\nSudo enrollment: leave only the intended YubiKey connected; touch it when requested.\n'
  if ! require_exact 'ENROLL SUDO'; then printf 'Sudo U2F enrollment deferred; use the ri password.\n'; return; fi
  pamu2fcfg --username=ri --origin="pam://$host" --appid="pam://$host" >"$work/u2f-mapping"
  registration=$(<"$work/u2f-mapping")
  [[ $registration == ri:?* && $registration != *$'\n'* ]] || fail 'Unexpected U2F registration output.'
  chmod 0600 "$work/u2f-mapping"
  # O_EXCL creation, not a clobbering install/copy, protects an existing mapping.
  (set -o noclobber; cat "$work/u2f-mapping" >"$mapping")
  chown root:root "$mapping"
  chmod 0600 "$mapping"
  rm -- "$work/u2f-mapping"
  printf 'Sudo registration installed root:root 0600; PAM authentication remains UNTESTED.\n'
}

main() {
  local mode=install selection identity current seq esp row files password_status
  local -a nixcmd=(nix --extra-experimental-features 'nix-command flakes')
  if [[ ${1:-} == --help || ${1:-} == -h ]]; then usage; return; fi
  if [[ ${1:-} == --list-disks || ${1:-} == --plan ]]; then mode=${1#--}; shift; fi
  (( $# <= 1 )) || fail 'Expected at most one repository path; see --help.'
  [[ ${1:-} != -* ]] || fail 'Unknown option; see --help.'
  source=$(realpath -e -- "${1:-$PWD}")
  if [[ $mode != install ]]; then
    disks=$(scan_disks) || fail 'Cannot establish disk usage; inventory unavailable (try root). No mutation performed.'
    show_disks
    [[ $mode != plan ]] || plan
    return
  fi
  (( EUID == 0 )) || fail 'Installation requires root; --help and --list-disks are read-only.'
  [[ -t 0 && -t 1 ]] || fail 'Installation requires an interactive terminal (KVM/console).'
  [[ $(uname -m) == x86_64 && -d /sys/firmware/efi ]] || fail 'Boot an x86_64 UEFI NixOS live ISO.'
  [[ -e /etc/NIXOS && -d /iso ]] || fail 'Installation is restricted to the NixOS live ISO (/etc/NIXOS and /iso).'
  findmnt --mountpoint /iso --noheadings >/dev/null || fail '/iso is not mounted; cannot establish live-media safety.'
  [[ -f $source/flake.nix && -f $source/flake.lock && -d $source/.git ]] || fail 'Provide the mutable repository root with .git, flake.nix and flake.lock.'
  check_mount_target
  umask 077
  unset PASSWORD NEWPASSWORD PIN
  export SYSTEMD_COLORS=0 SYSTEMD_PAGER=cat
  trap 'report_exit "$?"' EXIT
  trap 'printf "\nInterrupted. Leaving disks, mappings, mounts and recovery files untouched.\n" >&2; exit 130' INT TERM
  plan
  printf '\nHost [nix / nixos-server]: '
  IFS= read -r host
  case "$host" in nix|nixos-server) ;; *) fail 'Unknown host.' ;; esac
  [[ -f $source/hosts/$host/hardware.nix ]] || fail 'Selected host hardware source is missing.'
  printf '\nReview this checkout before continuing: %s\nOnly PUBLIC configuration and encrypted ciphertext may be included.\nDo not add private SOPS identities; this installer does not provision them.\n' "$source"
  require_exact 'PUBLIC SOURCE ONLY' || fail 'Source review not confirmed.'
  work=$(mktemp -d /run/nixcfg-install.XXXXXX)
  mkdir -m 0755 "$work/repo"
  git -c safe.directory="$source" -C "$source" ls-files --cached --others --exclude-standard --deduplicate -z >"$work/files"
  files=$work/files
  tar --create --file="$work/source.tar" --directory="$source" --null --verbatim-files-from \
    --exclude=.git --exclude=.omp --exclude=result --exclude='result-*' --exclude=__pycache__ \
    --no-recursion --files-from="$files"
  tar --extract --file="$work/source.tar" --directory="$work/repo" --no-same-owner
  rm -- "$work/source.tar"
  printf '\nEvaluating the selected build plan BEFORE erase (not a full build):\n'
  "${nixcmd[@]}" build --dry-run --no-link --no-write-lock-file "path:$work/repo#nixosConfigurations.$host.config.system.build.toplevel"
  printf '\nVisible FIDO2 devices (must be forwarded through your KVM, not merely a keyboard):\n'
  systemd-cryptenroll --fido2-device=list || printf 'FIDO2 discovery failed; only explicit DEFER may continue.\n'
  printf 'Enter a listed /dev/hidrawN, or type DEFER for password-only installation: '
  IFS= read -r fido
  if [[ $fido != DEFER ]]; then
    fido_visible "$fido" || fail 'Not a visible FIDO2 device. Restart and explicitly DEFER if necessary.'
  else
    printf 'Boot and sudo token enrollment explicitly deferred; password recovery is mandatory.\n'
  fi
  disks=$(scan_disks) || fail 'Cannot establish device usage; refusing erase.'
  show_disks
  printf '\nEnter the exact candidate disk path, e.g. /dev/nvme0n1: '
  IFS= read -r disk
  row=$(jq -cer --arg disk "$disk" '[.[] | select(.name == $disk and .reason == "")] | if length == 1 then .[0] else error("not an unused whole disk") end' <<<"$disks")
  [[ -b $disk ]] || fail 'Selected disk is not a block device.'
  identity=$(jq -c '[.name, .["maj:min"], .size, .model, .serial]' <<<"$row")
  seq=$(cat "/sys/class/block/${disk##*/}/diskseq")
  printf '\nALL DATA ON THIS DISK WILL BE DESTROYED for host %s:\n%s\n' "$host" "$row"
  require_exact "ERASE $disk" || fail 'Exact erase confirmation did not match; nothing erased.'
  # Hold a device lock and repeat every exclusion after the human confirmation.
  exec {disk_lock}<"$disk"
  flock --nonblock "$disk_lock" || fail 'Another process has locked the disk.'
  disks=$(scan_disks) || fail 'Device usage recheck failed.'
  current=$(jq -cer --arg disk "$disk" '.[] | select(.name == $disk and .reason == "") | [.name, .["maj:min"], .size, .model, .serial]' <<<"$disks")
  [[ $current == "$identity" && $(cat "/sys/class/block/${disk##*/}/diskseq") == "$seq" ]] || fail 'Disk identity or use changed; refusing erase.'
  check_mount_target
  parted --script "$disk" -- mklabel gpt mkpart ESP fat32 1MiB 4097MiB set 1 esp on mkpart cryptroot 4097MiB 100%
  blockdev --rereadpt "$disk"
  # Let udev process partition events before waiting for its queue.
  flock --unlock "$disk_lock"
  exec {disk_lock}<&-
  udevadm settle
  selection=$(lsblk --json --paths --output NAME,TYPE,PARTLABEL "$disk")
  esp=$(jq -er '.blockdevices[0].children | map(select(.type == "part" and .partlabel == "ESP")) | if length == 1 then .[0].name else error("EFI partition missing/ambiguous") end' <<<"$selection")
  rootpart=$(jq -er '.blockdevices[0].children | map(select(.type == "part" and .partlabel == "cryptroot")) | if length == 1 then .[0].name else error("root partition missing/ambiguous") end' <<<"$selection")
  mkfs.fat -F 32 -n BOOT "$esp"
  printf '\nChoose a strong RECOVERY passphrase. Keep it independently of the YubiKey.\n'
  cryptsetup luksFormat --type luks2 "$rootpart"
  cryptsetup open "$rootpart" cryptroot
  mkfs.xfs -L nixos /dev/mapper/cryptroot
  install -d -m 0755 /mnt
  mount /dev/mapper/cryptroot /mnt
  install -d -m 0755 /mnt/boot /mnt/etc /mnt/etc/nixos
  mount "$esp" /mnt/boot
  cp -a "$work/repo/." /mnt/etc/nixos/
  # Generate only after the real target root and ESP are mounted. Never edit source.
  nixos-generate-config --root /mnt --show-hardware-config >"$work/hardware.nix"
  rm -- "/mnt/etc/nixos/hosts/$host/hardware.nix"
  install -m 0644 "$work/hardware.nix" "/mnt/etc/nixos/hosts/$host/hardware.nix"
  nixos-install --root /mnt --flake "path:/mnt/etc/nixos#$host" --no-root-passwd --no-write-lock-file
  printf '\nSet a nonempty ROOT recovery password:\n'
  nixos-enter --root /mnt -c 'passwd root'
  password_status=$(nixos-enter --root /mnt -c 'passwd --status root')
  [[ $password_status == 'root P '* ]] || fail 'Root does not have an unlocked password.'
  printf '\nSet a nonempty RI password (required for sudo fallback):\n'
  nixos-enter --root /mnt -c 'passwd ri'
  password_status=$(nixos-enter --root /mnt -c 'passwd --status ri')
  [[ $password_status == 'ri P '* ]] || fail 'ri does not have an unlocked password.'
  printf '\nConfirm the original LUKS passphrase independently of any token:\n'
  cryptsetup open --test-passphrase --disable-external-tokens "$rootpart"
  if [[ $fido != DEFER ]]; then enroll_boot; enroll_sudo; fi
  sync
  cat <<'DONE'

Installation commands completed. The target stays mounted at /mnt; no reboot.
Keep the root shell, tested recovery ISO, passphrases and protected off-disk
header backups. Boot/sudo authentication is NOT proven by installation.
Before an operator-approved reboot inspect the target crypttab/initrd: exactly
one cryptroot mapping, FIDO2/USB/HID support, no headless/passwordless fallback.
From a separate ri terminal in the target, test sudo AND sudo -i with fresh
sudo -k before EACH attempt: touch/no PIN, no token/correct password, wrong
password, no touch, and an unregistered key. Keep root until failures reject
access and password fallback works. Plan cold-boot token/no-token/no-touch
checks and recovery before leaving the KVM. Do not retire any recovery slot.
SOPS/PIV identities, private service data and VPN provisioning are separate;
this installer never copies private live-system secrets into the target.
DONE
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
