{ config, pkgs, inputs, ... }:

{
  # SETTLED 2026-08-04 by reading the flake source directly:
  # the output is `homeManagerModules.default`. The NixOS wiki's
  # `homeModules.default` does NOT exist and fails at eval.
  imports = [ inputs.caelestia-shell.homeManagerModules.default ];

  home.stateVersion = "26.05";

  programs.caelestia = {
    enable = true;
    cli.enable = true;   # adds standalone caelestia-cli to PATH

    # The module runs the shell as a systemd user service by default
    # (programs.caelestia.systemd.enable = true), bound to
    # graphical-session.target -- which UWSM activates properly.
    # Do NOT also exec-once the shell in your Hyprland config, or
    # you'll get two instances. Bonus: Restart=on-failure means a
    # mid-game crash revives the shell in 5s.

    # Generates ~/.config/caelestia/shell.json declaratively; the
    # service restarts automatically when it changes. Keys below were
    # verified against the current schema (plugin/src/Caelestia/Config,
    # read 2026-08-04) -- note the old session.idle.* and
    # bar.status.showBattery keys no longer exist.
    # NOTE: the module writes this as a READ-ONLY store symlink at
    # ~/.config/caelestia/shell.json. Settings you change from the Caelestia
    # GUI can no longer be saved -- this file is the source of truth now, and
    # a rebuild is how you change it. Everything below the first block was
    # lifted verbatim from the shell.json you are running on CachyOS today.
    # (Per-monitor overrides live in ~/.config/caelestia/monitors/<name>/ and
    # stay writable, since only the one FILE is symlinked, not the directory.)
    settings = {
      # Desktop mode: never lock, dim, or sleep on idle.
      general.idle.timeouts = [ ];

      # Default assumes thunar; you run Nautilus.
      general.apps.explorer = [ "nautilus" ];

      # Weather widget off.
      dashboard.showWeather = false;

      # No notification banners over fullscreen games ("off" verified
      # in services/Notifs.qml).
      notifs.fullscreen = "off";

      # Tray icons recoloured to match the material scheme.
      bar.tray.recolour = true;

      # Clock on the wallpaper; bottom-right is already the default
      # position, so enabling is enough.
      background.desktopClock.enabled = true;

      # Lock screen (manual lock only, given idle is off): your
      # wallpaper as the background, notification contents hidden.
      lock.useWallpaper = true;
      lock.hideNotifs = true;

      # No toasts when tapping caps/num lock.
      utilities.toasts.capsLockChanged = false;
      utilities.toasts.numLockChanged = false;

      # Spotify runs as a Chromium web app, so its media player
      # announces itself as chromium over MPRIS; alias it. If the
      # widget shows the wrong name, check `playerctl -l` for the
      # exact identity.
      services.playerAliases = [ { from = "chromium"; to = "Spotify"; } ];

      # No lyrics. Verified in lyrics.cpp: valid backends are only
      # Local/LRCLIB/NetEase/Auto -- there is NO off switch upstream.
      # Local with an empty lyrics dir means nothing ever displays.
      # (Nuclear option instead: dashboard.showMedia = false, but that
      # kills the whole media widget.)
      services.lyricsBackend = "Local";

      ## Carried over from the live CachyOS shell.json ##########
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

    # extraConfig is a JSON *string* (types.str), not an attrset --
    # verified in nix/hm-module.nix. Keys in `settings` override it.
    # extraConfig = ''{ "some": { "raw": "json" } }'';
  };

  #############################################################
  ## Chromium web apps (Bitwarden / Discord / Spotify)
  #############################################################

  # Plain .desktop entries launching Chromium in --app mode. They land
  # in ~/.nix-profile/share/applications, which is on XDG_DATA_DIRS,
  # so the caelestia launcher finds them like any installed app.
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

  # Provides the "bitwarden"/"discord"/"spotify" icon names above
  # (and nicer Nautilus icons). Drop it and the entries fall back to
  # a generic icon but stay perfectly searchable.
  # adw-gtk3 is the GTK3 theme caelestia's scheme pass expects: its theme.py
  # literally runs `dconf write /org/gnome/desktop/interface/gtk-theme
  # "'adw-gtk3-dark'"` -- without the package that name resolves to nothing.
  home.packages = with pkgs; [ papirus-icon-theme adw-gtk3 ];

  # Chromium is the default browser now (helium-browser is AUR-only and was
  # dropped in the migration). Mirrors your CachyOS mimeapps.list with
  # helium.desktop swapped out.
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

  #############################################################
  ## Polkit agent
  #############################################################

  # Replaces the `/usr/lib/polkit-gnome/...-agent-1` exec-once that the
  # CachyOS hypr/execs.lua had -- that path does not exist here. Modelled on
  # the caelestia unit: PartOf graphical-session.target so it dies with the
  # session, Restart=on-failure so a crash doesn't leave you with GUI
  # privilege prompts that fail silently for the rest of the session.
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

  #############################################################
  ## Dotfiles carried over from CachyOS
  #############################################################

  # WHAT IS DELIBERATELY *NOT* MANAGED HERE, and why:
  # `caelestia scheme set ...` regenerates these at runtime from its own
  # templates (verified in caelestia/utils/theme.py). Home-manager files are
  # read-only symlinks into the store, so managing any of them turns every
  # colour change into a write error:
  #   fuzzel/fuzzel.ini          <- fully overwritten
  #   btop/themes/caelestia.theme
  #   htop/htoprc                <- fully overwritten
  #   cava/config                <- fully overwritten
  #   gtk-3.0/gtk.css, gtk-4.0/gtk.css, thunar.css
  #   qtengine/config.json, qtengine/caelestia.colors
  #   nvtop/nvtop.colors, zed/themes/caelestia.json
  #   hypr/scheme/current.lua    <- covered by the mkOutOfStoreSymlink below
  # Only files caelestia never touches are declared below.
  #
  # For the same reason gtk-3.0/settings.ini is written by hand instead of via
  # home-manager's `gtk` module: that module (a) emits gtk-4.0/gtk.css as soon
  # as a theme package is set, colliding head-on with caelestia's, and (b)
  # writes the same /org/gnome/desktop/interface dconf keys caelestia sets, so
  # the two would overwrite each other on every switch.

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
      # Terminal colours are NOT set here on purpose -- fish cats
      # ~/.local/state/caelestia/sequences.txt on startup, which repaints the
      # palette live whenever the scheme changes. Hardcoding colours would
      # only fight it. alpha is static, so it stays.
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

    # The `command -v ... &> /dev/null &&` guards from the CachyOS config.fish
    # are dropped: on NixOS these binaries are in the profile by construction
    # (configuration.nix lists them), so a guard could only ever hide a
    # genuine packaging mistake.
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

  # Verbatim copies. These are large, opaque and hand-tuned upstream files --
  # transcribing them into Nix attrsets would buy nothing but transcription
  # bugs, and none of the three is a caelestia scheme target.
  # btop.conf keeps `color_theme = "caelestia"`, which resolves against
  # ~/.config/btop/themes/caelestia.theme -- written at runtime by caelestia
  # into the same (real, writable) directory.
  xdg.configFile = {
    "starship.toml".source = ./dotfiles/starship.toml;
    "btop/btop.conf".source = ./dotfiles/btop.conf;
    "fastfetch/config.jsonc".source = ./dotfiles/fastfetch.jsonc;
    "micro/settings.json".text = ''
      {
          "colorscheme": "simple"
      }
    '';
    # Matches your current CachyOS state. caelestia only ever writes gtk.css
    # in these directories, never settings.ini, so this is safe to own.
    "gtk-3.0/settings.ini".text = ''
      [Settings]
      gtk-application-prefer-dark-theme=0
    '';
    "gtk-4.0/settings.ini".text = ''
      [Settings]
      gtk-application-prefer-dark-theme=0
    '';

    ###########################################################
    ## Hyprland config -- live-editable, tracked in your repo
    ###########################################################

    # Points ~/.config/hypr at a real directory you own, so edits
    # apply instantly without a rebuild. Path MUST be absolute and
    # user-writable; keep the dir inside your flake repo so it's
    # still versioned. (Read-only alternative: .source = ./hypr;)
    #
    # It has to stay writable for a second reason beyond convenience:
    # hypr/hyprland.lua bootstraps scheme/current.lua from scheme/default.lua
    # on first start, and `caelestia scheme set` rewrites it afterwards. A
    # store symlink would make both fail. current.lua is gitignored.
    "hypr".source =
      config.lib.file.mkOutOfStoreSymlink "/home/ri/nixcfg/hypr";
  };

  # Note: wayland.windowManager.hyprland.systemd.enable is NOT set
  # here -- that option only matters if HM's own hyprland module is
  # enabled, which it isn't (Hyprland comes from configuration.nix).
  # If you ever enable it, set systemd.enable = false to avoid
  # racing UWSM over graphical-session.target.
}
