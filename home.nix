{ config, pkgs, inputs, ... }:

{
  imports = [ inputs.caelestia-shell.homeManagerModules.default ];

  home.stateVersion = "26.05";

  programs.caelestia = {
    enable = true;
    cli.enable = true;

    settings = {
      general.idle.timeouts = [ ];

      general.apps.explorer = [ "nautilus" ];

      dashboard.showWeather = false;

      notifs.fullscreen = "off";

      bar.tray.recolour = true;

      background.desktopClock.enabled = true;

      lock.useWallpaper = true;
      lock.hideNotifs = true;

      utilities.toasts.capsLockChanged = false;
      utilities.toasts.numLockChanged = false;

      services.playerAliases = [ { from = "chromium"; to = "Spotify"; } ];

      services.lyricsBackend = "Local";

      appearance.transparency.enabled = false;
      background.wallpaperEnabled = true;

      bar.persistent = true;
      bar.showOnHover = true;
      bar.workspaces = {
        activeIndicator = true;
        activeTrail = false;
        maxWindowIcons = 5;
        occupiedBg = true;
        showWindows = false;
        shown = 4;
      };

      launcher.maxShown = 4;
      launcher.showOnHover = false;
      launcher.useFuzzy.apps = true;

      services.visualiserBars = 20;

      sidebar.enabled = true;
    };
  };

  xdg.desktopEntries = let
    webApp = name: url: icon: {
      inherit name icon;
      exec = "${pkgs.chromium}/bin/chromium --app=${url}";
      terminal = false;
      categories = [ "Network" ];
    };
  in {
    bitwarden = webApp "Bitwarden" "https://vault.bitwarden.com" "bitwarden";
    discord = webApp "Discord" "https://discord.com/app" "discord";
    spotify = webApp "Spotify" "https://open.spotify.com" "spotify";
  };

  home.packages = with pkgs; [ papirus-icon-theme adw-gtk3 ];

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "chromium-browser.desktop";
      "x-scheme-handler/http" = "chromium-browser.desktop";
      "x-scheme-handler/https" = "chromium-browser.desktop";
      "x-scheme-handler/about" = "chromium-browser.desktop";
      "x-scheme-handler/unknown" = "chromium-browser.desktop";
      "inode/directory" = "org.gnome.Nautilus.desktop";
      "video/mp4" = "mpv.desktop";
      "video/x-matroska" = "mpv.desktop";
      "audio/mpeg" = "mpv.desktop";
    };
  };

  systemd.user.services.hyprpolkitagent = {
    Unit = {
      Description = "Hyprland polkit authentication agent";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.hyprpolkitagent}/bin/hyprpolkitagent";
      Restart = "on-failure";
      RestartSec = "3s";
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
      Type = "simple";
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

  programs.foot = {
    enable = true;
    settings = {
      main = {
        shell = "fish";
        title = "foot";
        font = "JetBrains Mono Nerd Font:size=12";
        letter-spacing = 0;
        dpi-aware = "no";
        pad = "25x25";
        bold-text-in-bright = "no";
        gamma-correct-blending = "no";
      };
      scrollback.lines = 10000;
      cursor = {
        style = "beam";
        beam-thickness = 1.5;
      };

      colors-dark.alpha = 0.78;
      key-bindings = {
        scrollback-up-page = "Page_Up";
        scrollback-down-page = "Page_Down";
        search-start = "Control+Shift+f";
      };
      search-bindings = {
        cancel = "Escape";
        find-prev = "Shift+F3";
        find-next = "F3 Control+G";
      };
    };
  };

  programs.fish = {
    enable = true;
    shellAbbrs = {
      lg = "lazygit";
      gd = "git diff";
      ga = "git add .";
      gc = "git commit -am";
      gl = "git log";
      gs = "git status";
      gst = "git stash";
      gsp = "git stash pop";
      gp = "git push";
      gpl = "git pull";
      gsw = "git switch";
      gsm = "git switch main";
      gb = "git branch";
      gbd = "git branch -d";
      gco = "git checkout";
      gsh = "git show";
      l = "ls";
      ll = "ls -l";
      la = "ls -a";
      lla = "ls -la";
    };
    shellAliases.ls = "eza --icons --group-directories-first -1";

    interactiveShellInit = ''
      starship init fish | source
      direnv hook fish | source
      zoxide init fish --cmd cd | source

      # Live colour scheme -- caelestia rewrites this file on every
      # `caelestia scheme set` and the escape codes repaint the terminal.
      cat ~/.local/state/caelestia/sequences.txt 2> /dev/null

      # For jumping between prompts in foot terminal
      function mark_prompt_start --on-event fish_prompt
          echo -en "\e]133;A\e\\"
      end

      # Your own overrides. caelestia's installer used to `touch` this; the
      # `2> /dev/null` means an absent file is simply a no-op.
      source $HOME/.config/caelestia/user-config.fish 2> /dev/null
    '';

    functions.fish_greeting = ''
      echo -ne '\x1b[38;5;16m'  # Set colour to primary
      echo '     ______           __          __  _       '
      echo '    / ____/___ ____  / /__  _____/ /_(_)___ _ '
      echo '   / /   / __ `/ _ \/ / _ \/ ___/ __/ / __ `/ '
      echo '  / /___/ /_/ /  __/ /  __(__  ) /_/ / /_/ /  '
      echo '  \____/\__,_/\___/_/\___/____/\__/_/\__,_/   '
      set_color normal
      fastfetch --key-padding-left 5
    '';
  };

  xdg.configFile = {
    "starship.toml".source = ./dotfiles/starship.toml;
    "btop/btop.conf".source = ./dotfiles/btop.conf;
    "fastfetch/config.jsonc".source = ./dotfiles/fastfetch.jsonc;
    "micro/settings.json".text = ''
      {
          "colorscheme": "simple"
      }
    '';

    "gtk-3.0/settings.ini".text = ''
      [Settings]
      gtk-application-prefer-dark-theme=0
    '';
    "gtk-4.0/settings.ini".text = ''
      [Settings]
      gtk-application-prefer-dark-theme=0
    '';

    "hypr".source =
      config.lib.file.mkOutOfStoreSymlink "/home/ri/nixcfg/hypr";
  };
}
