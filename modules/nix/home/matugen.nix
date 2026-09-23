{ config, pkgs, lib, desktopPicker, ... }:

let
  terminalColours = "${config.xdg.stateHome}/theme/terminal-colors.conf";
  cursorColours = "${config.xdg.stateHome}/theme/cursor.conf";
  cursorTheme = "Bibata-Material-Dynamic";
  cursorDir = "${config.xdg.dataHome}/icons/${cursorTheme}";

  discordTheme = pkgs.runCommand "wallpaper.theme.css" { } ''
    cat ${
      pkgs.writeText "discord-theme-meta.css" ''
        /**
         * @name Wallpaper
         * @description Midnight, coloured from the current wallpaper by matugen.
         * @author refact0r
         * @website https://github.com/refact0r/midnight-discord
        */
      ''
    } > $out
    sed '/fonts\.googleapis\.com/d' ${pkgs.midnight-discord} >> $out
    cat ${../../../dotfiles/nix/discord/theme.css} >> $out
  '';

  template = input: output: {
    input_path = "${input}";
    output_path = output;
  };
  matugenConfig = (pkgs.formats.toml {}).generate "matugen-config.toml" {
    config.source_color_index = 0;
    templates = let cfg = config.xdg.configHome; in {
      fuzzel = template ../../../dotfiles/nix/matugen/templates/fuzzel.ini "${cfg}/fuzzel/colors.ini";
      quickshell = template ../../../dotfiles/nix/matugen/templates/quickshell.json "${cfg}/quickshell/colors.json";
      gtk3 = template ../../../dotfiles/nix/matugen/templates/gtk.css "${cfg}/gtk-3.0/gtk.css";
      gtk4 = template ../../../dotfiles/nix/matugen/templates/gtk.css "${cfg}/gtk-4.0/gtk.css";
      thunar3 = template ../../../dotfiles/nix/matugen/templates/thunar.css "${cfg}/gtk-3.0/thunar.css";
      thunar4 = template ../../../dotfiles/nix/matugen/templates/thunar.css "${cfg}/gtk-4.0/thunar.css";
      hypr = template ../../../dotfiles/nix/matugen/templates/hypr-scheme.lua "${cfg}/hypr/scheme/current.lua";
      terminal = template ../../../dotfiles/common/matugen/templates/terminal-colors.conf terminalColours;
      btop = template ../../../dotfiles/common/matugen/templates/btop.theme "${cfg}/btop/themes/wallpaper.theme" // {
        post_hook = "${pkgs.psmisc}/bin/killall -USR2 btop 2>/dev/null || true";
      };
      nvtop = template ../../../dotfiles/nix/matugen/templates/nvtop.colors "${cfg}/nvtop/nvtop.colors";
      qt = template ../../../dotfiles/nix/matugen/templates/qt.colors "${cfg}/qtengine/scheme.colors";
      cursor = template ../../../dotfiles/nix/matugen/templates/cursor.conf cursorColours;
      discord = template ../../../dotfiles/nix/matugen/templates/discord-palette.css "${cfg}/Equicord/settings/quickCss.css";
    };
  };

  termSequences = pkgs.writeShellApplication {
    name = "term-sequences";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      colours=${terminalColours}
      [ -r "$colours" ] || exit 0

      declare -A seen=()
      out=""
      while IFS='=' read -r key value || [[ -n "$key" ]]; do
        case "$key" in
          foreground) slot=10 ;;
          background) slot=11 ;;
          cursor) slot=12 ;;
          selection) slot=17 ;;
          color[0-9]|color1[0-8]) slot="4;''${key#color}" ;;
          *) continue ;;
        esac
        [[ "$value" =~ ^[[:xdigit:]]{6}$ ]] || {
          printf 'Invalid terminal colour: %s\n' "$key" >&2
          exit 1
        }
        [[ -v seen[$key] ]] && continue
        seen[$key]=1
        printf -v sequence '\033]%s;rgb:%s/%s/%s\033\x5c' \
          "$slot" "''${value:0:2}" "''${value:2:2}" "''${value:4:2}"
        out+="$sequence"
      done < "$colours"

      mkdir -p "$(dirname "$colours")"
      printf '%s' "$out" > "$(dirname "$colours")/sequences.txt"

      for pt in /dev/pts/[0-9]*; do
        [ -w "$pt" ] || continue
        printf '%s' "$out" > "$pt" 2>/dev/null || true
      done
    '';
  };

  cursorApply = pkgs.writeShellApplication {
    name = "cursor-apply";
    runtimeInputs = [ pkgs.bibata-material-cursor pkgs.gnused ];
    text = ''
      colours=${cursorColours}
      [ -r "$colours" ] || exit 0

      accent=$(sed -n "s/^accent=//p" "$colours" | head -1)
      [ -n "$accent" ] || exit 0

      bibata-material-render "$accent" ${cursorDir} hypr
      hyprctl setcursor ${cursorTheme} "''${XCURSOR_SIZE:-24}" >/dev/null 2>&1 || true

      bibata-material-render "$accent" ${cursorDir} x11
    '';
  };

  defaultWallpaper = ../../../dotfiles/nix/default-wallpaper.png;

  wallpaperRecord = lib.escapeShellArg "${config.xdg.stateHome}/wallpaper/current";
  animatedRecord = lib.escapeShellArg "${config.xdg.stateHome}/wallpaper/animated";
  animatedCache = lib.escapeShellArg "${config.xdg.cacheHome}/animated-wallpaper";

  themeApply = pkgs.writeShellApplication {
    name = "theme-apply";
    runtimeInputs = [ pkgs.matugen termSequences cursorApply ];
    text = ''
      wallpaper="''${1:?usage: theme-apply <image>}"
      record=${wallpaperRecord}

      matugen image "$wallpaper" \
        --type scheme-content \
        --mode dark \
        --config ${matugenConfig}

      term-sequences
      cursor-apply

      mkdir -p "$(dirname "$record")"
      printf '%s\n' "$wallpaper" > "$record"
    '';
  };

  wallpaperFrame = pkgs.writeShellApplication {
    name = "wallpaper-frame";
    runtimeInputs = [ pkgs.ffmpeg pkgs.coreutils ];
    text = ''
      video="''${1:?usage: wallpaper-frame VIDEO OUTPUT [FFMPEG_OUTPUT_ARGUMENT ...]}"
      output="''${2:?usage: wallpaper-frame VIDEO OUTPUT [FFMPEG_OUTPUT_ARGUMENT ...]}"
      shift 2
      if [ -s "$output" ] && [ ! "$video" -nt "$output" ]; then
        exit 0
      fi
      mkdir -p "$(dirname "$output")"
      tmp=$(mktemp "$(dirname "$output")/.frame.XXXXXX.png")
      trap 'rm -f -- "$tmp"' EXIT
      ffmpeg -y -loglevel error -ss 3 -i "$video" -frames:v 1 "$@" "$tmp" \
        < /dev/null || exit 1
      if [ ! -s "$tmp" ]; then
        ffmpeg -y -loglevel error -i "$video" -frames:v 1 "$@" "$tmp" \
          < /dev/null || exit 1
      fi
      [ -s "$tmp" ] || exit 1
      mv -- "$tmp" "$output"
    '';
  };

  awpApply = pkgs.writeShellApplication {
    name = "awp-apply";
    runtimeInputs = [ wallpaperFrame pkgs.systemd pkgs.awww themeApply ];
    text = ''
      video="''${1:?usage: awp-apply <video>}"
      record=${animatedRecord}
      cache=${animatedCache}
      frame="$cache/''${video##*/}.png"

      wallpaper-frame "$video" "$frame"

      mkdir -p "$(dirname "$record")"
      printf '%s\n' "$video" > "$record"
      systemctl --user restart animated-wallpaper.service

      # Playback does not depend on palette or cursor generation.
      awww img --resize crop --transition-type none "$frame"
      theme-apply "$frame"
    '';
  };
