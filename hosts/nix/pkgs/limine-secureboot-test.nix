{ runCommand, python3, openssl, sbsigntool, limine }:

runCommand "limine-secureboot-verification" {
  nativeBuildInputs = [ python3 openssl sbsigntool limine ];
} ''
  umask 077
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  cd "$work"
  printf 'timeout: no\n' > limine.conf
  cp ${limine}/share/limine/BOOTX64.EFI enrolled.efi
  chmod u+w enrolled.efi
  digest=$(b2sum limine.conf)
  limine enroll-config enrolled.efi "''${digest%% *}"
  openssl req -new -x509 -newkey rsa:2048 -sha256 -nodes \
    -subj '/CN=Disposable Limine signing test/' -days 1 \
    -keyout db.key -out db.pem

  verify() {
    python3 ${./verify-limine-secureboot.py} "$1" "$2" db.pem ${sbsigntool}/bin/sbverify
  }
  if verify limine.conf enrolled.efi; then
    echo 'Accepted an unsigned bootloader' >&2
    exit 1
  fi

  sbsign --key db.key --cert db.pem --output signed.efi enrolled.efi
  verify limine.conf signed.efi

  printf 'timeout: 5\n' > changed.conf
  if verify changed.conf signed.efi; then
    echo 'Accepted a changed configuration' >&2
    exit 1
  fi

  sbsign --key db.key --cert db.pem --output unenrolled.efi \
    ${limine}/share/limine/BOOTX64.EFI
  sbverify --cert db.pem unenrolled.efi
  if verify limine.conf unenrolled.efi; then
    echo 'Accepted a signed image without config enforcement' >&2
    exit 1
  fi

  cp signed.efi tampered.efi
  digest=$(b2sum changed.conf)
  limine enroll-config tampered.efi "''${digest%% *}"
  if verify changed.conf tampered.efi; then
    echo 'Accepted an image modified after signing' >&2
    exit 1
  fi

  rm db.key
  echo 'Limine signature and config-enforcement checks passed' > "$out"
''
