#!/usr/bin/env python3
"""Guided setup for this repository's installed NixOS/Limine desktop."""
import argparse
from contextlib import ExitStack
import fcntl
import os
from pathlib import Path
import re
import signal
import stat
import struct
import subprocess
import sys
import tempfile
import uuid

import yaml

EFI = Path('/sys/firmware/efi/efivars')
STATE = Path('/var/lib/sbctl')
BACKUP = STATE / 'before-enrollment'
IMAGE = Path('/boot/efi/limine/BOOTX64.EFI')
CONFIG = Path('/boot/limine/limine.conf')
X509 = uuid.UUID('a5c059a1-94e4-4aa7-87b5-ab155c2bf072').bytes_le
SHA256 = uuid.UUID('c1c41626-504c-4092-aca9-41f936934328').bytes_le


def run(*args, capture=False):
    return subprocess.run([str(arg) for arg in args], check=True,
                          stdout=subprocess.PIPE if capture else None).stdout


def confirm(message):
    if input(message + ' [y/N]: ').strip().lower() not in ('y', 'yes'):
        print('Stopped. Rerun the same command to resume; nothing is reset.')
        raise SystemExit(0)


def variable(name, directory=None):
    paths = [p for p in (directory or EFI).glob(name + '-*') if not p.name.endswith('.esl')]
    if len(paths) > 1:
        raise RuntimeError('Ambiguous EFI variable: ' + name)
    return paths[0] if paths else None


def value(name, directory=None):
    path = variable(name, directory)
    if path is None:
        return b''
    data = path.read_bytes()
    if len(data) < 4:
        raise RuntimeError('Truncated EFI variable: ' + name)
    return data[4:]


def entries(data):
    """Compare ESL entries independently of list order, retaining owner GUIDs."""
    result = set()
    offset = 0
    while offset < len(data):
        if len(data) - offset < 28:
            raise RuntimeError('Truncated EFI signature list')
        kind = data[offset:offset + 16]
        size, header, width = struct.unpack_from('<III', data, offset + 16)
        if size < 28 + header or width < 16 or offset + size > len(data) or (size - 28 - header) % width:
            raise RuntimeError('Malformed EFI signature list')
        for start in range(offset + 28 + header, offset + size, width):
            result.add((kind, data[start:start + 16], data[start + 16:start + width]))
        offset += size
    return result


