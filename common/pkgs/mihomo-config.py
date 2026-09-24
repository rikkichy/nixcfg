import json
import os
from pathlib import Path
import sys

import yaml


def render(template, primary, quattro, hwid, hostname):
    config = yaml.safe_load(template)
    for name, url in (("primary", primary), ("quattro", quattro)):
        config["proxy-providers"][name]["url"] = url
        config["proxy-providers"][name]["header"]["x-hwid"] = [hwid]
        config["proxy-providers"][name]["header"]["x-device-model"] = [hostname]
    return json.dumps(config, ensure_ascii=False) + "\n"


if __name__ == "__main__":
    os.umask(0o077)
    mode, hostname, template, *inputs, destination = sys.argv[1:]
    try:
        values = [Path(path).read_text() for path in inputs]
        if mode == "legacy":
            values = ["".join(value.split()) for value in values]
        if len(values) != 3 or not all(values):
            raise ValueError("Missing input")
        result = render(Path(template).read_text(), *values, hostname)
        temporary = Path(destination + ".tmp")
        temporary.write_text(result)
        temporary.chmod(0o600)
        temporary.replace(destination)
    except Exception:
        sys.exit("Mihomo configuration rendering failed; check the three private input files")
