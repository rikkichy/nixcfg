#!/usr/bin/env bash
# No root, real device discovery, partitioning, mount, enrollment, or Nix build.
set -euo pipefail
# shellcheck source=scripts/install.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/install.sh"

testdir=$(mktemp -d)
trap 'rm -rf -- "$testdir"' EXIT
mkdir "$testdir/source with spaces"
touch "$testdir/swap file" "$testdir/live image"
source="$testdir/source with spaces"
fixture='{"blockdevices":[
  {"name":"/dev/sda","type":"disk","size":17179869184,"ro":false,"maj:min":"8:0"},
  {"name":"/dev/sdb","type":"disk","size":17179869184,"children":[
    {"name":"/dev/sdb1","type":"part","maj:min":"8:17","mountpoints":["/iso"]}]},
  {"name":"/dev/sdc","type":"disk","size":17179869184,"children":[
    {"name":"/dev/sdc1","type":"part","maj:min":"8:33","children":[
      {"name":"/dev/mapper/busy","type":"crypt","maj:min":"253:0","mountpoints":[null]}]}]},
  {"name":"/dev/sdd","type":"disk","size":17179869184,"children":[
    {"name":"/dev/sdd1","type":"part","maj:min":"8:49","mountpoints":[null]}]},
  {"name":"/dev/sde","type":"disk","size":17179869184,"children":[
    {"name":"/dev/sde1","type":"part","maj:min":"8:65","mountpoints":[null]}]},
  {"name":"/dev/sdf","type":"disk","size":17179869184,"children":[
    {"name":"/dev/sdf1","type":"part","maj:min":"8:81","mountpoints":[null]}]},
  {"name":"/dev/sdg","type":"disk","size":17179869184,"ro":true},
  {"name":"/dev/sdh","type":"disk","size":17179869184,"children":[
    {"name":"/dev/sdh1","type":"part","fstype":"btrfs","maj:min":"8:113"}]},
  {"name":"/dev/sdi","type":"disk","size":17179869184,"children":[
    {"name":"/dev/sdi1","type":"part","fstype":"btrfs","maj:min":"8:129"}]},
  {"name":"/dev/sdj","type":"disk","size":1024209543168,"vendor":"AirDisk","model":"External SSD","tran":"usb","rm":false},
  {"name":"/dev/sdk","type":"disk","size":17179869184,"tran":"sata","rm":true},
  {"name":"/dev/sdl","type":"disk","size":17179869184,"tran":"usb","ro":true}
]}'

# Exercise the real usage collector and classifier, replacing only device APIs.
lsblk() { printf '%s\n' "$fixture"; }
mounted_btrfs_devices() { printf '8:129\n'; }
swapon() { printf '%s/swap\\x20file\n' "$testdir"; }
losetup() { jq -n --arg path "$testdir/live image" '{loopdevices:[{"back-file":$path}]}'; }
findmnt() {
  case "${*: -1}" in
    "$testdir/source with spaces") printf '8:81\n' ;;
    "$testdir/swap file") printf '8:49\n' ;;
    "$testdir/live image") printf '8:65\n' ;;
    MAJ:MIN) printf '8:17\n' ;;
    *) return 1 ;;
  esac
}

result=$(scan_disks)
jq -e '[.[] | select(.reason == "") | .name] == ["/dev/sda", "/dev/sdh", "/dev/sdj", "/dev/sdk"]' <<<"$result" >/dev/null || fail 'An in-use disk was offered or an unused disk excluded.'

disks=$result
internal=$(disk_candidates false)
jq -e 'map(.name) == ["/dev/sda", "/dev/sdh"]' <<<"$internal" >/dev/null || fail 'External media was offered by default or an internal SATA disk hidden.'
external=$(disk_candidates true)
jq -e 'map(.name) == ["/dev/sda", "/dev/sdh", "/dev/sdj", "/dev/sdk"]' <<<"$external" >/dev/null || fail 'External opt-in bypassed safety exclusions.'
select_disk <<<'1' >"$testdir/menu"
[[ $disk == /dev/sda ]] || fail 'Menu selected the wrong disk.'
[[ $(<"$testdir/menu") != *'/dev/sdj'* ]] || fail 'Default menu displayed an external target.'
select_disk <<<$'3\n3' >"$testdir/menu"
[[ $disk == /dev/sdj ]] || fail 'External opt-in could not select a USB SSD.'
[[ $(<"$testdir/menu") == *'0.93 TiB'* ]] || fail 'Disk size was not displayed in readable binary units.'

# Invalid menu input must never become a shell expression or an array index.
choose Host '' nix nixos-server <<<$'0\n999999999999999999999999\n1+1\n2' >/dev/null
[[ $choice == 2 ]] || fail 'Invalid selection was accepted.'
if (choose Host '' nix </dev/null) >/dev/null 2>&1; then fail 'EOF selected a host.'; fi
if approve Enroll <<<'' >/dev/null; then fail 'Empty approval enabled enrollment.'; fi

host=nixos-server
confirm_erase <<<$'yes\nERASE /dev/sdj\nERASE' >/dev/null
if (confirm_erase <<<'yes') >/dev/null 2>&1; then fail 'Inexact confirmation followed by EOF authorized erase.'; fi

# Enrollment approvals are independent and require no backup media.
(
  select_fido() { fido=/dev/hidraw5; }
  plan_enrollment <<<$'y\ny' >/dev/null
  [[ $sudo_enroll == true && $boot_enroll == true ]] || fail 'Approved enrollment was deferred.'
  plan_enrollment <<<$'n\ny' >/dev/null
  [[ $sudo_enroll == false && $boot_enroll == true ]] || fail 'Boot approval enabled sudo.'
  plan_enrollment <<<$'y\nn' >/dev/null
  [[ $sudo_enroll == true && $boot_enroll == false ]] || fail 'Sudo approval enabled boot.'
)

# Refuse a boot configuration whose LUKS reference differs from the real header,
# even if udev's stale symlink would still resolve to the same block device.
(
  rootpart=/dev/test-root esp=/dev/test-esp
  nixcmd=(bash -c "cat \"\$1\"" _ "$testdir/devices.json")
  cryptsetup() { printf '11111111-2222-3333-4444-555555555555\n'; }
  blkid() { printf 'ABCD-1234\n'; }
  printf '%s\n' '{"luks":{"cryptroot":"/dev/disk/by-uuid/stale"},"root":"/dev/mapper/cryptroot","esp":"/dev/disk/by-uuid/ABCD-1234"}' >"$testdir/devices.json"
  if (verify_boot_devices) >/dev/null 2>&1; then fail 'Stale LUKS UUID accepted for installation.'; fi
  jq '.luks.cryptroot = "/dev/disk/by-uuid/11111111-2222-3333-4444-555555555555"' \
    "$testdir/devices.json" >"$testdir/fresh.json"
  mv "$testdir/fresh.json" "$testdir/devices.json"
  verify_boot_devices
)

losetup() { printf '{"loopdevices":[{"back-file":"/nonexistent-live-backing-file"}]}\n'; }
if scan_disks >/dev/null 2>&1; then fail 'Unresolvable live loop backing was accepted.'; fi
findmnt() { return 1; }
if scan_disks >/dev/null 2>&1; then fail 'Usage collection failure did not fail closed.'; fi
printf 'PASS: disk-use exclusions, external opt-in, numbered menus, erase confirmation, independent enrollment approvals and fresh boot UUID validation.\n'
printf 'Mocks prove safety decisions only, NOT actual disk topology, installation, boot, or token/PAM authentication.\n'
