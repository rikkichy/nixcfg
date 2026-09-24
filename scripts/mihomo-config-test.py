#!/usr/bin/env python3
"""Run with the renderer's Python/PyYAML environment; no real secrets or services."""
import json
from pathlib import Path
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
    command = [
        sys.executable, str(repo / "common/pkgs/mihomo-config.py"),
        "sops", "nixos-server", str(repo / "common/dotfiles/mihomo.yaml"),
        *(str(path) for path in inputs), str(output),
    ]
    subprocess.run(command, check=True, capture_output=True, text=True)
    rendered = json.loads(output.read_text())
    for name, url in zip(("primary", "quattro"), values[:2]):
        provider = rendered["proxy-providers"][name]
        assert provider["url"] == url
        assert provider["header"]["x-hwid"] == [values[2]]
        assert provider["header"]["x-device-model"] == ["nixos-server"]
    assert stat.S_IMODE(output.stat().st_mode) == 0o600

    last_good = output.read_bytes()
    inputs[2].write_text("")
    failed = subprocess.run(command, capture_output=True, text=True)
    assert failed.returncode != 0
    assert output.read_bytes() == last_good
    assert all(value not in failed.stdout + failed.stderr for value in values)

print("PASS: hostname and private scalar isolation, private output, and fail-closed empty HWID.")
