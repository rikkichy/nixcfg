{ config, lib, pkgs, ... }:
let
  renderer = pkgs.callPackage ../pkgs/mihomo-config { };
in
{
  systemd.services.mihomo-config = {
    description = "Render Mihomo's private configuration";
    before = [ "mihomo.service" ];
    requiredBy = [ "mihomo.service" ];
    serviceConfig = {
      Type = "oneshot";
      UMask = "0077";
      RuntimeDirectory = "mihomo";
      RuntimeDirectoryMode = "0700";
      RuntimeDirectoryPreserve = "yes";
      ExecStart = "${lib.getExe renderer} ${lib.escapeShellArg config.networking.hostName} ${../dotfiles/mihomo.yaml} /etc/mihomo/subscription.url /etc/mihomo/quattro.url /run/mihomo/config.yaml /run/mihomo-api.header ${lib.escapeShellArg config.users.users.ri.name}";
    };
  };
  services.mihomo.configFile = "/run/mihomo/config.yaml";
  systemd.services.mihomo.restartTriggers = [ ../dotfiles/mihomo.yaml renderer ];
}
