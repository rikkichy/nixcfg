{ config, pkgs, lib, inputs, terminalColours, ... }:

let
  yaziSession = pkgs.writeShellScript "yazi-session" ''
    palette=${lib.escapeShellArg "${dirOf terminalColours}/sequences.txt"}
    if [ -r "$palette" ]; then
      ${pkgs.coreutils}/bin/cat -- "$palette"
    fi
    exec ${lib.getExe config.programs.yazi.finalPackage} "$@"
  '';
  yaziOpen = pkgs.writeShellApplication {
    name = "yazi-open";
    text = ''
      exec ${lib.getExe config.programs.foot.package} --app-id=yazi --title=Yazi -- ${yaziSession} "$@"
    '';
  };
in
{
  home.activation.osuSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    osudir="${config.home.homeDirectory}/.local/share/osu"
    run mkdir -p "$osudir"
    for f in game.ini input.json; do
      if [ ! -e "$osudir/$f" ]; then
        run cp ${../../dotfiles/gaming/osu}/"$f" "$osudir/$f"
        run chmod u+w "$osudir/$f"
      fi
    done
  '';

  dconf.settings."org/gnome/desktop/interface" = {
    gtk-theme = "adw-gtk3-dark";
    color-scheme = "prefer-dark";
    icon-theme = "Papirus-Dark";
  };

  gtk = {
    enable = true;
    gtk2.enable = false;
    gtk3 = {
      extraConfig.gtk-application-prefer-dark-theme = 0;
      bookmarks = [
        "file://${config.home.homeDirectory}/Pictures/Screenshots"
        "file://${config.home.homeDirectory}/Documents"
        "file://${config.home.homeDirectory}/Downloads"
      ];
    };
    gtk4.extraConfig.gtk-application-prefer-dark-theme = 0;
  };

  services.mpris-proxy.enable = true;

  programs.yazi = {
    enable = true;
    enableFishIntegration = true;
    shellWrapperName = "y";
    keymap.mgr.prepend_keymap = [
      { on = [ "g" "s" ]; run = "cd ~/Pictures/Screenshots"; desc = "Screenshots"; }
      { on = [ "g" "D" ]; run = "cd ~/Documents"; desc = "Documents"; }
      { on = [ "g" "d" ]; run = "cd ~/Downloads"; desc = "Downloads"; }
    ];
  };

  home.packages = [ yaziOpen ];
  xdg.desktopEntries.yazi = {
    name = "Yazi File Manager";
    icon = "yazi";
    exec = "${lib.getExe yaziOpen} %f";
    terminal = false;
    categories = [ "System" "FileManager" "FileTools" ];
    mimeType = [ "inode/directory" ];
  };

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "brave-origin.desktop";
      "x-scheme-handler/http" = "brave-origin.desktop";
      "x-scheme-handler/https" = "brave-origin.desktop";
      "x-scheme-handler/about" = "brave-origin.desktop";
      "x-scheme-handler/unknown" = "brave-origin.desktop";
      "inode/directory" = "yazi.desktop";
      "video/mp4" = "mpv.desktop";
      "video/x-matroska" = "mpv.desktop";
      "audio/mpeg" = "mpv.desktop";
    }
    // lib.genAttrs [
      "image/png"
      "image/jpeg"
      "image/gif"
      "image/webp"
      "image/avif"
      "image/heic"
      "image/heif"
      "image/jxl"
      "image/bmp"
      "image/tiff"
      "image/svg+xml"
    ] (_: "swayimg.desktop")
    // lib.genAttrs [
      "application/x-osu-beatmap"
      "application/x-osu-storyboard"
      "application/x-osu-skin-archive"
      "application/x-osu-beatmap-archive"
      "application/x-osu-replay"
      "x-scheme-handler/osu"
    ] (_: "osu!.desktop");
  };

  systemd.user.services.openwave = {
    Unit = {
      Description = "OpenWave Audio Manager";
      Wants = [ "pipewire.service" "wireplumber.service" ];
      Before = [ "pipewire.service" "wireplumber.service" ];
      StartLimitIntervalSec = 60;
      StartLimitBurst = 5;
    };
    Service = {
      Type = "simple";
      ExecStart = "${inputs.openwave.packages.${pkgs.stdenv.hostPlatform.system}.openwave-bin}/bin/openwave-daemon";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install.WantedBy = [ "default.target" ];
  };

  # Upstream reserves openwave.service for the capture daemon.
  systemd.user.services.openwave-gui = {
    Unit = {
      Description = "OpenWave audio controls";
      PartOf = [ "graphical-session.target" ];
      Requisite = [ "graphical-session.target" ];
      Requires = [ "openwave.service" ];
      After = [ "graphical-session.target" "openwave.service" ];
    };
    Service = {
      Type = "exec";
      ExecStart = "${inputs.openwave.packages.${pkgs.stdenv.hostPlatform.system}.openwave-bin}/bin/openwave --hide";
      Slice = "session.slice";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.tg-ws-proxy = {
    Unit = {
      Description = "Local MTProto proxy for Telegram";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      StateDirectory = "tg-ws-proxy";
      StateDirectoryMode = "0700";
      ExecStart = toString (pkgs.writeShellScript "tg-ws-proxy-start" ''
        set -eu
        dir="$STATE_DIRECTORY"
        if [ ! -s "$dir/secret" ]; then
          ${pkgs.openssl}/bin/openssl rand -hex 16 > "$dir/secret"
          chmod 600 "$dir/secret"
        fi
        exec ${pkgs.tg-ws-proxy}/bin/tg-ws-proxy \
          --host 127.0.0.1 --port 1443 --secret "$(cat "$dir/secret")"
      '');
      Restart = "on-failure";
      RestartSec = "5s";
      Slice = "session.slice";
    };
    Install.WantedBy = [ "default.target" ];
  };

  xdg.configFile = {
    # Adopt the capture daemon's existing systemctl-enable symlink.
    "systemd/user/default.target.wants/openwave.service".force = true;

    "qtengine/config.json" = {
      force = true;
      text = builtins.toJSON {
        theme = {
          colorScheme = "${config.home.homeDirectory}/.config/qtengine/scheme.colors";
          iconTheme = "Papirus-Dark";
          style = "Darkly";
          font = { family = "Google Sans Flex"; size = 12; weight = -1; };
          fontFixed = { family = "DepartureMono Nerd Font"; size = 12; weight = -1; };
        };
        misc = {
          menusHaveIcons = true;
          singleClickActivate = false;
          shortcutsForContextMenus = true;
        };
      };
    };

    "gtk-3.0/bookmarks".force = true;
  };
}
