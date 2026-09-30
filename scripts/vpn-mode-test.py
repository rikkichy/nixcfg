#!/usr/bin/env python3
"""Check a built vpn command against isolated Mihomo, without TUN or real secrets.

Usage: python3 scripts/vpn-mode-test.py /nix/store/...-vpn/bin/vpn
Requires mihomo on PATH. All traffic stays on loopback.
"""
import json
import os
from pathlib import Path
import socket
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class Echo(socketserver.BaseRequestHandler):
    def handle(self):
        while data := self.request.recv(1024):
            self.request.sendall(data)


with tempfile.TemporaryDirectory(prefix="vpn-mode-") as temporary:
    work = Path(temporary)
    api_port, socks_port = free_port(), free_port()
    api = f"http://127.0.0.1:{api_port}"
    header = work / "api.header"
    header.write_text("Authorization: Bearer isolated-test\n")
    command = work / "vpn"
    # Redirect only the controller address and credential file, not command logic.
    command.write_text(Path(sys.argv[1]).read_text()
                       .replace("http://127.0.0.1:9090", api)
                       .replace("/run/mihomo-api.header", str(header)))
    command.chmod(0o700)
    config = work / "config.json"
    config.write_text(json.dumps({
        "mixed-port": socks_port, "external-controller": f"127.0.0.1:{api_port}",
        "secret": "isolated-test", "mode": "rule", "tun": {"enable": False},
        "proxies": [{"name": "Selected", "type": "reject"}],
        "proxy-groups": [
            {"name": "PROXY", "type": "select", "proxies": ["PRIMARY", "QUATTRO"]},
            {"name": "PRIMARY", "type": "select", "proxies": ["Selected"]},
            {"name": "QUATTRO", "type": "select", "proxies": ["Selected"]}],
        "rules": ["MATCH,DIRECT"]}))
    env = dict(os.environ, DBUS_SESSION_BUS_ADDRESS="unix:path=/nonexistent")
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def get(path):
        request = urllib.request.Request(api + path, headers={"Authorization": "Bearer isolated-test"})
        with opener.open(request, timeout=2) as response:
            return json.load(response)

    def vpn(*args, success=True):
        result = subprocess.run([str(command), *args], env=env, text=True,
                                capture_output=True, timeout=10)
        assert (result.returncode == 0) == success, result.stderr
        return result.stdout.strip()

    def connect(port):
        sock = socket.create_connection(("127.0.0.1", socks_port), timeout=2)
        sock.sendall(b"\x05\x01\x00")
        assert sock.recv(2) == b"\x05\x00"
        sock.sendall(b"\x05\x01\x00\x01\x7f\x00\x00\x01" + port.to_bytes(2, "big"))
        reply = sock.recv(10)
        if len(reply) < 2 or reply[1] != 0:
            sock.close()
            raise ConnectionError(reply)
        return sock

    with (work / "mihomo.log").open("w+") as log:
        process = subprocess.Popen(["mihomo", "-d", str(work), "-f", str(config)],
                                   stdout=log, stderr=subprocess.STDOUT)
        server = socketserver.ThreadingTCPServer(("127.0.0.1", 0), Echo)
        server.daemon_threads = True
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            for _ in range(100):
                try:
                    get("/configs")
                    break
                except OSError:
                    if process.poll() is not None:
                        log.seek(0)
                        raise AssertionError(log.read())
                    time.sleep(.05)
            else:
                raise AssertionError("Mihomo startup timed out")
            assert vpn("mode") == "scoped"
            vpn("mode", "invalid", success=False)
            vpn("mode", "global", "extra", success=False)
            assert get("/configs")["mode"] == "rule"
            with connect(server.server_address[1]) as connection:
                connection.sendall(b"before")
                assert connection.recv(6) == b"before"
                vpn("mode", "global")
                assert connection.recv(1) == b"", "Old direct flow survived the switch"
            assert vpn("mode") == "global"
            assert get("/proxies/GLOBAL")["now"] == "PROXY"
            assert get("/proxies/PROXY")["now"] == "PRIMARY"
            try:
                with connect(server.server_address[1]) as connection:
                    connection.sendall(b"blocked")
                    assert connection.recv(7) == b"", "Global bypassed the selected rejecting proxy"
            except (ConnectionError, ConnectionResetError):
                pass
            vpn("mode", "scoped")
            assert vpn("mode") == "scoped"
            with connect(server.server_address[1]) as connection:
                connection.sendall(b"restored")
                assert connection.recv(8) == b"restored"
        finally:
            process.terminate()
            process.wait(timeout=10)
            server.shutdown()
            server.server_close()
print("PASS: global uses the selected proxy and closes old flows; scoped restores direct rules; invalid modes do not change routing")
