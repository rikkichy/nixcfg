{ config, pkgs, lib, ... }:

let
  filenSyncPairs = pkgs.writeText "filen-sync-pairs.json" (builtins.toJSON [
    {
      local = "${config.home.homeDirectory}/Pictures/Wallpapers";
      remote = "/Sync/Pictures/Wallpapers";
      syncMode = "twoWay";
      excludeDotFiles = true;
    }
    {
      local = "${config.home.homeDirectory}/Videos/Animated Wallpapers";
      remote = "/Sync/Videos/AnimatedWallpapers";
      syncMode = "twoWay";
      excludeDotFiles = true;
    }
  ]);

  # Audacity 4 popups; see the macOS twin in hosts/ne/modules/system/preferences.nix.
  # It re-enables the welcome dialog whenever the last-shown version sorts before
  # the running one, so pin a sentinel above any 4.x. QSettings nests keys with "\".
  audacitySeed = pkgs.writeText "Audacity4.ini" (lib.generators.toINI { } {
    application = {
      hasCompletedFirstLaunchSetup = true;
      welcomeDialogShowOnStartup = false;
      welcomeDialogLastShownVersion = "9999";
      checkForUpdate = false;
    };
    project = {
      shouldAskSaveLocationType = false;
      lastUsedSaveLocationType = 1;
    };
    importexport.askExportLocationType = false;
    trackedit.deleteBehavior = 1;
    ui."application\\startup\\showSplashScreen" = false;
  });
in

{
  home.activation.osuSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    for osudir in "${config.home.homeDirectory}/.local/share/"{osu,morasooma/mosu}; do
      run mkdir -p "$osudir"
      for f in game.ini input.json; do
        if [ ! -e "$osudir/$f" ]; then
          run cp ${../../dotfiles/gaming/osu}/"$f" "$osudir/$f"
          run chmod u+w "$osudir/$f"
        fi
      done
    done
  '';

  home.activation.audacitySettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    audacityini="${config.xdg.configHome}/Audacity/Audacity4.ini"
    if [ ! -e "$audacityini" ]; then
      run install -Dm644 ${audacitySeed} "$audacityini"
    fi
  '';

  dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";

  gtk = {
    enable = true;
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
    gtk2.enable = false;
    iconTheme = {
      name = "Mignon-pastel-dark";
      package = pkgs.mignon-icon-theme;
    };
    gtk3 = {
      extraConfig.gtk-application-prefer-dark-theme = 0;
      bookmarks = [
        "file://${config.home.homeDirectory}/Pictures/Screenshots"
        "file://${config.home.homeDirectory}/Documents"
        "file://${config.home.homeDirectory}/Downloads"
        "file://${config.home.homeDirectory}/GamesExternal"
      ];
    };
    gtk4.extraConfig.gtk-application-prefer-dark-theme = 0;
  };

  services.mpris-proxy.enable = true;

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
      "text/html" = "google-chrome.desktop";
      "x-scheme-handler/http" = "google-chrome.desktop";
      "x-scheme-handler/https" = "google-chrome.desktop";
      "x-scheme-handler/about" = "google-chrome.desktop";
      "x-scheme-handler/unknown" = "google-chrome.desktop";
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
    ] (_: "osu!.desktop");
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

  systemd.user.services.waydroid-pinch = {
    Unit = {
      Description = "Virtual touchscreen for Waydroid pinch zoom";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = lib.getExe pkgs.waydroid-pinch;
      Restart = "on-failure";
      Slice = "session.slice";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.filen-sync = {
    Unit = {
      Description = "Filen two-way sync";
      PartOf = [ "graphical-session.target" ];
      # The saved login's key lives in the GNOME keyring, unlocked by the session.
      After = [ "graphical-session.target" ];
      # Without saved credentials the CLI blocks on an interactive login prompt.
      AssertPathExists = "${config.xdg.configHome}/filen-cli/.filen-cli-keep-me-logged-in";
    };
    Service = {
      ExecStart = "${lib.getExe pkgs.filen-cli} --skip-update --quiet sync ${filenSyncPairs} --continuous";
      Restart = "on-failure";
      RestartSec = "30s";
      Slice = "session.slice";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  xdg.configFile = {
    "qtengine/config.json" = {
      force = true;
      text = builtins.toJSON {
        theme = {
          colorScheme = "${config.home.homeDirectory}/.config/qtengine/scheme.colors";
          iconTheme = config.gtk.iconTheme.name;
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
