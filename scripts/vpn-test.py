#!/usr/bin/env python3
"""Exercise vpn/vpnp against isolated Mihomo; needs nix, mihomo, bash, curl, jq, PyYAML."""
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import socketserver
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request

import yaml


class HealthProxy(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.settimeout(3)
        with self.request.makefile("rb") as stream:
            version, count = stream.read(2)
            assert version == 5
            stream.read(count)
            self.request.sendall(b"\x05\x00")
            version, command, _, kind = stream.read(4)
            assert version == 5 and command == 1
            stream.read(stream.read(1)[0] if kind == 3 else {1: 4, 4: 16}[kind])
            stream.read(2)
            self.request.sendall(b"\x05\x00\x00\x01\x7f\x00\x00\x01\x00\x00")
            while line := stream.readline():
                if line == b"\r\n":
                    break
            time.sleep(.02)  # Keep a successful loopback measurement above zero ms.
            self.request.sendall(
                f"HTTP/1.1 {self.server.status} Result\r\n"
                "Content-Length: 0\r\nConnection: close\r\n\r\n".encode())


repo = Path(__file__).resolve().parent.parent
expression = f"""let
  vpn = import {repo}/common/pkgs/vpn.nix {{
    writeShellApplication = x: x;
    curl = null; jq = null; libnotify = null; gnugrep = null; gnused = null; coreutils = null;
  }};
  menu = import {repo}/hosts/nix/modules/home/fuzzel.nix {{
    config = {{}}; pkgs.writeShellApplication = x: x;
    lib = (builtins.getFlake "path:{repo}").inputs.nixpkgs.lib // {{ mkAfter = x: x; }};
    inputs = {{}}; nixcfgPath = "{repo}";
  }};
in {{ vpn = vpn.text;
  vpnp = (builtins.head (builtins.filter (x: x.name == "vpnp") menu.home.packages)).text;
}}"""
scripts = json.loads(subprocess.check_output(
    ["nix", "eval", "--impure", "--json", "--expr", expression], text=True))
bash = shutil.which("bash")
mihomo = shutil.which("mihomo")
assert bash and mihomo, "bash and mihomo must be on PATH"

with tempfile.TemporaryDirectory(prefix="vpn-test-") as temporary:
    work = Path(temporary)
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    api = f"http://127.0.0.1:{port}"
    token = secrets.token_urlsafe(32)
    api_header = work / "api.header"
    api_header.write_text(f"Authorization: Bearer {token}\n")
    api_header.chmod(0o400)
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def get(group):
        request = urllib.request.Request(f"{api}/proxies/{group}",
                                         headers={"Authorization": f"Bearer {token}"})
        with opener.open(request, timeout=1) as response:
            return json.load(response)

    config = yaml.safe_load((repo / "common/dotfiles/mihomo.yaml").read_text())
    config.update({"mixed-port": 0, "external-controller": f"127.0.0.1:{port}", "secret": token,
                   "tun": {"enable": False}, "dns": {"enable": False},
                   "rules": ["MATCH,DIRECT"]})
    names = {"primary": ["First", '-edge [.*] / "quoted" '], "quattro": ["Other", "Other 2"]}
    servers = []
    for status in (204, 503):
        server = socketserver.ThreadingTCPServer(("127.0.0.1", 0), HealthProxy)
        server.status = status
        server.daemon_threads = True
        threading.Thread(target=server.serve_forever, daemon=True).start()
        servers.append(server)
    test_url = "http://health.invalid/generate_204"
    for provider, nodes in names.items():
        path = work / f"{provider}.json"
        path.write_text(json.dumps({"proxies": [
            {"name": name, "type": "socks5", "server": "127.0.0.1",
             "port": servers[index].server_address[1]}
            for index, name in enumerate(nodes)]}))
        health = config["proxy-providers"][provider]["health-check"]
        config["proxy-providers"][provider] = {"type": "file", "path": str(path),
            "health-check": {**health, "url": test_url}}
    (work / "config.json").write_text(json.dumps(config))
    for name, text in scripts.items():
        path = work / name
        path.write_text(f"#!{bash}\nset -euo pipefail\n" + text.replace(
            "api=http://127.0.0.1:9090", f"api={api}").replace(
                "/run/mihomo-api.header", str(api_header)))
        path.chmod(0o700)
    for name, text in {
        "notify-send": "exit 0\n",
        "desktop-picker": '''
index=0
if [ -f "$MENU.count" ]; then read -r index < "$MENU.count"; fi
cat > "$MENU.$index"
mapfile -t choices <<< "$CHOICES"
printf '%s\\n' "$((index + 1))" > "$MENU.count"
choice=${choices[index]:-CANCEL}
[ "$choice" != CANCEL ] || exit 1
printf '%s\\n' "$choice"
''',
    }.items():
        path = work / name
        path.write_text(f"#!{bash}\nset -euo pipefail\n" + text)
        path.chmod(0o700)
    env = {**os.environ, "PATH": f"{work}:{os.environ['PATH']}",
           "MENU": str(work / "menu"), "HOME": str(work)}

    def run(command, *arguments, choices=(), check=True):
        (work / "menu.count").unlink(missing_ok=True)
        return subprocess.run([str(work / command), *arguments],
                              env={**env, "CHOICES": "\n".join(
                                  "CANCEL" if choice is None else choice for choice in choices)},
                              check=check, capture_output=True, text=True)

    with (work / "mihomo.log").open("w+") as log:
        process = subprocess.Popen([mihomo, "-d", str(work), "-f", str(work / "config.json")],
                                   stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 10
            while True:
                try:
                    get("PROXY")
                    break
                except (urllib.error.URLError, TimeoutError):
                    if process.poll() is not None or time.monotonic() > deadline:
                        log.seek(0)
                        raise AssertionError(log.read())
                    time.sleep(0.05)
            try:
                opener.open(f"{api}/proxies/PROXY", timeout=1)
                raise AssertionError("Controller accepted an unauthenticated request")
            except urllib.error.HTTPError as error:
                assert error.code == 401
            request = urllib.request.Request(
                f"{api}/configs", method="OPTIONS",
                headers={"Origin": "https://untrusted.invalid",
                         "Access-Control-Request-Method": "PATCH",
                         "Access-Control-Request-Private-Network": "true"})
            with opener.open(request, timeout=1) as response:
                assert response.headers.get("Access-Control-Allow-Origin") is None
                assert response.headers.get("Access-Control-Allow-Private-Network") != "true"
            request = urllib.request.Request(f"{api}/providers/proxies/primary",
                headers={"Authorization": f"Bearer {token}"})
            deadline = time.monotonic() + 5
            while True:
                with opener.open(request, timeout=1) as response:
                    nodes = json.load(response)["proxies"]
                if all(node["extra"].get(test_url, {}).get("history") for node in nodes):
                    break
                assert time.monotonic() < deadline, "Health checks did not complete"
                time.sleep(.02)
            rows = run("vpn", "nodes").stdout.splitlines()
            delay, name = rows[0].split("\t", 1)
            assert name == "First" and int(delay) > 0
            assert rows[1] == f"0\t{names['primary'][1]}"

            run("vpnp", choices=("1", "1"))
            assert get("PRIMARY")["now"] == names["primary"][1]

            # Subscription changes retain each provider's manual server.
            run("vpnp", choices=("0", "1"))
            assert get("PROXY")["now"] == "QUATTRO"
            run("vpnp", choices=("1", "1"))
            assert get("QUATTRO")["now"] == "Other 2"
            assert get("PRIMARY")["now"] == names["primary"][1]
            run("vpnp", choices=("0", "0"))
            assert get("PROXY")["now"] == "PRIMARY"
            assert run("vpn").stdout.rstrip("\n") == names["primary"][1]

            # Invalid indexes and dismissal at either level cannot change selection.
            for choice in ("-1", "01", "3", "9" * 100, "1 + 1", "", None):
                for prefix in ((), ("0",), ("1",)):
                    run("vpnp", choices=(*prefix, choice))
                    assert get("PROXY")["now"] == "PRIMARY"
                    assert get("PRIMARY")["now"] == names["primary"][1]
                    assert get("QUATTRO")["now"] == "Other 2"
            run("vpnp", choices=("1", "2"))
            assert get("PRIMARY")["now"] == names["primary"][1]
            for command in ("on", "off", "toggle", "auto"):
                assert run("vpn", command, check=False).returncode == 2
            assert run("vpn", "select", "not a server", check=False).returncode != 0
            assert get("PROXY")["now"] == "PRIMARY"
            assert get("PRIMARY")["now"] == names["primary"][1]
        finally:
            process.terminate()
            process.wait(timeout=5)
            for server in servers:
                server.shutdown()

print("PASS: authenticated picker, HTTP-status-aware ranking, exact selection and dismissal boundaries.")
