{ nixpkgs ? <nixpkgs>, system ? builtins.currentSystem }:

let
  pkgs = import nixpkgs { inherit system; };
  testLib = import (nixpkgs + "/nixos/lib") { inherit (pkgs) lib; };
  clientConfig = pkgs.writeText "mihomo-test-client.yaml" ''
    mixed-port: 7890
    allow-lan: false
    external-controller: 127.0.0.1:9090
    secret: public-test-token
    mode: rule
    ipv6: false
    find-process-mode: off
    interface-name: eth1
    dns:
      enable: false
    tun:
      enable: true
      device: mihomo
      stack: gvisor
      auto-route: true
      auto-detect-interface: false
      dns-hijack: []
      route-exclude-address:
        - 198.51.100.0/24
        - 192.168.0.0/16
        - 10.0.0.0/8
    proxies:
      - name: relay
        type: socks5
        server: 198.51.100.2
        port: 1080
        username: public-test-user
        password: public-test-password
        udp: true
    proxy-groups:
      - name: PROXY
        type: select
        proxies: [relay]
    rules:
      - MATCH,PROXY
      - MATCH,REJECT
  '';
  serverConfig = pkgs.writeText "mihomo-test-server.yaml" ''
    mixed-port: 1080
    allow-lan: true
    bind-address: 198.51.100.2
    authentication:
      - public-test-user:public-test-password
    mode: rule
    rules:
      - MATCH,DIRECT
  '';
