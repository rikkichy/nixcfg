{ config, pkgs, lib, nixcfgPath, ... }:

{
  home.packages = lib.mkAfter (with pkgs; [
    (runCommand "swww-compat" { } ''
      mkdir -p $out/bin
      ln -s ${awww}/bin/awww $out/bin/swww
      ln -s ${awww}/bin/awww-daemon $out/bin/swww-daemon
    '')
  ]);

  systemd.user.services.wayle = {
    Unit = {
      Description = "Wayle desktop shell";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.wayle}/bin/wayle shell";
      Restart = "on-failure";
      RestartSec = "5s";
      Slice = "session.slice";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  xdg.dataFile."icons/hicolor/scalable/actions/halrune-symbolic.svg".source =
    ../dotfiles/wayle/halrune-symbolic.svg;

  xdg.configFile = {
    "wayle/config.toml".force = true;
    "wayle/config.toml".text = ''

      [general]
      font-sans = "Google Sans Flex Rounded"
      font-mono = "JetBrains Mono NF"
      tearing-mode = true

      [bar]
      location = "left"
      scale = 0.95
      inset-edge = 0.0
      inset-ends = 0.0
      rounding = "none"
      shadow = "none"
      button-rounding = "full"

      button-group-rounding = "full"

      button-variant = "basic"

      [[bar.layout]]
      monitor = "*"
      show = true
      left = [
          "custom-launcher",
          "hyprland-workspaces",
          "notifications",
          "clock",
      ]
      center = []
      right = [
          "systray",
          "microphone",
          "volume",
          "network",
          "bluetooth",
          "power",
      ]

      [styling]
      theme-provider = "matugen"
      matugen-scheme = "content"
      rounding = "lg"

      [modules.hyprland-workspaces]
      show-special = true
      min-workspace-count = 4
      display-mode = "label"
      workspace-padding = 0.6

      [[modules.custom]]
      id = "launcher"
      interval-ms = 0
      icon-name = "halrune-symbolic"
      icon-color = "accent"
      label-show = false
      left-click = "pkill -x fuzzel || fuzzel"

      [modules.power]
      left-click = "powermenu"

      [modules.clock]
      format = "%H\n%M"

      [modules.bluetooth]
      label-show = false

      [modules.network]
      label-show = false

      [modules.microphone]
      label-show = false
      icon-color = "accent"

      [modules.volume]
      label-show = false
      icon-color = "accent"

      [modules.notifications]
      popup-urgency-bar = "none"

      [wallpaper]
      transition-fps = 240
    '';

    "wayle/styles/index.scss".force = true;
    "wayle/styles/index.scss".text = ''
      .dropdown-header {
          background: var(--bg-surface);
          border-bottom: none;
      }
    '';

    "hypr".source =
      config.lib.file.mkOutOfStoreSymlink "${nixcfgPath}/hypr";
  };
}
