#!/usr/bin/env python3
"""Select prebuilt cursor assets behind the existing writable theme name."""

import argparse
import fcntl
import json
import os
from pathlib import Path
import sys
import tempfile

from color_match import find_closest_theme


PARTS = ("manifest.hl", "index.theme", "hyprcursors", "cursors", "cursors_scalable")


def select(assets: Path, palette: Path, accent: str, destination: Path) -> str:
    themes = {
        name: colors
        for name, colors in json.loads(palette.read_text()).items()
        if name != "Classic" and not name.endswith("-Light")
    }
    if not themes:
        raise ValueError("no dark Material Bibata palettes")
    name, _ = find_closest_theme(accent, themes)
    theme = assets.resolve() / f"Bibata-Material-{name}"
    for part in PARTS:
        path = theme / part
        valid = path.is_file() if part.endswith((".hl", ".theme")) else path.is_dir()
        if not valid:
            raise ValueError(f"incomplete cursor theme: {path}")
    if destination.is_symlink():
        raise ValueError(f"cursor selector must be a writable directory: {destination}")
    destination.mkdir(parents=True, exist_ok=True)
    with (destination / ".render.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        current = destination / ".selected"
        if current.exists() and not current.is_symlink():
            raise ValueError(f"refusing to replace non-symlink: {current}")
        changes = []
        for part in PARTS:
            path = destination / part
            target = Path(".selected") / part
            if path.is_symlink() and os.readlink(path) == str(target):
                continue
            backup = destination / f".{part}.before-prebuilt"
            if (path.exists() or path.is_symlink()) and (backup.exists() or backup.is_symlink()):
                raise ValueError(f"refusing to overwrite cursor backup: {backup}")
            changes.append((path, target, backup))
        if not changes and current.is_symlink() and os.readlink(current) == str(theme):
            return name
        with tempfile.TemporaryDirectory(prefix=".select-", dir=destination) as work:
            for path, target, backup in changes:
                if path.exists() or path.is_symlink():
                    path.rename(backup)
                link = Path(work) / path.name
                link.symlink_to(target)
                link.replace(path)
            link = Path(work) / "selected"
            link.symlink_to(theme)
            link.replace(current)
    return name


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("assets", type=Path)
    parser.add_argument("palette", type=Path)
    parser.add_argument("accent")
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    try:
        select(args.assets, args.palette, args.accent, args.destination)
    except (OSError, ValueError, KeyError) as error:
        print(f"bibata-material-select: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