def root_owned(path, private=False):
    for item in (path, *path.parents):
        if not item.exists() and not item.is_symlink():
            continue
        info = item.lstat()
        if stat.S_ISLNK(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o022:
            raise RuntimeError('Unsafe ownership, permissions or symlink: ' + str(item))
    if private and path.stat().st_mode & 0o077:
        raise RuntimeError('Private key is accessible to other users: ' + str(path))


def certificate(name):
    return run('openssl', 'x509', '-in', STATE / 'keys' / name / (name + '.pem'),
               '-outform', 'DER', capture=True)


def local_key_present(name):
    cert = certificate(name)
    return any(kind == X509 and data == cert for kind, owner, data in entries(value(name)))


def check_keys():
    for name in ('PK', 'KEK', 'db'):
        key = STATE / 'keys' / name / (name + '.key')
        cert = key.with_suffix('.pem')
        if not key.is_file() or not cert.is_file():
            raise RuntimeError('Incomplete key set: restore existing keys; do not regenerate them')
        root_owned(key, private=True)
        root_owned(cert)
        public = run('openssl', 'pkey', '-in', key, '-pubout', capture=True)
        if public != run('openssl', 'x509', '-in', cert, '-pubkey', '-noout', capture=True):
            raise RuntimeError(name + ': private key and certificate do not match')


def verify_boot():
    run(sys.executable, os.environ['NIXCFG_LIMINE_VERIFIER'], CONFIG, IMAGE,
        STATE / 'keys/db/db.pem', 'sbverify')


def backup():
    root_owned(BACKUP)
    directory = BACKUP if BACKUP.exists() else EFI
    if not all(variable(name, directory) is not None for name in ('KEK', 'db')):
        raise RuntimeError('Missing original KEK/db snapshot; review vendor trust before setup')
    if BACKUP.exists():
        if not (BACKUP / 'BOOTX64.EFI').is_file() or not (BACKUP / 'limine.conf').is_file():
            raise RuntimeError('Incomplete existing backup; inspect it instead of replacing it')
        print('Preserving existing backup: ' + str(BACKUP))
        return
    with tempfile.TemporaryDirectory(prefix='.secureboot-backup-', dir=STATE) as temporary:
        destination = Path(temporary)
        databases = ('PK', 'KEK', 'db', 'dbx', 'dbt', 'dbr', 'PKDefault', 'KEKDefault', 'dbDefault', 'dbxDefault')
        for name in (*databases, 'SecureBoot', 'SetupMode'):
            source = variable(name)
            if source is not None:
                raw = source.read_bytes()
                (destination / source.name).write_bytes(raw)
                if name in databases:
                    entries(raw[4:])
                    (destination / (source.name + '.esl')).write_bytes(raw[4:])
        for source in (IMAGE, CONFIG):
            (destination / source.name).write_bytes(source.read_bytes())
        for path in destination.iterdir():
            path.chmod(0o600)
            with path.open('rb') as file:
                os.fsync(file.fileno())
        destination.rename(BACKUP)
    print('Saved public firmware databases and boot files: ' + str(BACKUP))


def check_preserved(original):
    for name, expected in original.items():
        if not expected.issubset(entries(value(name))):
            raise RuntimeError(name + ': original trust entries were lost; stop and inspect')


def restore_dbx():
    if value('dbx'):
        entries(value('dbx'))
        return
    if value('SetupMode') != b'\x01' or value('PK') or value('SecureBoot') != b'\x00':
        raise RuntimeError('Restoring dbx requires Setup Mode, no PK, and Secure Boot disabled')
    factory = value('dbxDefault')
    revocations = entries(factory)
    # ponytail: restore SHA-256 factory lists only; add certificate-revocation checks before accepting other types.
    if not revocations or any(kind != SHA256 or len(data) != 32 for kind, owner, data in revocations):
        raise RuntimeError('Missing or unsupported factory dbx; review revocations manually')
    if factory != value('dbxDefault', BACKUP):
        raise RuntimeError('Factory dbx changed since backup; review before restoring')
    revoked = {data.hex() for kind, owner, data in revocations}
    output = run('pesign', '--hash', '--digest-type', 'sha256', '--in', IMAGE, capture=True).decode()
    digests = re.findall(r'\b[0-9a-fA-F]{64}\b', output)
    if len(digests) != 1 or digests[0].lower() in revoked:
        raise RuntimeError('Limine Authenticode digest is unavailable or revoked')
    log = yaml.safe_load(run('tpm2_eventlog', '/sys/kernel/security/tpm0/binary_bios_measurements', capture=True))
    checked = 0
    for event in log['events']:
        if event.get('EventType') not in ('EV_EFI_BOOT_SERVICES_APPLICATION', 'EV_EFI_BOOT_SERVICES_DRIVER', 'EV_EFI_RUNTIME_SERVICES_DRIVER'):
            continue
        for digest in event['Digests']:
            if digest['AlgorithmId'] == 'sha256':
                checked += 1
                if digest['Digest'].lower() in revoked:
                    raise RuntimeError('A measured EFI image is revoked by the factory dbx')
    if not checked:
        raise RuntimeError('No measured EFI image hashes available; review dbx manually')
    confirm(f'Restore missing dbx with {len(revocations)} checked factory revocations (not necessarily the latest updates)?')
    with tempfile.TemporaryDirectory(prefix='nixcfg-dbx-', dir='/run') as temporary:
        esl = Path(temporary) / 'dbx.esl'
        esl.write_bytes(factory)
        run('efi-updatevar', '-e', '-f', esl, 'dbx')
    if value('dbx') != factory:
        raise RuntimeError('dbx write verification failed; do not retry blindly')


def enroll():
    if value('SetupMode') != b'\x01' or value('PK') or value('SecureBoot') != b'\x00':
        raise RuntimeError('Enrollment requires Setup Mode, no PK, and Secure Boot disabled')
    original = {name: entries(value(name, BACKUP)) for name in ('KEK', 'db')}
    check_preserved(original)
    before = {name: entries(value(name)) for name in ('KEK', 'db')}
    dbx = value('dbx')
    if not dbx:
        raise RuntimeError('Revocation database is missing')
    locked = []
    for name in ('KEK', 'db'):
        path = variable(name)
        if path is not None and 'i' in run('lsattr', '-d', path, capture=True).decode().split()[0]:
            locked.append(path)
    unlock = ', '.join(path.name.split('-')[0] for path in locked) or 'none'
    confirm(f'Enroll local keys, appending Microsoft/OEM trust; temporarily unlock immutable variables: {unlock}?')
    with ExitStack() as restore:
        for path in locked:
            run('chattr', '-i', path)
            restore.callback(run, 'chattr', '+i', path)
        run('sbctl', 'enroll-keys', '--append', '--microsoft', '--firmware-builtin=db,KEK')
    check_preserved(before)
    if value('dbx') != dbx or value('SetupMode') != b'\x00' or not all(local_key_present(name) for name in ('PK', 'KEK', 'db')):
        raise RuntimeError('Enrollment verification failed; inspect firmware databases before proceeding')
    for path in locked:
        if 'i' not in run('lsattr', '-d', path, capture=True).decode().split()[0]:
            raise RuntimeError('Immutable flag was not restored: ' + str(path))


def activate(repo):
    confirm('Activate the reviewed checkout with nh os switch and update signed EFI boot files?')
    run('nh', 'os', 'switch', '--bypass-root-check', '--no-nom', '--hostname', 'nix',
        'path:' + str(repo))
    verify_boot()


def firmware_step(enrolled):
    if enrolled:
        print('Keys are enrolled. In BIOS: keep Custom mode, enable Secure Boot, and select Maximum Security / Deny Execute. Do not restore factory keys.')
    else:
        print('Signed Limine is ready. In BIOS: remove ONLY PK to enter Setup Mode, retaining KEK/db/dbx. Keep Secure Boot disabled.')
        print('MSI: Reset To Setup Mode deletes ALL keys. If no explicit PK-only action exists, stop rather than using it.')
        print('Keep a working recovery ISO/console, LUKS passphrase and encrypted offline key backup before changing firmware.')
    print('No reboot was performed. Rerun this command after the BIOS step. Recovery: disable enforcement without deleting keys.')


def main():
    parser = argparse.ArgumentParser(prog='nixcfg-secureboot-setup', description=__doc__, epilog='Uses native sbctl. No key rotation, automatic PK deletion, firmware enforcement toggle or reboot. Rerun after each BIOS step.')
    parser.add_argument('--status', action='store_true', help='read-only status and installed Limine verification')
    parser.add_argument('repository', nargs='?', default='/etc/nixos', help='reviewed checkout (default: /etc/nixos)')
    args = parser.parse_args()
    if os.geteuid() != 0 or not Path('/etc/NIXOS').exists() or not EFI.is_dir():
        raise RuntimeError('Run on the installed NixOS desktop in UEFI mode with sudo')
    run('sbctl', 'status')
    if args.status:
        if (STATE / 'keys/db/db.pem').is_file():
            verify_boot()
        return
    if os.uname().nodename != 'nix':
        raise RuntimeError('This helper activates the repository desktop host nix, not other hosts')
    if Path('/etc/sbctl/sbctl.conf').exists():
        raise RuntimeError('Custom sbctl configuration requires separate review; this helper uses the standard key paths')
    if not sys.stdin.isatty():
        raise RuntimeError('Interactive terminal required; use --status for read-only checks')
    if not IMAGE.is_file() or not CONFIG.is_file():
        raise RuntimeError('Expected the installed x86_64 Limine boot files under /boot')
    repo = Path(args.repository).resolve(strict=True)
    root_owned(STATE)
    if repo.is_relative_to(STATE) or STATE.is_relative_to(repo):
        raise RuntimeError('The checkout must not contain or reside in the private signing directory')
    if not (repo / '.git').exists() or not (repo / 'flake.nix').is_file() or not (repo / 'hosts/nix/boot.nix').is_file():
        raise RuntimeError('Expected a reviewed Git checkout of this repository, not an arbitrary directory')
    enabled = run('nix', 'eval', '--json', 'path:' + str(repo) + '#nixosConfigurations.nix.config.boot.loader.limine.secureBoot.enable', capture=True)
    if enabled.strip() != b'true':
        raise RuntimeError('This checkout must enable native Limine Secure Boot for host nix')
    if not (STATE / 'keys').exists():
        if STATE.exists() and any(STATE.iterdir()):
            raise RuntimeError('sbctl state exists without keys; restore it instead of creating a new identity')
        confirm('Create local PK/KEK/db signing keys under root-only /var/lib/sbctl?')
        STATE.mkdir(mode=0o700, exist_ok=True)
        run('sbctl', 'create-keys')
        STATE.chmod(0o700)
    check_keys()
    uuid.UUID((STATE / 'GUID').read_text().strip())
    backup()
    try:
        verify_boot()
    except subprocess.CalledProcessError:
        activate(repo)
    if local_key_present('PK'):
        if not all(local_key_present(name) for name in ('KEK', 'db')) or not value('dbx'):
            raise RuntimeError('Local PK is enrolled but trust/revocations are incomplete; inspect before further writes')
        if value('SecureBoot') == b'\x01':
            print('Secure Boot is enabled; local keys and installed Limine verified. Still confirm MSI Maximum Security / Deny Execute in BIOS.')
        else:
            firmware_step(True)
        return
    if value('SetupMode') != b'\x01':
        firmware_step(False)
        return
    confirm('Confirm a working recovery ISO/console, LUKS passphrase, and a protected offline backup of /var/lib/sbctl before firmware writes?')
    restore_dbx()
    enroll()
    firmware_step(True)


if __name__ == '__main__':
    try:
        os.umask(0o077)
        for sig in (signal.SIGTERM, signal.SIGHUP):
            signal.signal(sig, lambda signum, frame: sys.exit(128 + signum))
        # One enrollment session at a time; --status/--help do not create files.
        if '--status' in sys.argv or '--help' in sys.argv or '-h' in sys.argv:
            main()
        else:
            with open('/run/nixcfg-secureboot.lock', 'w') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                main()
    except (OSError, RuntimeError, subprocess.CalledProcessError, EOFError, KeyboardInterrupt) as error:
        print(f'ERROR: {error}\nStopped. Inspect any completed writes before retrying; keys were not reset or rotated.', file=sys.stderr)
        sys.exit(1)
