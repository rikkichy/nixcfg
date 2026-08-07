{ config, pkgs, lib, inputs, nixcfgPath, ... }:

let
  # Seeded into ~/.config/caelestia/shell.json below rather than passed to
  # programs.caelestia.settings. That option writes the file as a read-only
  # store symlink, and Caelestia rewrites its merged config on every start --
  # so it logged "Failed to write .../shell.json: Read-only file system" each
  # time and nothing changed in the GUI could ever be saved. These are defaults
  # for a fresh install; once the file exists it belongs to Caelestia, so
  # editing them here will not affect a machine that already has one.
  caelestiaDefaults = {
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

    # Every shell animation duration is `token * scale`, so this is the only
    # writable speed control -- the per-size durations (small 200, normal 400,
    # large 600, extraLarge 1000 ms) are read-only properties derived from it.
    # Lower is faster, the inverse of Hyprland's `speed` in hypr/hyprland/
    # animations.lua, which is a separate system this does not touch.
    appearance.anim.durations.scale = 0.6;
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

  caelestiaSeed = pkgs.writeText "caelestia-shell.json"
    (builtins.toJSON caelestiaDefaults);

  # The colour scheme, applied by the activation script below.
  #
  # `dynamic` generates the palette from the current wallpaper rather than
  # reading one of the bundled scheme files, so what is declared here is which
  # generator runs, not a set of colours -- the colours themselves change every
  # time the wallpaper does. `flavour` picks the generator's contrast (`default`
  # or `hard`); `mode` and `variant` are left out on purpose, because
  # `services.smartScheme` derives both from the wallpaper on the dynamic path
  # and setting them here would fight that on every rebuild.
  caelestiaScheme = { name = "dynamic"; flavour = "default"; };

in
{
  imports = [ inputs.caelestia-shell.homeManagerModules.default ];

  home.stateVersion = "26.05";

  # Leaving settings unset matters: the module gates the file on
  # `extraConfig != "" || settings != {}`, so an empty set means it writes no
  # shell.json at all and the seed below owns the path.
  programs.caelestia = {
    enable = true;
    cli.enable = true;

    # SUPER+D runs `caelestia toggle communication`, whose built-in config
    # spawns `discord` and matches windows whose `class` contains "discord".
    # The native client satisfies both: the binary is on PATH from
    # systemPackages, so shutil.which() resolves it, and its window class is
    # plain "discord". Nothing needs overriding.
  };

  # Write a real, writable file, but only when there is not one already, so the
  # GUI keeps whatever the user changes. Runs after writeBoundary so
  # home-manager has finished removing the store symlink it used to place here.
  home.activation.seedCaelestiaShell =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      target="${config.xdg.configHome}/caelestia/shell.json"
      if [ -L "$target" ]; then
        $DRY_RUN_CMD rm -f "$target"       # leftover read-only store symlink
      fi
      if [ ! -e "$target" ]; then
        $DRY_RUN_CMD mkdir -p "$(dirname "$target")"
        $DRY_RUN_CMD cp ${caelestiaSeed} "$target"
        $DRY_RUN_CMD chmod 644 "$target"
      fi
    '';

  # Caelestia owns ~/.local/state/caelestia/scheme.json outright -- it rewrites
  # the whole file, colours included, on `scheme set`, on every wallpaper
  # change, and on the dark/light toggle in the shell -- so the scheme is
  # applied by invoking the CLI rather than by placing a file. Writing that JSON
  # directly relabels the scheme and repaints nothing: the template pass that
  # produces hypr/scheme/current.lua, gtk.css, fuzzel.ini, the btop/htop/cava
  # themes and the terminal escape sequences runs inside `scheme set` and
  # nowhere else.
  #
  # The guard is what keeps this out of the rebuild's critical path. `scheme
  # set` re-runs that whole template pass unconditionally, even when every
  # property already matches, so it is only worth calling when something
  # differs; `scheme get -nf` prints name and flavour on separate lines in that
  # fixed order.
  #
  # A dynamic scheme cannot be generated before a wallpaper exists -- the CLI
  # raises and exits non-zero -- which is the state of a machine that has been
  # installed but never logged into. Skipping explicitly keeps that from failing
  # activation midway through the install; the shell sets its bundled wallpaper
  # on first start, and the next activation applies the scheme.
  home.activation.caelestiaScheme =
    lib.hm.dag.entryAfter [ "writeBoundary" ] (
      let
        cli = "${config.programs.caelestia.cli.package}/bin/caelestia";
        inherit (caelestiaScheme) name flavour;
      in ''
        if [ ! -e "${config.xdg.stateHome}/caelestia/wallpaper/current" ]; then
          echo "caelestiaScheme: no wallpaper set yet, leaving the scheme alone"
        elif [ "$(${cli} scheme get -nf)" != $'${name}\n${flavour}' ]; then
          $DRY_RUN_CMD ${cli} scheme set -n ${name} -f ${flavour}
        fi
      ''
    );

  # `chromium --app=URL` gives its window a WM_CLASS of its own -- for
  # https://open.spotify.com that is chrome-open.spotify.com__-Default, i.e.
  # "chrome-" + host + "__" + path (slashes as underscores) + "-Default". That
  # never matches the desktop file's own id, so a running web app falls back to
  # the generic Chromium icon in the bar and alt-tab even though the launcher
  # entry looks right. StartupWMClass is what ties the window back to the entry,
  # so the icon below is used in both places. Verify a class with `hyprctl
  # clients` after launching the app; a wrong string fails silently.
  xdg.desktopEntries = let
    webApp = name: url: icon: wmClass: {
      inherit name icon;
      exec = "${pkgs.chromium}/bin/chromium --app=${url}";
      terminal = false;
      categories = [ "Network" ];
      settings.StartupWMClass = wmClass;
    };
  in {
    bitwarden = webApp "Bitwarden" "https://vault.bitwarden.com" "bitwarden"
      "chrome-vault.bitwarden.com__-Default";
    spotify = webApp "Spotify" "https://open.spotify.com" "spotify"
      "chrome-open.spotify.com__-Default";
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
      config.lib.file.mkOutOfStoreSymlink "${nixcfgPath}/hypr";
  };
}
