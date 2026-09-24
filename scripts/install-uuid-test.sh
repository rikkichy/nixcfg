#!/usr/bin/env bash
# Run only in a disposable Linux VM: uses private loop devices and pauses udev.
# Requires the installer's runtime tools and nixos-generate-config on PATH.
set -euo pipefail
# shellcheck source=scripts/install.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/install.sh"
(( EUID == 0 )) || fail 'Run this regression as root in a disposable Linux VM.'
[[ ! -e /dev/mapper/cryptroot ]] || fail 'cryptroot already exists; use a disposable VM.'

work=$(mktemp -d /tmp/nixcfg-uuid.XXXXXX)
rootpart='' esp='' mounted=false opened=false paused=false
cleanup() {
  if [[ $paused == true ]]; then udevadm control --start-exec-queue; fi
  if [[ $mounted == true ]]; then umount "$work/target"; fi
  if [[ $opened == true ]]; then cryptsetup close cryptroot; fi
  if [[ -n $esp ]]; then losetup -d "$esp"; fi
  if [[ -n $rootpart ]]; then losetup -d "$rootpart"; fi
  rm -rf -- "$work"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# Disposable test data only; /dev/zero is not a production encryption key.
truncate -s 512M "$work/root.img"
truncate -s 64M "$work/esp.img"
rootpart=$(losetup --find --show "$work/root.img")
esp=$(losetup --find --show "$work/esp.img")
mkfs.fat -F 32 "$esp" >/dev/null
for _ in 1 2; do
  cryptsetup luksFormat --batch-mode --pbkdf pbkdf2 --key-file /dev/zero --keyfile-size 32 "$rootpart"
  udevadm trigger --action=change --settle "$rootpart"
done
cryptsetup open --key-file /dev/zero --keyfile-size 32 "$rootpart" cryptroot
opened=true
mkfs.xfs -q /dev/mapper/cryptroot
mkdir "$work/target"
mount /dev/mapper/cryptroot "$work/target"
mounted=true
udevadm settle
old_uuid=$(cryptsetup luksUUID "$rootpart")

# Freeze discovery to deterministically reproduce a UUID change not yet seen by
# udev. Changing only the UUID keeps the mounted test filesystem readable.
udevadm control --stop-exec-queue
paused=true
new_uuid=$(cat /proc/sys/kernel/random/uuid)
cryptsetup luksUUID --batch-mode --uuid "$new_uuid" "$rootpart"
nixos-generate-config --root "$work/target" --show-hardware-config >"$work/hardware.nix"
generated_device() {
  HARDWARE_FILE="$work/hardware.nix" nix-instantiate --eval --strict --json --expr '
    (import (builtins.getEnv "HARDWARE_FILE") {
      config = {}; lib = {}; pkgs = {}; modulesPath = "";
    }).boot.initrd.luks.devices.cryptroot.device' | jq -r .
}
[[ $(generated_device) == "/dev/disk/by-uuid/$old_uuid" ]] || fail 'Stale UUID reproduction did not trigger.'
printf 'REPRODUCED: hardware generation selected the stale LUKS UUID.\n'

# Release queued discovery only when production asks for it. Without the refresh,
# generation must still see the old identity rather than passing by timing.
udevadm() {
  if [[ $1 == trigger ]]; then
    command udevadm control --start-exec-queue
    paused=false
  fi
  command udevadm "$@"
}
generate_hardware_config "$work/target"
[[ $(generated_device) == "/dev/disk/by-uuid/$new_uuid" ]] || fail 'Refreshed generation retained the stale LUKS UUID.'
[[ $(cryptsetup luksUUID "$rootpart") == "$new_uuid" ]] || fail 'Unexpected on-disk UUID.'
printf 'PASS: production hardware generation matches the on-disk UUID after reformatting and delayed discovery.\n'