in
testLib.runTest {
  name = "mihomo-killswitch";
  hostPkgs = pkgs;

  nodes = {
    machine = { ... }: {
      imports = [ ../modules/system/mihomo-killswitch.nix ];
      networking.networkmanager.enable = true;
      networking.networkmanager.unmanaged = [ "interface-name:mihomo" "interface-name:eth1" ];
      networking.useDHCP = false;
      networking.defaultGateway = { address = "198.51.100.2"; interface = "eth1"; };
      networking.interfaces.eth1 = {
        ipv4.addresses = [ { address = "198.51.100.1"; prefixLength = 24; } ];
        ipv6.addresses = [ { address = "2001:db8::1"; prefixLength = 64; } ];
      };
      networking.firewall.trustedInterfaces = [ "mihomo" ];
      networking.firewall.checkReversePath = "loose";
      boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
      services.mihomo = {
        enable = true;
        tunMode = true;
        processesInfo = false;
        configFile = clientConfig;
      };
      # Start it explicitly so the first probes exercise a boot without a TUN.
      systemd.services.mihomo.wantedBy = pkgs.lib.mkForce [ ];
      environment.systemPackages = with pkgs; [ nftables iptables python3 util-linux ];
    };

    peer = { ... }: {
      networking.useDHCP = false;
      networking.firewall.enable = false;
      networking.interfaces.eth1 = {
        ipv4.addresses = [
          { address = "198.51.100.2"; prefixLength = 24; }
          { address = "203.0.113.2"; prefixLength = 32; }
          { address = "203.0.113.3"; prefixLength = 32; }
        ];
        ipv6.addresses = [ { address = "2001:db8::2"; prefixLength = 64; } ];
        ipv4.routes = [ { address = "10.88.0.0"; prefixLength = 24; via = "198.51.100.1"; } ];
      };
      services.mihomo = {
        enable = true;
        configFile = serverConfig;
      };
      # The fixture's UDP relay needs route discovery, not TUN capabilities.
      systemd.services.mihomo.serviceConfig.RestrictAddressFamilies =
        pkgs.lib.mkForce "AF_INET AF_INET6 AF_NETLINK";
      systemd.services.tcp-echo = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig.ExecStart = "${pkgs.socat}/bin/socat TCP4-LISTEN:8000,reuseaddr,fork EXEC:${pkgs.coreutils}/bin/cat";
      };
      systemd.services.udp-echo = {
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        serviceConfig.ExecStart = "${pkgs.socat}/bin/socat UDP4-RECVFROM:8001,bind=203.0.113.2,reuseaddr,fork EXEC:${pkgs.coreutils}/bin/cat";
      };
      systemd.services.udp-echo-alt = {
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        serviceConfig.ExecStart = "${pkgs.socat}/bin/socat UDP4-RECVFROM:8001,bind=203.0.113.3,reuseaddr,fork EXEC:${pkgs.coreutils}/bin/cat";
      };
      systemd.services.tcp6-echo = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig.ExecStart = "${pkgs.socat}/bin/socat TCP6-LISTEN:8000,ipv6only=1,reuseaddr,fork EXEC:${pkgs.coreutils}/bin/cat";
      };
      environment.systemPackages = [ pkgs.tcpdump pkgs.python3 ];
    };
  };

  testScript = ''
    import shlex
    from datetime import timedelta

    def python(code):
        return "python3 -c " + shlex.quote(code)

    def probe(address="203.0.113.2", udp=False, prefix="", ipv6=False):
        family = "AF_INET6" if ipv6 else "AF_INET"
        kind = "SOCK_DGRAM" if udp else "SOCK_STREAM"
        port = 8001 if udp else 8000
        return prefix + python(
            f"import socket; s=socket.socket(socket.{family},socket.{kind}); "
            f"s.settimeout(2); s.connect(('{address}',{port})); "
            "s.sendall(b'guard-test'); assert s.recv(64)==b'guard-test'"
        )

    start_all()
    peer.wait_for_unit("mihomo.service")
    peer.wait_for_unit("tcp-echo.service")
    peer.wait_for_unit("udp-echo.service")
    peer.wait_for_unit("udp-echo-alt.service")
    peer.wait_for_unit("tcp6-echo.service")
    machine.wait_for_unit("NetworkManager.service")
    machine.wait_for_unit("mihomo-killswitch.service")
    machine.succeed("nft list table inet mihomo_guard")
    guard_time = int(machine.succeed("systemctl show -p ActiveEnterTimestampMonotonic --value mihomo-killswitch"))
    network_time = int(machine.succeed("systemctl show -p ActiveEnterTimestampMonotonic --value NetworkManager"))
    assert 0 < guard_time <= network_time
    machine.succeed(probe("peer"))

    # The synthetic public addresses exist only on this disposable VM network.
    # Broker probes also prove a working peer; a network outage cannot pass this.
    for udp in (False, True):
        machine.succeed(probe(udp=udp, prefix="runuser -u mihomo -- "))
    peer.succeed("tcpdump -n -U -i eth1 -w /run/blocked.pcap '(dst host 203.0.113.2 or dst host 2001:db8::2) and (tcp or udp)' >/run/capture.log 2>&1 &")
    peer.wait_until_succeeds("test -s /run/blocked.pcap")
    for udp in (False, True):
        machine.fail(probe(udp=udp))
    machine.fail(probe("2001:db8::2", ipv6=True))
    machine.fail(probe("2001:db8::2", ipv6=True, prefix="runuser -u mihomo -- "))
    peer.succeed("pkill -INT tcpdump")
    peer.wait_until_fails("pgrep tcpdump")
    assert peer.succeed("tcpdump -n -r /run/blocked.pcap 2>/dev/null").strip() == ""

    # Even a pre-existing physical TCP flow loses egress on policy replacement.
    machine.succeed("nft insert rule inet mihomo_guard output ip daddr 203.0.113.2 tcp dport 8000 accept")
    flow = """
    import pathlib, socket, time
    s = socket.create_connection(('203.0.113.2', 8000), timeout=2)
    s.sendall(b'before')
    assert s.recv(64) == b'before'
    pathlib.Path('/run/flow-ready').touch()
    while not pathlib.Path('/run/flow-send').exists():
        time.sleep(0.02)
    try:
        s.sendall(b'after')
        leaked = s.recv(64) == b'after'
    except (TimeoutError, OSError):
        leaked = False
    pathlib.Path('/run/flow-leaked' if leaked else '/run/flow-blocked').touch()
    """
    machine.succeed(python(flow) + " >/run/flow.log 2>&1 &")
    machine.wait_until_succeeds("test -e /run/flow-ready")
    machine.succeed("systemctl reload mihomo-killswitch; touch /run/flow-send")
    machine.wait_until_succeeds("test -e /run/flow-blocked")
    machine.fail("test -e /run/flow-leaked")

    # Forwarding gets the same guard, independently of iptables/Docker accepts.
    machine.succeed("ip netns add container; ip link add host-veth type veth peer name guest-veth; ip link set guest-veth netns container; ip addr add 10.88.0.1/24 dev host-veth; ip link set host-veth up; ip netns exec container ip addr add 10.88.0.2/24 dev guest-veth; ip netns exec container ip link set guest-veth up; ip netns exec container ip link set lo up; ip netns exec container ip route add default via 10.88.0.1; iptables -I FORWARD -j ACCEPT")
    for udp in (False, True):
        machine.fail(probe(udp=udp, prefix="ip netns exec container "))

    machine.succeed("systemctl start mihomo")
    machine.wait_until_succeeds("ip -4 addr show dev mihomo", timeout=timedelta(seconds=30))
    for udp in (False, True):
        machine.wait_until_succeeds(probe("203.0.113.3", udp=udp), timeout=timedelta(seconds=30))
        machine.wait_until_succeeds(probe("203.0.113.3", udp=udp, prefix="ip netns exec container "), timeout=timedelta(seconds=30))
    # Force this destination onto the physical route even while the TUN is up.
    machine.succeed("ip rule add pref 1 to 203.0.113.2/32 lookup main")
    for udp in (False, True):
        machine.fail(probe(udp=udp))
        machine.fail(probe(udp=udp, prefix="ip netns exec container "))
    peer.succeed("systemctl stop mihomo")
    for udp in (False, True):
        machine.fail(probe("203.0.113.3", udp=udp))
    peer.succeed("systemctl start mihomo")
    machine.wait_until_succeeds(probe("203.0.113.3"), timeout=timedelta(seconds=30))

    # A real tunnel stop must leave the independent filter and broker exemption.
    machine.succeed("systemctl stop mihomo; nft list table inet mihomo_guard")
    machine.succeed(probe("peer"))
    for udp in (False, True):
        machine.fail(probe("203.0.113.3", udp=udp))
        machine.fail(probe("203.0.113.3", udp=udp, prefix="ip netns exec container "))
        machine.succeed(probe(udp=udp, prefix="runuser -u mihomo -- "))

    # Reload while packets race it: no intermediate empty table is observable.
    peer.succeed("tcpdump -n -U -i eth1 -w /run/reload.pcap 'src host 198.51.100.1 and dst host 203.0.113.2 and udp port 8001' >/run/capture.log 2>&1 &")
    peer.wait_until_succeeds("test -s /run/reload.pcap")
    flood = """
    import pathlib, socket, time
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    end = time.monotonic() + 5
    while time.monotonic() < end:
        try:
            s.sendto(b'no-leak', ('203.0.113.2', 8001))
        except PermissionError:
            pass
        time.sleep(0.001)
    pathlib.Path('/run/flood-done').touch()
    """
    machine.succeed(python(flood) + " >/run/flood.log 2>&1 &")
    for _ in range(10):
        machine.succeed("systemctl reload mihomo-killswitch")
    machine.wait_until_succeeds("test -e /run/flood-done", timeout=timedelta(seconds=30))
    peer.succeed("pkill -INT tcpdump")
    peer.wait_until_fails("pgrep tcpdump")
    assert peer.succeed("tcpdump -n -r /run/reload.pcap 2>/dev/null").strip() == ""

    # Failed nft transactions preserve the old policy too.
    machine.succeed("printf '%s\\n' 'flush table inet mihomo_guard' 'add rule inet mihomo_guard nonexistent counter accept' > /run/bad.nft")
    machine.fail("nft -f /run/bad.nft")
    machine.fail(probe())

    # A failed guard start gates both network management and the trusted broker.
    machine.succeed("systemctl stop NetworkManager mihomo-killswitch; nft list table inet mihomo_guard; mkdir -p /run/systemd/system/mihomo-killswitch.service.d; printf '[Service]\\nExecStart=\\nExecStart=/run/current-system/sw/bin/false\\n' > /run/systemd/system/mihomo-killswitch.service.d/failure.conf; systemctl daemon-reload")
    machine.fail("systemctl start NetworkManager")
    machine.fail("systemctl start mihomo")
    machine.fail("systemctl is-active NetworkManager")
    machine.fail("systemctl is-active mihomo")
    machine.fail(probe())
    machine.succeed("rm /run/systemd/system/mihomo-killswitch.service.d/failure.conf; systemctl daemon-reload; systemctl reset-failed; systemctl start NetworkManager mihomo")
    for udp in (False, True):
        machine.wait_until_succeeds(probe("203.0.113.3", udp=udp), timeout=timedelta(seconds=30))
        machine.fail(probe(udp=udp))
  '';
}
