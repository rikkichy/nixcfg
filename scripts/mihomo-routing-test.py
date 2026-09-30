#!/usr/bin/env python3
"""Exercise real Mihomo process lookup without TUN or production credentials.

Needs mihomo and Python with PyYAML. Same-user check; service privileges and
live desktop TUN routing require separate operator validation after activation.
"""
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import time

import yaml


CLIENT = """
import socket, sys, time
with socket.create_connection(('127.0.0.1', int(sys.argv[1]))) as control:
    control.sendall(b'\\x05\\x01\\x00')
    assert control.recv(2) == b'\\x05\\x00'
    control.sendall(b'\\x05\\x03\\x00\\x01\\x7f\\x00\\x00\\x01\\x00\\x00')
    reply = control.recv(64)
    assert reply[1] == 0 and reply[3] == 1, reply
    relay = (socket.inet_ntoa(reply[4:8]), int.from_bytes(reply[8:10], 'big'))
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
        udp.sendto(b'\\x00\\x00\\x00\\x01' + socket.inet_aton('192.0.2.123')
                   + (19311).to_bytes(2, 'big') + b'voice-routing-check', relay)
        time.sleep(1)
"""

repo = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="mihomo-process-") as temporary:
    work = Path(temporary)
    # /proc/<pid>/exe follows symlinks; a copy exercises the actual basename.
    discord = work / ".Discord-wrapped"
    shutil.copy2(os.readlink("/proc/self/exe"), discord)
    env = dict(os.environ, PYTHONHOME=sys.prefix)
    for udp_capable in (True, False):
        config = yaml.safe_load((repo / "common/dotfiles/mihomo.yaml").read_text())
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        config.update({"mixed-port": port, "external-controller": "",
                       "tun": {"enable": False}, "sniffer": {"enable": False},
                       "geo-auto-update": False, "log-level": "debug"})
        config.pop("proxy-providers")
        # A rejecting UDP-capable outbound proves selection without sending
        # packets outside this isolated instance. HTTP proves fallback rejection.
        config["proxies"] = ([{"name": "Sink", "type": "reject"}] if udp_capable else
                             [{"name": "Sink", "type": "http", "server": "127.0.0.1", "port": 1}])
        config["proxy-groups"] = [{"name": "PROXY", "type": "select", "proxies": ["Sink"]}]
        path = work / "config.json"
        path.write_text(json.dumps(config))
        with (work / "mihomo.log").open("w+") as log:
            process = subprocess.Popen(["mihomo", "-d", str(work), "-f", str(path)],
                                       stdout=log, stderr=subprocess.STDOUT)
            try:
                for _ in range(1200):
                    if process.poll() is not None:
                        log.seek(0)
                        raise AssertionError(log.read())
                    try:
                        with socket.create_connection(("127.0.0.1", port), timeout=.1):
                            break
                    except OSError:
                        time.sleep(.1)
                else:
                    raise AssertionError("Mihomo startup timed out")
                subprocess.run([str(discord), "-c", CLIENT, str(port)], env=env,
                               check=True, timeout=10)
                log.seek(0)
                lines = log.read().splitlines()
                target = "using PROXY[Sink]" if udp_capable else "using REJECT"
                assert any("[UDP]" in line and "ProcessName(.Discord-wrapped)" in line
                           and "192.0.2.123:19311" in line and target in line
                           for line in lines), "\n".join(lines)
            finally:
                process.terminate()
                process.wait(timeout=10)
print("PASS: native Discord identity selects proxy for an unlisted voice IP; TCP-only proxy fails closed")
