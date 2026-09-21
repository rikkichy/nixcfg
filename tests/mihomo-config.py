"""Run with Python containing PyYAML; all private-looking inputs are dummy data."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as directory:
    directory = Path(directory)
    inputs = [directory / name for name in ("primary", "quattro", "hwid")]
    values = ['https://example.invalid/a?x="\\&|#\nnext', "https://example.invalid/'two", ' device:"\\\n ']
    for path, value in zip(inputs, values):
        path.write_text(value)
    output = directory / "config.yaml"
    command = [sys.executable, str(root / "pkgs/mihomo-config.py"), "sops",
               str(root / "dotfiles/mihomo.yaml"), *map(str, inputs), str(output)]
    subprocess.run(command, check=True)
    config = json.loads(output.read_text())
    assert config["proxy-providers"]["primary"]["url"] == values[0]
    assert config["proxy-providers"]["quattro"]["url"] == values[1]
    for provider in config["proxy-providers"].values():
        assert provider["header"]["x-hwid"] == [values[2]]
        assert provider["proxy"] == "DIRECT"
    assert output.stat().st_mode & 0o777 == 0o600
    before = output.read_bytes()
    inputs[0].write_text("")
    failed = subprocess.run(command, capture_output=True, text=True)
    assert failed.returncode != 0 and output.read_bytes() == before
    assert values[1] not in failed.stderr
    inputs[0].write_text("https://example.invalid/changed")
    subprocess.run(command, check=True)
    assert json.loads(output.read_text())["proxy-providers"]["primary"]["url"].endswith("/changed")
    command[2] = "legacy"
    subprocess.run(command, check=True)
    assert json.loads(output.read_text())["proxy-providers"]["primary"]["header"]["x-hwid"] == ["".join(values[2].split())]
print("PASS: escaping, exact SOPS values, legacy framing, private mode, failed render, refresh")
