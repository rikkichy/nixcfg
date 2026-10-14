#!/usr/bin/env python3
"""Run with Python + PyYAML; never accesses real EFI variables or signing keys."""
import contextlib
import importlib.util
import io
from pathlib import Path
import stat
import struct
import subprocess
import tempfile
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('setup', Path(__file__).with_name('secureboot-setup.py'))
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


def esl(*payloads):
    width = 16 + len(payloads[0])
    assert all(len(payload) + 16 == width for payload in payloads)
    return setup.SHA256 + struct.pack('<III', 28 + width * len(payloads), 0, width) + b''.join(b'\x00' * 16 + payload for payload in payloads)


def rejects(function, *args):
    try:
        function(*args)
    except RuntimeError:
        return
    raise AssertionError('Unsafe input was accepted')


old, extra = b'a' * 32, b'b' * 32
assert setup.entries(esl(old, extra)) == setup.entries(esl(extra, old))
for malformed in [b'\x00', esl(old)[:-1], setup.SHA256 + struct.pack('<III', 0, 0, 0)]:
    rejects(setup.entries, malformed)

with tempfile.TemporaryDirectory(prefix='secureboot-policy-test-') as temporary:
    root = Path(temporary)
    setup.EFI = root / 'efi'
    setup.BACKUP = root / 'backup'
    setup.EFI.mkdir()
    setup.BACKUP.mkdir()

    def put(directory, name, data):
        path = directory / (name + '-test')
        path.write_bytes(b'\x07\x00\x00\x00' + data)
        return path

    put(setup.EFI, 'SetupMode', b'\x01')
    put(setup.EFI, 'SecureBoot', b'\x00')
    put(setup.EFI, 'dbx', esl(extra))
    paths = [put(setup.EFI, name, esl(old)) for name in ('KEK', 'db')]
    for name in ('KEK', 'db'):
        put(setup.BACKUP, name, esl(old))
    original = {'KEK': setup.entries(esl(old)), 'db': setup.entries(esl(old))}
    put(setup.EFI, 'db', esl(old, extra))
    setup.check_preserved(original)
    put(setup.EFI, 'db', esl(extra))
    rejects(setup.check_preserved, original)
    put(setup.EFI, 'db', esl(old))
    for path in paths:
        path.chmod(0o400)

    # Model native failure after an actual partial database write. Check filesystem
    # state, not call counts: a failure must retain the update and restore protection.
    def native(*args, capture=False):
        if args[0] == 'lsattr':
            immutable = not (Path(args[-1]).stat().st_mode & stat.S_IWUSR)
            return ('----i----' if immutable else '---------').encode() + b' variable\n'
        if args[0] == 'chattr':
            Path(args[-1]).chmod(0o400 if args[1] == '+i' else 0o600)
            return
        if args[0] == 'sbctl':
            put(setup.EFI, 'KEK', esl(old, extra))
            raise subprocess.CalledProcessError(1, 'sbctl')
        raise AssertionError('Unexpected native operation: ' + str(args))

    with patch.object(setup, 'run', native), patch('builtins.input', return_value=''):
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                setup.enroll()
        except SystemExit as stopped:
            assert stopped.code == 0
        else:
            raise AssertionError('Default approval did not stop enrollment')
    assert all(setup.value(name) == esl(old) for name in ('KEK', 'db'))
    assert all(stat.S_IMODE(path.stat().st_mode) == 0o400 for path in paths)

    with patch.object(setup, 'run', native), patch('builtins.input', return_value='yes'):
        try:
            setup.enroll()
        except subprocess.CalledProcessError:
            pass
        else:
            raise AssertionError('Native enrollment failure was hidden')
    assert setup.value('KEK') == esl(old, extra)
    assert setup.value('db') == esl(old)
    assert all(stat.S_IMODE(path.stat().st_mode) == 0o400 for path in paths)
    assert all(setup.value(name, setup.BACKUP) == esl(old) for name in ('KEK', 'db'))

print('Secure Boot policy checks passed: malformed data, trust preservation, declined writes, and interrupted enrollment')
