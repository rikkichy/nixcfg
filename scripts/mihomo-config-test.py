#!/usr/bin/env python3
"""Run with the renderer's Python/PyYAML environment; no real secrets or services."""
import os
import json
from pathlib import Path
import pwd
import stat
import subprocess
import sys
import tempfile


repo = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="mihomo-render-test-") as temporary:
    work = Path(temporary)
    values = [
        'https://primary.invalid/?q="dummy"\\value\n',
        "https://quattro.invalid/?q=dummy\n",
        ' dummy-hwid\\"\nwith whitespace ',
    ]
    inputs = [work / name for name in ("primary", "quattro", "hwid")]
    for path, value in zip(inputs, values):
        path.write_text(value)
        path.chmod(0o600)
    output = work / "config.json"
    api_header = work / "api.header"
    command = [
        sys.executable, str(repo / "common/pkgs/mihomo-config.py"),
        "sops", "nixos-server", str(repo / "common/dotfiles/mihomo.yaml"),
        *(str(path) for path in inputs), str(output), str(api_header),
        pwd.getpwuid(os.getuid()).pw_name,
    ]
    subprocess.run(command, check=True, capture_output=True, text=True)
    rendered = json.loads(output.read_text())
    for name, url in zip(("primary", "quattro"), values[:2]):
        provider = rendered["proxy-providers"][name]
        assert provider["url"] == url
        assert provider["header"]["x-hwid"] == [values[2]]
        assert provider["header"]["x-device-model"] == ["nixos-server"]
    assert stat.S_IMODE(output.stat().st_mode) == 0o600
    assert stat.S_IMODE(api_header.stat().st_mode) == 0o400
    assert api_header.stat().st_uid == os.getuid()
    assert api_header.read_text() == f"Authorization: Bearer {rendered['secret']}\n"

    subprocess.run(command, check=True, capture_output=True, text=True)
    rotated = json.loads(output.read_text())
    assert rotated["secret"] != rendered["secret"]
    assert api_header.read_text() == f"Authorization: Bearer {rotated['secret']}\n"

    last_good = output.read_bytes()
    last_header = api_header.read_bytes()
    inputs[2].write_text("")
    failed = subprocess.run(command, capture_output=True, text=True)
    assert failed.returncode != 0
    assert output.read_bytes() == last_good
    assert api_header.read_bytes() == last_header
    assert all(value not in failed.stdout + failed.stderr for value in values)

print("PASS: private scalar isolation, controller token rotation/permissions, and fail-closed empty HWID.")
