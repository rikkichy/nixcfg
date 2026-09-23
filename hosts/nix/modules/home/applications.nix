{ config, pkgs, lib, ... }:

{
  home.file.".config/net.imput.helium/WidevineCdm/${pkgs.widevine-cdm.version}" = {
    source = "${pkgs.widevine-cdm}/share/google/chrome/WidevineCdm";
    recursive = true;
  };

  home.activation.equicordSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    settings="${config.home.homeDirectory}/.config/Equicord/settings/settings.json"
    if [ ! -e "$settings" ]; then
      run mkdir -p "$(dirname "$settings")"
      run cp ${
        pkgs.writeText "equicord-settings.json" (
          builtins.toJSON { enabledThemes = [ "wallpaper.theme.css" ]; }
        )
      } "$settings"
      run chmod u+w "$settings"
    fi
  '';

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

  xfconf.settings.thunar = {
    last-menubar-visible = false;
    hidden-bookmarks = [
      "file://${config.home.homeDirectory}/Desktop"
      "recent:///"
    ];
  };

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "helium.desktop";
      "x-scheme-handler/http" = "helium.desktop";
      "x-scheme-handler/https" = "helium.desktop";
      "x-scheme-handler/about" = "helium.desktop";
      "x-scheme-handler/unknown" = "helium.desktop";
      "inode/directory" = "thunar.desktop";
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
    ] (_: "osu!.desktop")
    // lib.genAttrs [
      "application/x-rhythia-sspm"
      "application/x-rhythia-map"
      "application/x-rhythia-replay"
    ] (_: "rhythia.desktop");
  };

  systemd.user.services.tg-ws-proxy = {
    Unit = {
      Description = "Local MTProto proxy for Telegram";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      ExecStart = toString (pkgs.writeShellScript "tg-ws-proxy-start" ''
        set -eu
        dir="''${XDG_STATE_HOME:-$HOME/.local/state}/tg-ws-proxy"
        mkdir -p "$dir"
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
    "gtk-3.0/settings.ini".text = ''
      [Settings]
      gtk-application-prefer-dark-theme=0
    '';

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

    "gtk-3.0/bookmarks" = {
      force = true;
      text = ''
        file://${config.home.homeDirectory}/Pictures/Screenshots
        file://${config.home.homeDirectory}/Documents
        file://${config.home.homeDirectory}/Downloads
      '';
    };
    "gtk-4.0/settings.ini".text = ''
      [Settings]
      gtk-application-prefer-dark-theme=0
    '';
  };
}
