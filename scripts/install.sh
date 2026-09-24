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
  sudo nix --extra-experimental-features 'nix-command flakes' run path:.#install

--help        No privilege requirements or device access.
--list-disks  Read-only disk inventory and exclusion reasons; no selection.
--plan        Optional read-only inventory and step outline; no host evaluation.
REPOSITORY    Defaults to the current directory.

Installation ERASES ONE WHOLE DISK after a single ERASE confirmation. It creates
GPT, a 4 GiB FAT32 EFI partition, and a passphrase-protected LUKS2/XFS root.
The source checkout is never modified. Tracked and nonignored untracked files
are copied; .git, .omp, result links and Python cache state are excluded.
Never keep plaintext secrets, private keys or identities in this checkout:
path: flakes include ignored files even before this program starts.

Numbered menus select the host, disk and YubiKey. USB/removable targets are
hidden until "Show external disks"; --list-disks includes all exclusion reasons.
Boot and sudo enrollment have separate y/N approvals BEFORE erase.
Passwords are entered directly into cryptsetup/passwd, never command arguments.
No reboot, forced unmount, enrollment removal, or automatic recovery cleanup.
HELP
}

plan() {
  cat <<'PLAN'
Plan: select host -> snapshot and evaluate build plan -> select unused disk
-> select YubiKey (or skip) -> approve sudo/boot enrollment
-> ERASE confirmation -> recheck disk -> GPT/EFI/LUKS2/XFS -> mount /mnt
-> copy repository and generate hosts/HOST/hardware.nix from actual hardware
-> nixos-install -> set root and ri passwords -> approved FIDO2 enrollments
-> retain mounted system and recovery shell; NEVER auto-reboot.

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
  blocks=$(lsblk --json --bytes --paths --output NAME,TYPE,SIZE,VENDOR,MODEL,SERIAL,TRAN,RM,RO,MAJ:MIN,MOUNTPOINTS,FSTYPE) || return 1
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

disk_label() {
  jq -r '[
    .name,
    ([.vendor, .model] | map(. // "" | gsub("^\\s+|\\s+$"; "")) | map(select(length > 0)) | join(" ")),
    (if .size >= 1000000000000 then
      (((.size / 1099511627776 * 100 | round) / 100 | tostring) + " TiB")
    else (((.size / 1073741824 * 10 | round) / 10 | tostring) + " GiB") end)
  ] | @tsv' <<<"$1"
}

show_disks() {
  local row
  printf '\nWhole disks (including excluded and external devices):\n'
  while IFS= read -r row; do
    printf '%s  %s\n' "$(disk_label "$row")" \
      "$(jq -r 'if .reason == "" then "candidate" else "EXCLUDED: " + .reason end' <<<"$row")"
  done < <(jq -c '.[]' <<<"$disks")
  if (( EUID != 0 )); then
    printf 'Non-root inventory is advisory; root must repeat all usage checks.\n'
  fi
}

# Menus return a validated index in choice; zero is available only when labelled.
choose() {
  local title=$1 zero=$2 label i=0 max
  shift 2
  max=$#
  printf '\n%s\n' "$title"
  for label in "$@"; do
    i=$((i + 1))
    printf '  %s  %s\n' "$i" "$label"
  done
  [[ -z $zero ]] || printf '  0  %s\n' "$zero"
  while :; do
    printf 'Select: '
    IFS= read -r choice || fail 'Input closed; cancelled.'
    if [[ $choice =~ ^(0|[1-9][0-9]*)$ && ${#choice} -le ${#max} ]] &&
      (( choice <= max )) && { (( choice > 0 )) || [[ -n $zero ]]; }; then return; fi
    printf 'Choose a listed number, or Ctrl+C to cancel.\n'
  done
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

confirm_erase() {
  local answer
  printf '\nERASE ALL DATA for %s:\n%s\nSerial: %s\n' "$host" \
    "$(disk_label "$row")" "$(jq -r '.serial // "unknown"' <<<"$row")"
  while :; do
    printf 'Type ERASE (Ctrl+C cancels): '
    IFS= read -r answer || fail 'Input closed; nothing erased.'
    [[ $answer != ERASE ]] || return 0
    printf 'Confirmation did not match; nothing erased.\n'
  done
}

disk_candidates() {
  jq --argjson external "$1" '[.[] | select(.reason == "") |
    select($external or ((.tran != "usb") and (.rm != true) and (.rm != 1)))]' <<<"$disks"
}

select_disk() {
  local external=false candidates count
  local -a labels
  while :; do
    candidates=$(disk_candidates "$external")
    count=$(jq 'length' <<<"$candidates")
    labels=()
    while IFS= read -r row; do labels+=("$(disk_label "$row")"); done < <(jq -c '.[]' <<<"$candidates")
    if [[ $external == false ]]; then labels+=("Show external disks"); fi
    (( ${#labels[@]} > 0 )) || fail 'No unused disks available; use --list-disks for exclusion reasons.'
    choose 'Installation disk (unused whole disks only)' '' "${labels[@]}"
    if (( choice > count )); then external=true; continue; fi
    row=$(jq -c --argjson index "$((choice - 1))" '.[$index]' <<<"$candidates")
    disk=$(jq -r '.name' <<<"$row")
    return
  done
}

select_fido() {
  local listing device description
  local -a devices=() labels=()
  listing=$(systemd-cryptenroll --fido2-device=list) || listing=''
  while read -r device description; do
    [[ $device =~ ^/dev/hidraw[0-9]+$ && -c $device ]] || continue
    devices+=("$device")
    labels+=("$description ($device)")
  done <<<"$listing"
  choose 'YubiKey / FIDO2 (USB forwarding required)' 'Skip enrollment; use passwords' "${labels[@]}"
  fido=''
  if (( choice > 0 )); then
    fido=${devices[choice-1]}
    fido_visible "$fido" || fail 'Selected FIDO2 device disappeared.'
  fi
}

fido_visible() {
  local listing device found=1
  listing=$(systemd-cryptenroll --fido2-device=list) || return 1
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

plan_enrollment() {
  boot_enroll=false
  sudo_enroll=false
  select_fido
  [[ -n $fido ]] || return 0
  if approve 'Enable YubiKey for sudo?'; then sudo_enroll=true; fi
  if approve 'Enable YubiKey for disk unlock?'; then boot_enroll=true; fi
}

enroll_boot() {
  local metadata token
  fido_visible "$fido" || fail 'Selected FIDO2 device disappeared or changed; enrollment stopped.'
  printf '\nEnrolling boot FIDO2; retaining the tested recovery passphrase slot.\n'
  systemd-cryptenroll "$rootpart" --fido2-device="$fido" \
    --fido2-with-client-pin=no --fido2-with-user-presence=yes --fido2-with-user-verification=no
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

generate_hardware_config() {
  # Formatting changes UUIDs without necessarily refreshing udev's by-uuid links.
  # The hardware generator picks those links by device number, not on-disk UUID.
  udevadm trigger --action=change --settle "$esp" "$rootpart" /dev/mapper/cryptroot
  nixos-generate-config --root "$1" --show-hardware-config >"$work/hardware.nix"
}

verify_boot_devices() {
  local luks_uuid esp_uuid devices
  luks_uuid=$(cryptsetup luksUUID "$rootpart")
  esp_uuid=$(blkid --probe --match-tag UUID --output value "$esp")
  [[ -n $luks_uuid && -n $esp_uuid ]] || fail 'Cannot read fresh disk UUIDs; refusing installation.'
  devices=$("${nixcmd[@]}" eval --json --no-write-lock-file \
    "path:/mnt/etc/nixos#nixosConfigurations.$host.config" --apply \
    'c: { luks = builtins.mapAttrs (_: v: v.device) c.boot.initrd.luks.devices;
          root = c.fileSystems."/".device; esp = c.fileSystems."/boot".device; }')
  jq -e --arg luks "/dev/disk/by-uuid/$luks_uuid" --arg esp "/dev/disk/by-uuid/$esp_uuid" \
    '. == {luks: {cryptroot: $luks}, root: "/dev/mapper/cryptroot", esp: $esp}' \
    <<<"$devices" >/dev/null ||
    fail 'Boot configuration does not match the freshly formatted disk UUIDs; refusing installation.'
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
  choose 'Host' '' 'nix (AMD/NVIDIA desktop)' 'nixos-server'
  case "$choice" in 1) host=nix ;; 2) host=nixos-server ;; esac
  [[ -f $source/hosts/$host/hardware.nix ]] || fail 'Selected host hardware source is missing.'
  printf '\nSource: %s — public configuration/encrypted ciphertext only; no private identities.\n' "$source"
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
  disks=$(scan_disks) || fail 'Cannot establish device usage; refusing erase.'
  select_disk
  [[ -b $disk ]] || fail 'Selected disk is not a block device.'
  identity=$(jq -c '[.name, .["maj:min"], .size, .model, .serial]' <<<"$row")
  seq=$(cat "/sys/class/block/${disk##*/}/diskseq")
  plan_enrollment
  confirm_erase
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
  cryptsetup luksFormat --type luks2 --batch-mode --verify-passphrase "$rootpart"
  cryptsetup open "$rootpart" cryptroot
  mkfs.xfs -L nixos /dev/mapper/cryptroot
  install -d -m 0755 /mnt
  mount /dev/mapper/cryptroot /mnt
  install -d -m 0755 /mnt/boot /mnt/etc /mnt/etc/nixos
  mount "$esp" /mnt/boot
  cp -a "$work/repo/." /mnt/etc/nixos/
  # Generate only after the real target root and ESP are mounted. Never edit source.
  generate_hardware_config /mnt
  rm -- "/mnt/etc/nixos/hosts/$host/hardware.nix"
  install -m 0644 "$work/hardware.nix" "/mnt/etc/nixos/hosts/$host/hardware.nix"
  verify_boot_devices
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
  if [[ $boot_enroll == true ]]; then enroll_boot; fi
  if [[ $sudo_enroll == true ]]; then enroll_sudo; fi
  sync
  cat <<'DONE'

Installation commands completed. The target stays mounted at /mnt; no reboot.
Keep the root shell, tested recovery ISO and passphrases.
Boot/sudo authentication is NOT proven by installation.
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
