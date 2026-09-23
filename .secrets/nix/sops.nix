{ config, lib, pkgs, ... }:
let
  provisioned = builtins.pathExists ./personal.yaml;
  python = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
  source = name: legacy:
    if provisioned then config.sops.secrets."mihomo/${name}".path else "/etc/mihomo/${legacy}";
in
{
  sops = lib.mkIf provisioned {
    useSystemdActivation = true;
    defaultSopsFile = ./personal.yaml;
    age = {
      keyFile = "/var/lib/sops-nix/key.txt";
      generateKey = false;
      sshKeyPaths = [ ];
    };
    gnupg.sshKeyPaths = [ ];
    secrets = lib.genAttrs [ "mihomo/primary_url" "mihomo/quattro_url" "mihomo/hwid" ] (_: {
      mode = "0400";
      restartUnits = [ "mihomo.service" ];
    });
  };

  systemd.services.mihomo-config = {
    description = "Render Mihomo's private configuration";
    before = [ "mihomo.service" ];
    requiredBy = [ "mihomo.service" ];
    requires = lib.optional provisioned "sops-install-secrets.service";
    after = lib.optional provisioned "sops-install-secrets.service";
    serviceConfig = {
      Type = "oneshot";
      UMask = "0077";
      RuntimeDirectory = "mihomo";
      RuntimeDirectoryMode = "0700";
      RuntimeDirectoryPreserve = "yes";
      ExecStart = "${python}/bin/python ${../../pkgs/nix/bypasses/mihomo-config.py} ${if provisioned then "sops" else "legacy"} ${../../dotfiles/nix/bypasses/mihomo.yaml} ${source "primary_url" "subscription.url"} ${source "quattro_url" "quattro.url"} ${source "hwid" "hwid"} /run/mihomo/config.yaml";
    };
  };
  services.mihomo.configFile = "/run/mihomo/config.yaml";
  systemd.services.mihomo.restartTriggers = [ ../../dotfiles/nix/bypasses/mihomo.yaml ../../pkgs/nix/bypasses/mihomo-config.py ];
}
