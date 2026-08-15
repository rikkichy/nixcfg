{ config, pkgs, lib, inputs, nixcfgPath, ... }:

let
  /* Caelestia is parked while Wayle is on trial. Restore by deleting this
     comment marker and its partner below, the one around the activation
     scripts, and uncommenting the import and programs.caelestia block.

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

  caelestiaScheme = { name = "dynamic"; flavour = "default"; };
  */

  caelestiaCli =
    inputs.caelestia-cli.packages.${pkgs.stdenv.hostPlatform.system}.caelestia-cli;

  # Bootstraps the colour scheme on a machine with no wallpapers yet. Every
  # themed file downstream -- fuzzel.ini, both gtk.css, the btop theme, the
  # terminal palette, hypr/scheme/current.lua -- is generated from a wallpaper,
  # so without one the whole chain has no root and a fresh install comes up on
  # stock defaults. Generated rather than borrowed so a public repo carries
  # nothing with a licence attached; a smooth gradient also costs 8 KiB, where
  # anything with noise in it runs to megabytes.
  defaultWallpaper = ./dotfiles/default-wallpaper.png;

  # Where the chosen wallpaper is recorded. Wayle keeps no record of its own:
  # `wallpaper set` draws the image and writes nothing, and the `[wallpaper]
  # monitors` list that would hold it stays empty unless the GUI fills it, so
  # a shell restart comes up on a blank desktop. This file is what
  # wallpaper-restore reads back.
  wallpaperRecord = ''"''${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper/current"'';

  # The half of wpp that is not the picker, split out so the restore unit can
  # reach it too. Both engines are driven here: wayle draws the wallpaper and
  # derives its own bar colours, caelestia themes everything wayle does not
  # reach. -v has to come after -f, which re-derives the variant from the image
  # and discards anything set before it.
  themeApply = pkgs.writeShellApplication {
    name = "theme-apply";
    runtimeInputs = [ pkgs.wayle caelestiaCli ];
    text = ''
      wallpaper="''${1:?usage: theme-apply <image>}"
      record=${wallpaperRecord}

      wayle wallpaper set --fit fill "$wallpaper"
      caelestia wallpaper -f "$wallpaper" || true
      caelestia scheme set -v content || true

      mkdir -p "$(dirname "$record")"
      printf '%s\n' "$wallpaper" > "$record"
    '';
  };

  # What the bar's special-workspace buttons are made of. Both halves address
  # a workspace by name, which is the point: a special workspace's id comes
  # from newSpecialID(), the highest live special id plus one counting up from
  # -99, so it depends on the order the overlays were first opened in and
  # anything keyed on it points somewhere else the next day.
  #
  # The state it reports distinguishes three things the bar draws
  # differently: absent (the overlay holds nothing, and Hyprland does not list
  # a workspace at all), idle, and on screen. hyprctl is left to the PATH
  # wayle inherits from the session rather than pinned here -- pkgs.hyprland
  # would be a second copy of the compositor in this closure to run two IPC
  # calls.
  #
  # `watch` is what the bar runs. Polling for this is visibly late: the
  # numbered workspaces are driven from Hyprland's event socket and change
  # under the cursor, so a button next to them that catches up a second later
  # reads as broken rather than slow. socket2 carries every event, so the
  # reply is filtered to the ones that can change an answer and then to
  # answers that actually differ, which keeps a mouse moving between windows
  # from redrawing anything.
  specialWs = pkgs.writeShellApplication {
    name = "special-ws";
    runtimeInputs = [ pkgs.jq pkgs.socat ];
    text = ''
      action="''${1:?usage: special-ws state|watch|toggle <name>}"
      name="''${2:?usage: special-ws state|watch|toggle <name>}"
      ws="special:$name"

      state() {
          if ! hyprctl -j workspaces | jq -e --arg w "$ws" 'any(.[]; .name == $w)' > /dev/null; then
              echo 0
          elif hyprctl -j monitors | jq -e --arg w "$ws" 'any(.[]; .specialWorkspace.name == $w)' > /dev/null; then
              echo open
          else
              echo idle
          fi
      }

      case "$action" in
      state)
          state
          ;;
      watch)
          last=""
          emit() {
              current=$(state)
              if [ "$current" != "$last" ]; then
                  last=$current
                  printf '%s\n' "$current"
              fi
          }

          emit
          socat -u UNIX-CONNECT:"$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" - |
              while IFS= read -r event; do
                  case "$event" in
                  activespecial* | openwindow* | closewindow* | movewindow* | createworkspace* | destroyworkspace*)
                      emit
                      ;;
                  esac
              done
          ;;
      toggle)
          # toggle_special prefixes "special:" itself, so it takes the bare
          # name. hyprctl's argument is Lua as of Hyprland 0.56.
          hyprctl repl "hl.dispatch(hl.dsp.workspace.toggle_special(\"$name\"))" > /dev/null
          ;;
      *)
          echo "special-ws: unknown action $action" >&2
          exit 1
          ;;
      esac
    '';
  };
