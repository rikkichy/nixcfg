{ config, pkgs, lib, nixcfgPath, ... }:

{
  home.packages = with pkgs; [ quickshell blueman ];

  systemd.user.services.quickshell = {
    Unit = {
      Description = "Material 3 Expressive desktop shell";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
      X-Restart-Triggers = [ "${../../../dotfiles/nix/quickshell}" ];
    };
    Service = {
      ExecStart = "${pkgs.quickshell}/bin/quickshell --no-duplicate --config expressive";
      Restart = "on-failure";
      RestartSec = "2s";
      Slice = "session.slice";
      Environment = [
        "PATH=${lib.makeBinPath [ pkgs.fuzzel pkgs.psmisc pkgs.networkmanager pkgs.foot pkgs.pavucontrol pkgs.blueman ]}:/etc/profiles/per-user/ri/bin:/run/current-system/sw/bin"
        "QT_QUICK_CONTROLS_STYLE=Basic"
      ];
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  xdg.configFile = {
    "quickshell/expressive".source = ../../../dotfiles/nix/quickshell;
    "hypr".source = config.lib.file.mkOutOfStoreSymlink "${nixcfgPath}/dotfiles/nix/hypr";
  };
}
