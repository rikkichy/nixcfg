import json
import os
from pathlib import Path
import pwd
import secrets
import sys
from string import Template
import tempfile

# YAML folds Unicode line separators and rejects raw C1 controls.
YAML_ESCAPES = {code: f"\\u{code:04x}" for code in (*range(0x7f, 0xa0), 0x2028, 0x2029)}


def render(template, primary, quattro, hwid, hostname, token):
    values = dict(primary=primary, quattro=quattro, hwid=hwid, hostname=hostname, token=token)
    template = Template(template)
    if set(template.get_identifiers()) != values.keys():
        raise ValueError("Missing or unknown template fields")
    return template.substitute(
        {name: json.dumps(value, ensure_ascii=False).translate(YAML_ESCAPES)
         for name, value in values.items()}
    )


def publish(path, content, permissions, uid):
    path = Path(path)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as output:
            output.write(content)
            os.fchown(output.fileno(), uid, -1)
            os.fchmod(output.fileno(), permissions)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


if __name__ == "__main__":
    os.umask(0o077)
    mode, hostname, template, *inputs, destination, api_header, api_user = sys.argv[1:]
    try:
        values = [Path(path).read_text() for path in inputs]
        if mode == "legacy":
            values = ["".join(value.split()) for value in values]
        if len(values) != 3 or not all(values):
            raise ValueError("Missing input")
        uid = pwd.getpwnam(api_user).pw_uid
        token = secrets.token_urlsafe(32)
        result = render(Path(template).read_text(), *values, hostname, token)
        publish(api_header, f"Authorization: Bearer {token}\n", 0o400, uid)
        publish(destination, result, 0o600, os.getuid())
    except Exception:
        sys.exit("Mihomo configuration rendering failed; check private inputs and runtime paths")
