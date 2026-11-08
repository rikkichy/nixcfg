{ config, lib, pkgs, ... }:

let
  rules = pkgs.writeText "mihomo-killswitch.nft" ''
    # Creation and replacement are one netlink transaction, including on reload.
    destroy table inet mihomo_guard
    table inet mihomo_guard {
      set private_v4 {
        type ipv4_addr
        flags interval
        elements = { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16 }
      }
      chain output {
        type filter hook output priority -10; policy drop;
        oifname "lo" accept
        meta nfproto ipv4 oifname "mihomo" accept
        # The trusted broker needs direct bootstrap, provider and node access.
        meta nfproto ipv4 meta skuid "mihomo" accept
        ip daddr @private_v4 accept
        ip daddr 255.255.255.255 udp sport 68 udp dport 67 accept
        ip daddr 224.0.0.251 udp dport 5353 accept
        ip daddr 239.255.255.250 udp dport 1900 accept
        counter drop
      }
      chain forward {
        type filter hook forward priority -10; policy drop;
        meta nfproto ipv4 oifname "mihomo" accept
        ip daddr @private_v4 accept
        # No established/related exemption: a route change must not leak a flow.
        counter drop
      }
    }
  '';
  loadRules = "${lib.getExe pkgs.nftables} -f ${rules}";
in
{
  assertions = [
    {
      assertion = !config.boot.initrd.network.enable;
      message = "The Mihomo egress guard does not cover initrd networking.";
    }
    {
      assertion = !config.networking.nftables.enable;
      message = "The independent Mihomo egress guard requires the existing iptables firewall, not a ruleset-flushing nftables service.";
    }
  ];

  # DynamicUser reuses this system account; its UID survives service restarts.
  users.groups.mihomo = { };
  users.users.mihomo = {
    isSystemUser = true;
    group = "mihomo";
  };

  systemd.services.mihomo-killswitch = {
    description = "Fail-closed Mihomo Internet egress guard";
    wantedBy = [ "network-pre.target" ];
    before = [ "network-pre.target" "NetworkManager.service" "mihomo.service" ];
    after = [ "local-fs.target" "systemd-sysusers.service" ];
    unitConfig.DefaultDependencies = false;
    reloadIfChanged = true;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = loadRules;
      ExecReload = loadRules;
      # Deliberately no ExecStop: tunnel/service shutdown must retain the guard.
    };
  };

  systemd.services.NetworkManager = {
    requires = [ "mihomo-killswitch.service" ];
    after = [ "mihomo-killswitch.service" ];
  };
  systemd.services.mihomo = {
    requires = [ "mihomo-killswitch.service" ];
    after = [ "mihomo-killswitch.service" ];
    serviceConfig.User = "mihomo";
    serviceConfig.Group = "mihomo";
  };
}
