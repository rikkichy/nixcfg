{ lib, pkgs, ... }:

{
  nixpkgs.config.allowUnfreePredicate = pkg: lib.getName pkg == "obsidian-headless";

  environment.systemPackages = with pkgs; [
    yubikey-manager
    age-plugin-yubikey
    obsidian-headless
  ];

  systemd.services.obsidian-sync = {
    description = "Continuous Obsidian vault sync";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    environment.HOME = "/home/ri";
    serviceConfig = {
      User = "ri";
      WorkingDirectory = "/home/ri/vault/Obsidian";
      ExecStart = "${lib.getExe pkgs.obsidian-headless} sync --path /home/ri/vault/Obsidian --continuous";
      Restart = "always";
      RestartSec = "10s";
      UMask = "0077";
    };
  };

  services.pcscd.enable = true;
  services.udev.packages = [ pkgs.yubikey-personalization ];
  security.polkit = {
    enable = true;
    extraConfig = ''
      polkit.addRule(function (action, subject) {
        if (subject.user == "ri" && (
              action.id == "org.debian.pcsc-lite.access_pcsc" ||
              action.id == "org.debian.pcsc-lite.access_card")) {
          return polkit.Result.YES;
        }
      });
    '';
  };

  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };
  users.users.ri.extraGroups = [ "docker" "networkmanager" ];

  time.timeZone = "Europe/Moscow";
}