in
{
  # imports = [ inputs.caelestia-shell.homeManagerModules.default ];

  home.stateVersion = "26.05";

  # programs.caelestia = {
  #   enable = true;
  #   cli.enable = true;
  # };

  /*
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
  */

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

    # fuzzel's launcher lists desktop entries, not PATH, so a bare `wpp` binary
    # is unreachable from it no matter how short the name is -- this entry is
    # what actually makes it typeable there. Name and Exec are both "wpp" so
    # the match happens on the first three keystrokes.
    wpp = {
      name = "wpp";
      genericName = "Wallpaper";
      comment = "Pick a wallpaper and retheme";
      exec = "wpp";
      icon = "preferences-desktop-wallpaper";
      terminal = false;
      categories = [ "Settings" ];
    };
  };

  # Wayle drives wallpapers by shelling out to `swww-daemon` by name, with no
  # setting to point it elsewhere -- the only backend key in its schema is
  # Wallust's image sampler, which is colour extraction rather than the
  # wallpaper daemon. nixpkgs carries that project under its new name, awww,
  # and ships no swww alias, so the lookup fails and the desktop stays blank
  # with one WARN line at startup and nothing later.
  # The launcher, replacing caelestia's. ~/.config/fuzzel/fuzzel.ini is left
  # alone deliberately: caelestia wrote it as part of its unconditional theme
  # sweep, so it already carries the right font and colours, and it is a plain
  # 0600 file rather than a store symlink. Putting it under xdg.configFile
  # would make it read-only for no gain.
  home.packages = with pkgs; [
    papirus-icon-theme
    adw-gtk3
    fuzzel
    wayle

    # Screenshots, replacing the caelestia CLI for that job. It carries grim,
    # slurp, jq and wl-clipboard on an injected PATH, so none of those need
    # installing here -- none of them are on this user's PATH at all.
    hyprshot

    # wayle's own bar/popover colours. theme-provider = matugen makes it shell
    # out to a `matugen` binary by name, exactly as it does to `swww-daemon`,
    # and the failure is the same shape: it logs `cannot execute color
    # extractor` once and then repeats `palette file not found:
    # ~/.cache/wayle/matugen-colors.json` forever, while the bar silently keeps
    # its built-in palette. Nothing in the UI says the theme provider is dead.
    matugen

    # The colour engine, without the shell that was crashing. caelestia-dots/cli
    # is its own flake, so this pulls in no quickshell and no Qt -- verified by
    # inspecting the closure. `scheme set` is what rewrote every app's theme
    # under caelestia, and it runs headless: fuzzel.ini, gtk-3.0 and gtk-4.0
    # gtk.css, the btop theme and the terminal escape sequences are all still
    # regenerated with nothing but this binary.
    #
    # hypr/scheme/current.lua is the exception -- that write is gated on
    # HYPRLAND_INSTANCE_SIGNATURE being set, so it silently does nothing from a
    # context that lacks it (a bare systemd unit, or su without the session
    # environment) while every other file updates normally.
    caelestiaCli
    themeApply

    # Reached by name from config.toml below: wayle runs a custom module's
    # command through `sh -c` with the session PATH, which carries the
    # per-user profile this lands in.
    specialWs

    (writeShellApplication {
      name = "wpp";
      runtimeInputs = [
        fuzzel
        gdk-pixbuf
        coreutils
        findutils
        libnotify
        themeApply
      ];
      text = ''
        dir="''${WALLPAPER_DIR:-$HOME/Pictures/Wallpapers}"
        cache="''${XDG_CACHE_HOME:-$HOME/.cache}/wallpaper-picker"

        # Both notify and print: bound to a key there is no terminal to read,
        # and run from a shell there may be no notification daemon.
        die() {
          echo "wpp: $1" >&2
          notify-send -a wpp "Wallpaper" "$1" 2>/dev/null || true
          exit 1
        }

        mapfile -t files < <(find "$dir" -maxdepth 1 -type f \
          \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
          2>/dev/null | sort)

        # An empty or missing directory used to be fatal, which on a fresh
        # install meant the one command that could theme the desktop was also
        # the one that refused to run. Falling back to the shipped default
        # themes the machine instead of explaining why it cannot.
        if [ "''${#files[@]}" -eq 0 ]; then
          notify-send -a wpp "Wallpaper" \
            "No images in $dir — applied the built-in default" 2>/dev/null || true
          theme-apply ${defaultWallpaper}
          exit 0
        fi

        mkdir -p "$cache"

        # fuzzel renders PNG and SVG icons only, so a JPEG source would show no
        # thumbnail at all; and pointing it at the originals would have it decode
        # up to 15 MB per row while the menu is opening. Both are avoided by
        # caching a small PNG per image, rebuilt only when the source is newer.
        #
        # The cache name keeps the source extension and appends .png, giving
        # 4721.jpg.png. Stripping the extension instead would map 4721.jpg and
        # 4721.png onto one cache entry, and the loser would silently show the
        # other image's thumbnail while setting the right wallpaper.
        for f in "''${files[@]}"; do
          base="''${f##*/}"
          thumb="$cache/$base.png"
          if [ ! -e "$thumb" ] || [ "$f" -nt "$thumb" ]; then
            gdk-pixbuf-thumbnailer -s 128 "$f" "$thumb" || true
          fi
        done

        # fuzzel has no icon-size setting: the icon is drawn at the row height,
        # so line-height is the only lever. Passed as a flag rather than set in
        # fuzzel.ini because that file is shared with the app launcher on SUPER,
        # which does not want 64px icons. 64 sits under the 128px the cache is
        # rendered at, so the thumbnails stay sharp; --lines drops with it since
        # 15 rows at this height is taller than the screen.
        #
        # Rofi's extended dmenu protocol, which fuzzel implements: name, NUL,
        # the literal "icon", 0x1f, then the icon. --index returns the position
        # rather than the text, so the answer maps back to the array without
        # depending on how the name renders or what characters it contains.
        idx=$(
          for f in "''${files[@]}"; do
            base="''${f##*/}"
            printf '%s\x00icon\x1f%s\n' "$base" "$cache/$base.png"
          done | fuzzel --dmenu --index --prompt "wp> " \
            --font "Google Sans Flex Rounded:size=17" --line-height=64px --lines 8
        ) || exit 0

        case "$idx" in
          "" | *[!0-9]*) exit 0 ;;
        esac

        chosen="''${files[$idx]}"

        theme-apply "$chosen"
      '';
    })
    (runCommand "swww-compat" { } ''
      mkdir -p $out/bin
      ln -s ${awww}/bin/awww $out/bin/swww
      ln -s ${awww}/bin/awww-daemon $out/bin/swww-daemon
    '')
  ];

  # Wayle ships no unit of its own, so this is hand-written rather than taken
  # from systemd.packages. graphical-session.target rather than default.target
  # keeps it out of the path of "reloading user units for ri" during a switch.
  #
  # It replaces only part of what caelestia did: bar, notifications, OSDs and
  # wallpaper. There is no launcher and no lock screen, so the caelestia:*
  # global dispatchers still bound in hypr/hyprland/keybinds.lua now resolve to
  # nothing -- they fail silently rather than erroring.
  systemd.user.services.wayle = {
    Unit = {
      Description = "Wayle desktop shell";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      # `wayle` on its own is a CLI dispatcher: it prints usage and exits 2.
      # The long-running shell is the `shell` subcommand, which stays in the
      # foreground, so Type=simple is right.
      ExecStart = "${pkgs.wayle}/bin/wayle shell";
      Restart = "on-failure";
      RestartSec = "5s";
      Slice = "session.slice";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # Puts the wallpaper back at every login, and themes a machine that has never
  # been themed. Two jobs in one unit because they answer the same question --
  # which image should be on screen -- and the recorded path is exactly what
  # distinguishes them.
  #
  # A recorded wallpaper is re-drawn and nothing else: every file the colour
  # engine generates is already on disk from the run that recorded it, so
  # rethemeing here would rewrite dozens of files to their current contents on
  # every login. No record means nothing has ever chosen one, which is the
  # fresh-install case -- there the default wallpaper goes through the full
  # theme-apply, since fuzzel, GTK and the terminal palette all descend from it
  # and would otherwise sit on stock defaults, waiting for someone to know that
  # running wpp is the fix.
  #
  # A user unit rather than a home.activation script, because caelestia only
  # writes hypr/scheme/current.lua when HYPRLAND_INSTANCE_SIGNATURE is set and
  # activation has no session to take it from -- the colours would land
  # everywhere except Hyprland's borders, silently. The sleep is for wayle:
  # `wallpaper set` is answered over D-Bus by the running shell, so it fails
  # against a service that has started but not yet registered. TimeoutStartSec
  # because a blocking unit in the login path wedges the whole switch with
  # nothing said about why.
  systemd.user.services.wallpaper-restore = {
    Unit = {
      Description = "Restore the wallpaper, theming the machine if it never has been";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" "wayle.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = toString (pkgs.writeShellScript "wallpaper-restore" ''
        set -eu
        sleep 3
        record=${wallpaperRecord}
        if [ -r "$record" ]; then
          wallpaper=$(cat "$record")
          if [ -e "$wallpaper" ]; then
            exec ${pkgs.wayle}/bin/wayle wallpaper set --fit fill "$wallpaper"
          fi
        fi
        exec ${themeApply}/bin/theme-apply ${defaultWallpaper}
      '');
      TimeoutStartSec = "60s";
      Slice = "session.slice";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # wpp reads this directory; the collection inside it is user data and is not
  # in the repo, but the directory existing is what keeps a fresh install from
  # looking like a broken one.
  home.file."Pictures/Wallpapers/.keep".text = "";

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
        # Departure Mono is drawn on a pixel grid, so it is sharpest when the
        # rendered size lands on whole pixels -- dpi-aware = no above is what
        # keeps that predictable, since letting fontconfig scale by DPI puts a
        # bitmap-styled face on fractional boundaries and softens it.
        #
        # The family is "DepartureMono Nerd Font", one word: the Nerd Font
        # build renames the family, so the upstream "Departure Mono" matches
        # nothing and falls through to the default monospace without a word.
        font = "DepartureMono Nerd Font:size=15";
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

  # nix-direnv is what makes `use flake` cheap: it caches the evaluated shell
  # and roots its store paths, so a dev shell survives `nix-collect-garbage`.
  # The fish hook comes from this module -- interactiveShellInit no longer
  # calls `direnv hook` itself.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
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
    # Wayle splits its configuration in two, which is what makes this one
    # safe to own from here when caelestia's shell.json was not: config.toml
    # is read and never written, while `wayle config set` and anything changed
    # in the GUI land in runtime.toml beside it. A read-only store symlink here
    # therefore breaks nothing.
    #
    # The catch is precedence -- runtime.toml wins. Verified by putting
    # matugen-scheme = "vibrant" here against "expressive" there and restarting:
    # expressive won. So a key that has ever been set at runtime shadows the
    # value declared below, silently and with nothing logged. When a change
    # here appears to do nothing, that file is the reason.
    #
    # config.toml.example in the same directory lists the full surface, and it
    # is 16 KB, so this covers only what is deliberately chosen.
    # force, because wayle writes a stub config.toml on first run if the file
    # is absent. Without it home-manager refuses to clobber that stub and the
    # whole switch fails at activation, which is a rebuild broken by a file
    # nothing has ever edited.
    "wayle/config.toml".force = true;
    "wayle/config.toml".text = ''
      # Managed by home-manager. Runtime overrides live in runtime.toml and
      # take precedence over everything here.

      [general]
      # "Google Sans Flex Rounded", not "Google Sans Rounded": every weight in
      # the package registers the shared family "Google Sans Flex" plus its own
      # "<Weight> Rounded" name, and the archive's name matches neither. A name
      # that matches nothing falls back to the default sans silently.
      font-sans = "Google Sans Flex Rounded"
      font-mono = "JetBrains Mono NF"
      tearing-mode = true

      # A bar that clears the screen edge on all sides, is rounded off and
      # casts a shadow, rather than a full-width strip welded to the bottom.
      # inset-* is what detaches it; rounding without them just rounds corners
      # that nothing can be seen behind.
      [bar]
      location = "left"
      scale = 0.95
      # Flush against the left edge and running the full height, rather than an
      # island. inset-edge is the gap from the attached edge and inset-ends the
      # gap at top and bottom; both at zero is what makes it a docked strip.
      # rounding and shadow come off with them -- a rounded corner against a
      # screen edge shows the desktop through the notch, and "floating" casts a
      # shadow on three sides that no longer have anything behind them.
      inset-edge = 0.0
      inset-ends = 0.0
      rounding = "none"
      shadow = "none"
      button-rounding = "full"

      # button-group-rounding defaults to "sm" and is easy to miss: with the
      # bar and the buttons both at "full", the grouped modules -- the systray
      # cluster especially -- kept visibly squarer corners than everything
      # around them.
      button-group-rounding = "full"

      # Zero, so the special-workspace buttons sit against the numbered ones
      # rather than a step apart from them. This is the gap inside a group;
      # module-gap, which still separates the whole cluster from
      # notifications, is a different setting.
      button-group-module-gap = 0.0

      # basic is "icon + label, minimal background". block-prefix, the default,
      # is "icon in colored pill container", which is the filled blob behind
      # every icon. Dropping to basic removes the container so the icon glyph
      # itself carries the colour.
      button-variant = "basic"

      # Workspaces were the thing missing. The left slot was empty, which is
      # most of why this read as a status strip rather than a shell.
      #
      # The slot names do not follow the orientation: on a vertical bar `left`
      # is the top section and `right` is the bottom. media is left out here
      # because a track title has nowhere to go in a column.
      #
      # A named group puts the special workspaces in the same container as the
      # numbered ones, so the run reads as one cluster: 1, 2, then whichever
      # overlays are up, then the gap before notifications. Membership of a
      # group is what makes button-group-module-gap apply to the join instead
      # of the bar's own module-gap. The container itself is hidden while
      # every module in it is, which is the usual state for all three.
      [[bar.layout]]
      monitor = "*"
      show = true
      left = [
          { name = "workspaces", modules = [
              "hyprland-workspaces",
              "custom-ws-music",
              "custom-ws-comms",
              "custom-ws-scratch",
          ] },
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
      rounding = "full"

      # This module numbers the ordinary workspaces and nothing else. It can
      # carry the special ones too -- show-special = true with an icon per
      # workspace in workspace-map -- but that map is keyed by workspace id,
      # and a special workspace's id is handed out in creation order:
      # newSpecialID() returns the highest live special id plus one, counting
      # up from -99. Which of music and communication is -98 therefore depends
      # on which was opened first that session, and the icons trade places.
      # The custom modules below address the same workspaces by name.
      #
      # min-workspace-count only fills in workspaces that a workspace rule
      # assigns to this bar's monitor; with monitor-specific on and no such
      # rules, the empty pills it would add are skipped and the bar shows the
      # workspaces that exist.
      [modules.hyprland-workspaces]
      show-special = false
      min-workspace-count = 4
      display-mode = "label"
      workspace-padding = 0.6

      # One button per special workspace, each present only while its overlay
      # holds something: an empty special workspace is not a workspace
      # Hyprland lists, so special-ws answers 0 and hide-if-empty takes the
      # button away. Nothing here runs while Spotify or Discord are closed,
      # and no button can be clicked into an empty overlay.
      #
      # class-format turns the other two answers into the CSS classes ws-idle
      # and ws-open, and styles/index.scss gives ws-open the same filled
      # accent circle the active numbered workspace gets. The class lands on
      # the module's root box, so the selector reaches through it to the
      # button.
      #
      # Clicking toggles rather than focuses, so a second click puts the
      # overlay away. The workspaces module has no click action to configure
      # -- it always focuses -- which is the other half of why these are
      # custom modules rather than workspace-map entries.
      #
      # The icons are among the 362 the package carries in share/icons.
      # `wayle icons list` reports none installed regardless: it counts only
      # ~/.local/share/wayle/icons, where `wayle icons install` puts what it
      # pulls from a CDN. An icon in neither place draws nothing at all.
      # mode = "watch" spawns the command once and takes a display update from
      # every line it prints, so these follow Hyprland's event socket at the
      # speed the numbered workspaces do. interval-ms means nothing here.
      # restart-policy covers the socket going away with the compositor: the
      # delay it retries on backs off exponentially, so a shell that outlives
      # a Hyprland restart reconnects without spinning.
      [[modules.custom]]
      id = "ws-music"
      command = "special-ws watch music"
      mode = "watch"
      restart-policy = "on-exit"
      icon-name = "ld-music-symbolic"
      label-show = false
      hide-if-empty = true
      class-format = "ws-{{ output }}"
      left-click = "special-ws toggle music"

      [[modules.custom]]
      id = "ws-comms"
      command = "special-ws watch communication"
      mode = "watch"
      restart-policy = "on-exit"
      icon-name = "ld-message-circle-symbolic"
      label-show = false
      hide-if-empty = true
      class-format = "ws-{{ output }}"
      left-click = "special-ws toggle communication"

      [[modules.custom]]
      id = "ws-scratch"
      command = "special-ws watch special"
      mode = "watch"
      restart-policy = "on-exit"
      icon-name = "ld-layers-symbolic"
      label-show = false
      hide-if-empty = true
      class-format = "ws-{{ output }}"
      left-click = "special-ws toggle special"

      # A vertical bar is as wide as its widest module, and the clock defaults
      # to "%a %b %d %I:%M %p" -- "Sun Aug 09 06:46 PM", about nineteen
      # characters, which was setting the width for everything else. %H:%M is
      # five, and 24-hour drops the AM/PM suffix along with the date.
      # Hours over minutes on two lines. TOML reads the \n in a basic string as
      # a real newline before wayle ever sees it, so this is one string with a
      # break in it rather than an escape wayle has to interpret.
      [modules.clock]
      format = "%H\n%M"

      [modules.bluetooth]
      label-show = false

      # The icons already say these; the text was width for nothing. Volume
      # keeps its percentage because the number is the point there.
      [modules.network]
      label-show = false

      # Each module carries a semantic colour and icon-color = auto resolves to
      # it, so audio defaults to red where network is accent and bluetooth is
      # blue. With button-variant = basic there is no pill covering that, and
      # the glyphs sit in the bar two hues away from their neighbours. Naming
      # accent explicitly is what overrides auto.
      #
      # Neither audio module shows a label, so the icon is the whole reading
      # and label-color would style nothing.
      [modules.microphone]
      label-show = false
      icon-color = "accent"

      [modules.volume]
      label-show = false
      icon-color = "accent"

      [wallpaper]
      transition-fps = 240
    '';

    # Wayle compiles styles/index.scss with grass and appends it to its own
    # stylesheet, so a rule here is last and wins on equal specificity without
    # a priority to set. A file that fails to compile is logged and dropped,
    # leaving the rest of the bundle intact -- so a mistake here costs these
    # colours, not the bar. force for the same reason config.toml has it: the
    # settings GUI scaffolds this path on first run.
    #
    # A custom module's dynamic classes land on its root box, one level above
    # the button that carries the background, and the colours come from the
    # palette tokens rather than --ws-active-color, which is scoped to
    # .workspaces and does not reach out here. accent and fg-on-accent are
    # what the workspaces module resolves its own active colours to.
    "wayle/styles/index.scss".force = true;
    "wayle/styles/index.scss".text = ''
      .custom.ws-open menubutton.bar-button > button.toggle {
          background-color: var(--accent);
      }

      .custom.ws-open menubutton.bar-button > button.toggle image {
          color: var(--fg-on-accent);
      }
    '';

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