in
{
  _module.args.terminalColours = terminalColours;

  xdg.desktopEntries = {
    wpp = {
      name = "Wallpaper";
      exec = "wpp";
      icon = "preferences-desktop-wallpaper";
      terminal = false;
      categories = [ "System" ];
      settings.OnlyShowIn = "X-DesktopTools;";
    };
    awpp = {
      name = "Animated wallpaper";
      exec = "awpp";
      icon = "applications-multimedia";
      terminal = false;
      categories = [ "System" ];
      settings.OnlyShowIn = "X-DesktopTools;";
    };
  };

  home.packages = lib.mkAfter (with pkgs; [
    (writeShellApplication {
      name = "wpp";
      runtimeInputs = [
        desktopPicker
        coreutils
        findutils
        libnotify
        systemd
        awww
        themeApply
      ];
      text = ''
        dir="''${WALLPAPER_DIR:-$HOME/Pictures/Wallpapers}"
        cache="''${XDG_CACHE_HOME:-$HOME/.cache}/wallpaper-picker"

        mapfile -t files < <(find "$dir" -maxdepth 1 -type f \
          \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
          2>/dev/null | sort)

        if [ "''${#files[@]}" -eq 0 ]; then
          notify-send -a wpp "Wallpaper" \
            "No images in $dir — applied the built-in default" 2>/dev/null || true
          chosen=${defaultWallpaper}
        else
          mkdir -p "$cache"
          for f in "''${files[@]}"; do
            base="''${f##*/}"
            thumb="$cache/$base.png"
            if [ ! -s "$thumb" ] || [ "$f" -nt "$thumb" ]; then
              printf '%s\0%s\0' "$f" "$thumb"
            fi
          done | xargs -0 -r -n 2 -P 4 ${pkgs.writeShellScript "wallpaper-thumbnail" ''
            ${pkgs.gdk-pixbuf}/bin/gdk-pixbuf-thumbnailer -s 128 "$1" "$2" || true
          ''}

        idx=$(
          for f in "''${files[@]}"; do
            base="''${f##*/}"
            printf '%s\x00icon\x1f%s\n' "$base" "$cache/$base.png"
          done | desktop-picker --index --prompt "wp> " \
            --font "Google Sans Flex Rounded:size=17" --line-height=64px --lines 8
        ) || exit 0

        count=''${#files[@]}
        [[ "$idx" =~ ^(0|[1-9][0-9]*)$ ]] || exit 0
        (( ''${#idx} <= ''${#count} )) || exit 0
        (( idx < count )) || exit 0

        chosen="''${files[$idx]}"
        fi

        awww img --resize crop --transition-type none "$chosen"
        systemctl --user stop animated-wallpaper.service
        rm -f ${animatedRecord}
        theme-apply "$chosen"
      '';
    })

    (writeShellApplication {
      name = "awpp";
      runtimeInputs = [
        desktopPicker
        coreutils
        findutils
        libnotify
        awpApply
      ];
      text = ''
        dir="''${ANIMATED_WALLPAPER_DIR:-$HOME/Videos/Animated Wallpapers}"
        cache=${animatedCache}/thumbs

        die() {
          echo "awpp: $1" >&2
          notify-send -a awpp "Animated wallpaper" "$1" 2>/dev/null || true
          exit 1
        }

        mapfile -t files < <(find "$dir" -maxdepth 1 -type f \
          \( -iname '*.mp4' -o -iname '*.webm' -o -iname '*.mkv' \
             -o -iname '*.mov' -o -iname '*.gif' \) \
          2>/dev/null | sort)

        [ "''${#files[@]}" -gt 0 ] || die "No videos in $dir"

        mkdir -p "$cache"

        for f in "''${files[@]}"; do
          thumb="$cache/''${f##*/}.png"
          if [ ! -s "$thumb" ] || [ "$f" -nt "$thumb" ]; then
            printf '%s\0%s\0' "$f" "$thumb"
          fi
        done | xargs -0 -r -n 2 -P 4 ${pkgs.writeShellScript "animated-wallpaper-thumbnail" ''
          ${wallpaperFrame}/bin/wallpaper-frame "$1" "$2" -vf scale=256:-2 || true
        ''}

        idx=$(
          for f in "''${files[@]}"; do
            base="''${f##*/}"
            printf '%s\x00icon\x1f%s\n' "''${base%.*}" "$cache/$base.png"
          done | desktop-picker --index --prompt "awp> " \
            --font "Google Sans Flex Rounded:size=17" --line-height=64px --lines 8
        ) || exit 0

        count=''${#files[@]}
        [[ "$idx" =~ ^(0|[1-9][0-9]*)$ ]] || exit 0
        (( ''${#idx} <= ''${#count} )) || exit 0
        (( idx < count )) || exit 0

        awp-apply "''${files[$idx]}"
      '';
    })
  ]);

  services.awww.enable = true;

  systemd.user.services.awww = {
    Unit = {
      Before = [ "wallpaper-restore.service" ];
    };
    Service = {
      ExecStartPost = toString (pkgs.writeShellScript "awww-ready" ''
        for attempt in $(${pkgs.coreutils}/bin/seq 1 100); do
          ${pkgs.awww}/bin/awww query >/dev/null 2>&1 && exit 0
          ${pkgs.coreutils}/bin/sleep 0.1
        done
        exit 1
      '');
      Slice = "session.slice";
    };
  };

  systemd.user.services.wallpaper-restore = {
    Unit = {
      Description = "Restore the wallpaper and regenerate application palettes";
      PartOf = [ "graphical-session.target" ];
      Requires = [ "awww.service" ];
      After = [ "graphical-session.target" "awww.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = toString (pkgs.writeShellScript "wallpaper-restore" ''
        set -eu
        record=${wallpaperRecord}
        wallpaper=${defaultWallpaper}
        if [ -r "$record" ]; then
          saved=$(cat "$record")
          [ ! -e "$saved" ] || wallpaper="$saved"
        fi
        ${pkgs.awww}/bin/awww img --resize crop --transition-type none "$wallpaper"
        exec ${themeApply}/bin/theme-apply "$wallpaper"
      '');
      TimeoutStartSec = "60s";
      Slice = "session.slice";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.animated-wallpaper = {
    Unit = {
      Description = "Play the animated wallpaper";
      ConditionFileNotEmpty = "${config.xdg.stateHome}/wallpaper/animated";
      PartOf = [ "graphical-session.target" ];
      After = [
        "graphical-session.target"
        "awww.service"
      ];
    };
    Service = {
      ExecStart = toString (pkgs.writeShellScript "animated-wallpaper" ''
        set -eu
        video=$(cat ${animatedRecord})
        [ -e "$video" ] || exit 0
        exec ${pkgs.mpvpaper}/bin/mpvpaper -p -l bottom \
          -o "no-audio loop-file=inf hwdec=auto panscan=1.0" '*' "$video"
      '');
      Restart = "on-failure";
      RestartSec = "5s";
      Slice = "session.slice";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  xdg.configFile = {
    "matugen/config.toml".source = matugenConfig;
    "Equicord/themes/wallpaper.theme.css" = {
      source = discordTheme;
      force = true;
    };
  };
}
