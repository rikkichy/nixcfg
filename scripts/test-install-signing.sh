#!/usr/bin/env bash
# Run: nix shell nixpkgs#openssl --command bash scripts/test-install-signing.sh
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/install.sh"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
umask 077
backup="$tmp/backup"
mkdir -p "$backup/keys/db" "$backup/keys/PK" "$backup/keys/KEK"
printf '12345678-1234-1234-1234-123456789abc\n' >"$backup/GUID"
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$backup/keys/db/db.key" -out "$backup/keys/db/db.pem" -days 1 -subj /CN=installer-test >/dev/null 2>&1
for key in PK KEK; do
  cp "$backup/keys/db/db.key" "$backup/keys/$key/$key.key"
  cp "$backup/keys/db/db.pem" "$backup/keys/$key/$key.pem"
done
validate_signing_state "$backup"
reject() {
  if (validate_signing_state "$backup") >"$tmp/error" 2>&1; then
    printf 'FAIL: accepted %s\n' "$1" >&2
    exit 1
  fi
}
chmod 0644 "$backup/keys/db/db.key"
reject 'publicly readable private key'
chmod 0600 "$backup/keys/db/db.key"
mv "$backup/keys/PK/PK.key" "$tmp/PK.key"
reject 'missing PK key'
mv "$tmp/PK.key" "$backup/keys/PK/PK.key"
printf 'invalid\n' >"$backup/GUID"
reject 'invalid GUID'
printf '12345678-1234-1234-1234-123456789abc\n' >"$backup/GUID"
ln -s "$backup/keys/db/db.key" "$backup/link"
reject 'symlink in backup'
rm "$backup/link"
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$tmp/other.key" -out "$tmp/other.pem" -days 1 -subj /CN=other-test >/dev/null 2>&1
cp "$backup/keys/db/db.pem" "$tmp/db.pem"
cp "$tmp/other.pem" "$backup/keys/db/db.pem"
reject 'mismatched key and certificate'
cp "$tmp/db.pem" "$backup/keys/db/db.pem"
source="$tmp/repo"
work="$tmp/work"
mkdir "$source" "$work"
prepare_signing_state <<<"$backup"
rm "$backup/keys/db/db.key"
validate_signing_state "$work/sbctl"
[[ $(stat -c %a "$work/sbctl") == 700 ]]
printf 'PASS: signing backup validation and independent pre-erase staging\n'
