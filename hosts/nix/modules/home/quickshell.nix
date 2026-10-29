{ config, pkgs, lib, nixcfgPath, ... }:

let
  desktopApps = pkgs.writeShellApplication {
    name = "expressive-apps";
    runtimeInputs = [
      (pkgs.python3.withPackages (python: [ python.pygobject3 ]))
      pkgs.xdg-terminal-exec
      pkgs.foot
    ];
    text = ''
      exec python3 ${../../dotfiles/ricing/quickshell/desktop-apps.py} "$@"
    '';
  };
in
{
  home.packages = with pkgs; [ quickshell blueman ];

  systemd.user.services.quickshell = {
    Unit = {
      Description = "Material 3 Expressive desktop shell";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
      X-Restart-Triggers = [ "${../../dotfiles/ricing/quickshell}" ];
    };
    Service = {
      ExecStart = "${pkgs.quickshell}/bin/quickshell --no-duplicate --config expressive";
      Restart = "on-failure";
      RestartSec = "2s";
      Slice = "session.slice";
      Environment = [
        "PATH=${lib.makeBinPath [ desktopApps pkgs.networkmanager pkgs.foot pkgs.pavucontrol pkgs.blueman pkgs.hyprland pkgs.systemd pkgs.zed-editor pkgs.wl-clipboard ]}:/etc/profiles/per-user/ri/bin:/run/current-system/sw/bin"
        "QT_QUICK_CONTROLS_STYLE=Basic"
        "QS_EMOJI_DATA=${pkgs.unicode-emoji.emoji-test}/share/unicode/emoji/emoji-test.txt"
        "QS_VPN_CONFIG=${nixcfgPath}/common/dotfiles/mihomo.yaml"
      ];
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  xdg.configFile = {
    "xdg-terminals.list".text = "foot.desktop\n";
    "autostart/blueman.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Blueman
      Hidden=true
    '';
    "quickshell/expressive".source = ../../dotfiles/ricing/quickshell;
    "hypr".source = config.lib.file.mkOutOfStoreSymlink "${nixcfgPath}/hosts/nix/dotfiles/ricing/hypr";
  };
}
