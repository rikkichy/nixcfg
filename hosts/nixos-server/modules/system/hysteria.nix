{ config, lib, pkgs, ... }:

{
  environment.etc."hysteria/server.example.yaml".source =
    ../../dotfiles/hysteria/server.example.yaml;

  networking.firewall.allowedUDPPorts =
    lib.optionals config.systemd.services.hysteria.enable [ 443 ];

  systemd.services.hysteria = {
    # Enable only after provisioning /etc/hysteria/{server.yaml,server.crt,server.key}.
    enable = false;
    description = "Hysteria2 SSH transport";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.hysteria}/bin/hysteria server --config %d/server.yaml";
      DynamicUser = true;
      LoadCredential = [
        "server.yaml:/etc/hysteria/server.yaml"
        "server.crt:/etc/hysteria/server.crt"
        "server.key:/etc/hysteria/server.key"
      ];
      AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
      CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}
