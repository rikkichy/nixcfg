#!/usr/bin/env python3
"""Exercise IP-list routing without TUN, Internet traffic or credentials.

Needs mihomo and Python with PyYAML. Live desktop routing requires separate
operator validation after activation.
"""
import json
from pathlib import Path
import socket
import subprocess
import tempfile
import time

import yaml


def receive(sock, size):
    data = b""
    while len(data) < size:
        part = sock.recv(size - len(data))
        assert part, data
        data += part
    return data


def connect(port):
    sock = socket.create_connection(("127.0.0.1", port), timeout=3)
    sock.sendall(b"\x05\x01\x00")
    assert receive(sock, 2) == b"\x05\x00"
    return sock


def domain_request(sock, domain, port):
    name = domain.encode()
    sock.sendall(b"\x05\x01\x00\x03" + bytes([len(name)]) + name
                 + port.to_bytes(2, "big"))
    reply = receive(sock, 4)
    size = {1: 4, 4: 16}.get(reply[3])
    if size is None:
        assert reply[3] == 3, reply
        size = receive(sock, 1)[0]
    receive(sock, size + 2)
    return reply[1]


repo = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="mihomo-routing-") as temporary:
    work = Path(temporary)
    # Synthetic addresses prevent upstream data changes affecting this check.
    # Loopback is deliberately listed to exercise the earlier LAN exclusion.
    (work / "ips.txt").write_text("192.0.2.123/32\n127.0.0.1/32\n")
    for udp_capable in (True, False):
        config = yaml.safe_load((repo / "common/dotfiles/mihomo.yaml").read_text())
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        config.update({"mixed-port": port, "external-controller": "",
                       "tun": {"enable": False}, "log-level": "debug",
                       "hosts": {"listed.test": "192.0.2.123",
                                 "unlisted.test": "127.0.0.2"}})
        # Narrow only the fixture's loopback exclusion so 127.0.0.2 can prove
        # MATCH,DIRECT without sending traffic to a public destination.
        config["rules"] = [
            rule.replace("127.0.0.0/8", "127.0.0.1/32") for rule in config["rules"]]
        config.pop("proxy-providers")
        config["rule-providers"]["refilter-ips"] = {
            "type": "file", "behavior": "ipcidr", "format": "text",
            "path": str(work / "ips.txt")}
        # Rejecting outbound proves selection without contacting any public IP.
        config["proxies"] = ([{"name": "Sink", "type": "reject"}] if udp_capable else
                             [{"name": "Sink", "type": "http", "server": "127.0.0.1", "port": 1}])
        config["proxy-groups"] = [{"name": "PROXY", "type": "select", "proxies": ["Sink"]}]
        path = work / "config.json"
        path.write_text(json.dumps(config))
        with (work / "mihomo.log").open("w+") as log:
            process = subprocess.Popen(["mihomo", "-d", str(work), "-f", str(path)],
                                       stdout=log, stderr=subprocess.STDOUT)
            try:
                for _ in range(100):
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
                # Domain-addressed mixed-proxy requests must resolve for IP matching.
                with connect(port) as client:
                    domain_request(client, "listed.test", 19312)
                # An unlisted domain reaches MATCH,DIRECT; listed loopback stays LAN.
                for destination in ("unlisted.test", "127.0.0.1"):
                    with socket.socket() as server:
                        server.settimeout(3)
                        address = "127.0.0.2" if destination == "unlisted.test" else "127.0.0.1"
                        server.bind((address, 0))
                        server.listen()
                        with connect(port) as client:
                            assert domain_request(client, destination, server.getsockname()[1]) == 0
                            client.sendall(b"direct-check")
                            peer, _ = server.accept()
                            with peer:
                                peer.settimeout(3)
                                assert receive(peer, 12) == b"direct-check"
                                peer.sendall(b"direct-ok")
                            assert receive(client, 9) == b"direct-ok"
                with connect(port) as control:
                    control.sendall(b"\x05\x03\x00\x01\x7f\x00\x00\x01\x00\x00")
                    reply = receive(control, 10)
                    assert reply[1] == 0 and reply[3] == 1, reply
                    relay = (socket.inet_ntoa(reply[4:8]), int.from_bytes(reply[8:10], "big"))
                    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
                        udp.sendto(b"\x00\x00\x00\x01" + socket.inet_aton("192.0.2.123")
                                   + (19311).to_bytes(2, "big") + b"routing-check", relay)
                        time.sleep(.5)
                log.seek(0)
                lines = log.read().splitlines()
                target = "using PROXY[Sink]" if udp_capable else "using REJECT"
                assert any("[UDP]" in line and "RuleSet(refilter-ips)" in line
                           and "192.0.2.123:19311" in line and target in line
                           for line in lines), "\n".join(lines)
                assert any("[TCP]" in line and "listed.test:19312" in line
                           and ("RuleSet(refilter-ips)" in line or "RuleSet/refilter-ips" in line)
                           and ("PROXY[Sink]" in line or "dial PROXY" in line)
                           for line in lines), "\n".join(lines)
                assert any("unlisted.test:" in line and "Match" in line
                           and "DIRECT" in line for line in lines), "\n".join(lines)
                assert any("IPCIDR(127.0.0.1/32)" in line and "DIRECT" in line
                           for line in lines), "\n".join(lines)
            finally:
                process.terminate()
                process.wait(timeout=10)
print("PASS: listed IP/domain selects proxy; unsupported UDP rejects; unlisted and LAN traffic stay direct")
