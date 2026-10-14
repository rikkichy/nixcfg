#!/usr/bin/env python3
"""Run with the pinned upstream scripts directory on PYTHONPATH."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile

selector = Path(sys.argv[1]) if len(sys.argv) > 1 else (
    Path(__file__).resolve().parents[1] / "hosts/nix/pkgs/ricing/bibata-material-select.py"
)
parts = ("manifest.hl", "index.theme", "hyprcursors", "cursors", "cursors_scalable")

with tempfile.TemporaryDirectory() as work:
    root = Path(work)
    assets, destination = root / "assets", root / "cursor"
    palette = root / "themes.json"
    palette.write_text(json.dumps({
        "Blue": {"primary": "#0000ff", "body": "#0000ff"},
        "Red": {"primary": "#ff0000", "body": "#ff0000"},
        "Classic": {"primary": "#ffffff", "body": "#ffffff"},
        "Blue-Light": {"primary": "#0000fe", "body": "#0000fe"},
    }))
    for name in ("Blue", "Red"):
        theme = assets / f"Bibata-Material-{name}"
        theme.mkdir(parents=True)
        for part in parts:
            path = theme / part
            if part.endswith((".hl", ".theme")):
                path.write_text(name)
            else:
                path.mkdir()
                (path / "left_ptr").write_text(name)
    destination.mkdir()
    (destination / "manifest.hl").write_text("generated cursor")
    (destination / "cursors").mkdir()
    (destination / "cursors/left_ptr").write_text("generated bitmap")

    def run(accent):
        return subprocess.run(
            [sys.executable, str(selector), str(assets), str(palette), accent, str(destination)],
            capture_output=True, text=True, check=False,
        )

    assert run("#0000ff").returncode == 0
    assert (destination / ".manifest.hl.before-prebuilt").read_text() == "generated cursor"
    assert (destination / ".cursors.before-prebuilt/left_ptr").read_text() == "generated bitmap"
    assert all((destination / part).resolve() == assets / "Bibata-Material-Blue" / part for part in parts)
    current = destination / ".selected"
    unchanged = current.lstat()
    assert run("#0000ff").returncode == 0
    assert current.lstat().st_ino == unchanged.st_ino
    assert run("#0000fe").returncode == 0  # Exclude the closer, uninstalled light palette.
    assert current.readlink() == assets / "Bibata-Material-Blue"
    assert run("#ff0000").returncode == 0
    assert all((destination / part).resolve() == assets / "Bibata-Material-Red" / part for part in parts)
    selected = current.readlink()
    assert run("invalid").returncode != 0
    assert current.readlink() == selected
    (assets / "Bibata-Material-Blue/manifest.hl").unlink()
    assert run("#0000ff").returncode != 0
    assert current.readlink() == selected

print("PASS: cursor selection preserves assets, switches both formats, reuses state and rejects invalid input")
