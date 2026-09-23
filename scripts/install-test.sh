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
    {"name":"/dev/sdi1","type":"part","fstype":"btrfs","maj:min":"8:129"}]}
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
jq -e '[.[] | select(.reason == "") | .name] == ["/dev/sda", "/dev/sdh"]' <<<"$result" >/dev/null || fail 'An in-use disk was offered or an unmounted Btrfs target excluded.'

require_exact 'ERASE /dev/sda' <<<'ERASE /dev/sda' 2>/dev/null || fail 'Exact target confirmation rejected.'
for answer in yes YES /dev/sda 'ERASE /dev/sdb' 'ERASE /dev/sda ' ' ERASE /dev/sda'; do
  if require_exact 'ERASE /dev/sda' <<<"$answer" 2>/dev/null; then fail 'Inexact target confirmation accepted.'; fi
done
if require_exact 'ERASE /dev/sda' </dev/null 2>/dev/null; then fail 'EOF confirmed erase.'; fi

losetup() { printf '{"loopdevices":[{"back-file":"/nonexistent-live-backing-file"}]}\n'; }
if scan_disks >/dev/null 2>&1; then fail 'Unresolvable live loop backing was accepted.'; fi
findmnt() { return 1; }
if scan_disks >/dev/null 2>&1; then fail 'Usage collection failure did not fail closed.'; fi
printf 'PASS: mounted/live, mapper, swap-file, loop-backing, source, read-only and multi-device exclusions; exact confirmation and fail-closed discovery.\n'
printf 'Mocks prove safety decisions only, NOT actual disk topology, installation, boot, or token/PAM authentication.\n'
