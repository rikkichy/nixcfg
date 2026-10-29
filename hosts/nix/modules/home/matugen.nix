{ config, pkgs, lib, equicordDataDir, spotifyPaletteTemplate, ... }:

let
  terminalColours = "${config.xdg.stateHome}/theme/terminal-colors.conf";

  template = input: output: {
    input_path = "${input}";
    output_path = output;
  };
  matugenConfig = (pkgs.formats.toml {}).generate "matugen-config.toml" {
    config.source_color_index = 0;
    templates = let cfg = config.xdg.configHome; in {
      quickshell = template ../../dotfiles/ricing/matugen/templates/quickshell.json "${cfg}/quickshell/colors.json";
      gtk3 = template ../../dotfiles/ricing/matugen/templates/gtk.css "${cfg}/gtk-3.0/gtk.css";
      gtk4 = template ../../dotfiles/ricing/matugen/templates/gtk.css "${cfg}/gtk-4.0/gtk.css";
      thunar3 = template ../../dotfiles/ricing/matugen/templates/thunar.css "${cfg}/gtk-3.0/thunar.css";
      thunar4 = template ../../dotfiles/ricing/matugen/templates/thunar.css "${cfg}/gtk-4.0/thunar.css";
      hypr = template ../../dotfiles/ricing/matugen/templates/hypr-scheme.lua "${cfg}/hypr/scheme/current.lua";
      terminal = template ../../../../common/dotfiles/matugen/templates/terminal-colors.conf terminalColours;
      btop = template ../../../../common/dotfiles/matugen/templates/btop.theme "${cfg}/btop/themes/wallpaper.theme" // {
        post_hook = "${pkgs.psmisc}/bin/killall -USR2 btop 2>/dev/null || true";
      };
      nvtop = template ../../dotfiles/ricing/matugen/templates/nvtop.colors "${cfg}/nvtop/nvtop.colors";
      qt = template ../../dotfiles/ricing/matugen/templates/qt.colors "${cfg}/qtengine/scheme.colors";
      discord = template ../../../../common/dotfiles/matugen/templates/discord-palette.css "${equicordDataDir}/settings/quickCss.css";
      spotify = spotifyPaletteTemplate;
      obsidian = template ../../dotfiles/ricing/matugen/templates/obsidian.css "${cfg}/obsidian/matugen.css";
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

  defaultWallpaper = ../../dotfiles/ricing/default-wallpaper.png;

  wallpaperRecord = lib.escapeShellArg "${config.xdg.stateHome}/wallpaper/current";
  animatedRecord = lib.escapeShellArg "${config.xdg.stateHome}/wallpaper/animated";
  animatedCache = lib.escapeShellArg "${config.xdg.cacheHome}/animated-wallpaper";

  themeApply = pkgs.writeShellApplication {
    name = "theme-apply";
    runtimeInputs = [ pkgs.matugen termSequences ];
    text = ''
      wallpaper="''${1:?usage: theme-apply <image>}"
      record=${wallpaperRecord}

      matugen image "$wallpaper" \
        --type scheme-content \
        --mode dark \
        --config ${matugenConfig}

      term-sequences

      mkdir -p "$(dirname "$record")"
      printf '%s\n' "$wallpaper" > "$record"
    '';
  };

  wallpaperFrame = pkgs.writeShellApplication {
    name = "wallpaper-frame";
    runtimeInputs = [ pkgs.ffmpeg pkgs.coreutils ];
    text = ''
      mode=full
      case "''${1-}" in
        --preview-image|--preview-video) mode="$1"; shift ;;
      esac
      video="''${1:?usage: wallpaper-frame [--preview-image|--preview-video] SOURCE OUTPUT}"
      output="''${2:?usage: wallpaper-frame [--preview-image|--preview-video] SOURCE OUTPUT}"
      seek=(-ss 3)
      decode=()
      encode=()
      extension=png
      if [ "$mode" != full ]; then
        extension=jpg
        encode=(-vf scale=640:360:force_original_aspect_ratio=decrease:out_range=full -pix_fmt yuvj420p -q:v 3)
        if [ "$mode" = --preview-image ]; then
          seek=()
        else
          decode=(-skip_frame nokey)
        fi
      fi
      if [ -s "$output" ] && [ ! "$video" -nt "$output" ]; then
        exit 0
      fi
      parent="''${output%/*}"
      mkdir -p -- "$parent"
      tmp=$(mktemp "$parent/.frame.XXXXXX.$extension")
      trap 'rm -f -- "$tmp"' EXIT
      if ! ffmpeg -y -loglevel error -filter_threads 1 "''${decode[@]}" "''${seek[@]}" \
        -threads 1 -i "$video" -frames:v 1 -threads 1 "''${encode[@]}" "$tmp" < /dev/null; then
        [ "$mode" = --preview-video ] || exit 1
        rm -f -- "$tmp"
      fi
      if [ ! -s "$tmp" ]; then
        ffmpeg -y -loglevel error -filter_threads 1 -threads 1 -i "$video" \
          -frames:v 1 -threads 1 "''${encode[@]}" "$tmp" < /dev/null || exit 1
      fi
      [ -s "$tmp" ] || exit 1
      mv -- "$tmp" "$output"
    '';
  };

  awpApply = pkgs.writeShellApplication {
    name = "awp-apply";
    runtimeInputs = [ wallpaperFrame pkgs.coreutils pkgs.systemd pkgs.awww themeApply ];
    text = ''
      video="''${1:?usage: awp-apply <video>}"
      record=${animatedRecord}
      cache=${animatedCache}
      key=$(printf '%s' "$video" | sha256sum)
      frame="$cache/''${key%% *}.png"

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
      icon = "accessories-image-viewer";
      terminal = false;
      categories = [ "System" ];
      settings.OnlyShowIn = "X-DesktopTools;";
    };
    awpp = {
      name = "Animated wallpaper";
      exec = "awpp";
      icon = "totem";
      terminal = false;
      categories = [ "System" ];
      settings.OnlyShowIn = "X-DesktopTools;";
    };
  };

  home.packages = lib.mkAfter (with pkgs; [
    (writeShellApplication {
      name = "wpp";
      runtimeInputs = [
        quickshell
        jq
        coreutils
        findutils
        systemd
        awww
        themeApply
      ];
      text = ''
        case "$#:''${1-}" in
          0:) dir="''${WALLPAPER_DIR:-$HOME/Pictures/Wallpapers}" ;;
          2:--list) dir="$2" ;;
          3:--apply|3:--preview) chosen="$2"; dir="$3" ;;
          *) printf 'usage: wpp [--list DIRECTORY | --preview PATH DIRECTORY | --apply PATH DIRECTORY]\n' >&2; exit 2 ;;
        esac
        IFS= read -r -d "" dir < <(realpath -m -z -- "$dir")
        if [ "$#" -eq 0 ]; then
          exec quickshell -c expressive ipc call desktop wallpaper wallpapers "$dir"
        fi

        mapfile -d "" -t files < <(find "$dir" -maxdepth 1 -type f \
          \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
          -printf '%p\0%T@:%s\0' 2>/dev/null)
        empty=false
        if [ "''${#files[@]}" -eq 0 ]; then
          empty=true
          files=(${defaultWallpaper} builtin)
        fi

        cache="''${XDG_CACHE_HOME:-${config.xdg.cacheHome}}/wallpaper/thumbs/v2"
        IFS= read -r -d "" cache < <(realpath -m -z -- "$cache")
        key=$(printf '%s' "$dir" | sha256sum)
        cache="$cache/''${key%% *}"

        if [ "$1" = --list ]; then
          for ((i = 0; i < ''${#files[@]}; i += 2)); do
            f="''${files[$i]}"
            revision="''${files[$((i + 1))]}"
            preview="$cache/''${f##*/}/$revision.jpg"
            if [ ! -s "$preview" ] || [ "$f" -nt "$preview" ]; then preview=""; fi
            printf '%s\0%s\0%s\0' "$f" "$revision" "$preview"
          done | jq -Rs --argjson builtin "$empty" '
            [split("\u0000") | .[:-1] | range(0; length; 3) as $i |
              {name: (if $builtin then "Built-in default" else .[$i] | split("/")[-1] end),
               path: .[$i], preview: .[$i + 2], revision: .[$i + 1]}] | sort_by(.path)'
          exit 0
        fi

        valid=false
        for ((i = 0; i < ''${#files[@]}; i += 2)); do
          f="''${files[$i]}"
          if [ "$chosen" = "$f" ] && [ -f "$f" ] && [ ! -L "$f" ]; then
            valid=true
            break
          fi
        done
        if ! "$valid"; then
          printf 'wpp: Selection is no longer in %s\n' "$dir" >&2
          exit 1
        fi
        if [ "$1" = --preview ]; then
          preview="$cache/''${chosen##*/}/''${files[$((i + 1))]}.jpg"
          ${wallpaperFrame}/bin/wallpaper-frame --preview-image "$chosen" "$preview"
          jq -n --arg preview "$preview" '{preview: $preview}'
          exit 0
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
        quickshell
        jq
        coreutils
        findutils
        awpApply
      ];
      text = ''
        case "$#:''${1-}" in
          0:) dir="''${ANIMATED_WALLPAPER_DIR:-$HOME/Videos/Animated Wallpapers}" ;;
          2:--list) dir="$2" ;;
          3:--apply|3:--preview) chosen="$2"; dir="$3" ;;
          *) printf 'usage: awpp [--list DIRECTORY | --preview PATH DIRECTORY | --apply PATH DIRECTORY]\n' >&2; exit 2 ;;
        esac
        IFS= read -r -d "" dir < <(realpath -m -z -- "$dir")
        if [ "$#" -eq 0 ]; then
          exec quickshell -c expressive ipc call desktop wallpaper animated-wallpapers "$dir"
        fi

        die() {
          echo "awpp: $1" >&2
          exit 1
        }

        mapfile -d "" -t files < <(find "$dir" -maxdepth 1 -type f \
          \( -iname '*.mp4' -o -iname '*.webm' -o -iname '*.mkv' \
             -o -iname '*.mov' -o -iname '*.gif' \) \
          -printf '%p\0%T@:%s\0' 2>/dev/null)

        [ "''${#files[@]}" -gt 0 ] || die "No videos in $dir"

        cache="''${XDG_CACHE_HOME:-${config.xdg.cacheHome}}/animated-wallpaper/thumbs/v2"
        IFS= read -r -d "" cache < <(realpath -m -z -- "$cache")
        key=$(printf '%s' "$dir" | sha256sum)
        cache="$cache/''${key%% *}"

        if [ "$1" = --list ]; then
          for ((i = 0; i < ''${#files[@]}; i += 2)); do
            f="''${files[$i]}"
            revision="''${files[$((i + 1))]}"
            preview="$cache/''${f##*/}/$revision.jpg"
            if [ ! -s "$preview" ] || [ "$f" -nt "$preview" ]; then preview=""; fi
            printf '%s\0%s\0%s\0' "$f" "$revision" "$preview"
          done | jq -Rs '
            [split("\u0000") | .[:-1] | range(0; length; 3) as $i |
              {name: (.[$i] | split("/")[-1] | sub("\\.[^.]*$"; "")),
               path: .[$i], preview: .[$i + 2], revision: .[$i + 1]}] | sort_by(.path)'
          exit 0
        fi

        for ((i = 0; i < ''${#files[@]}; i += 2)); do
          f="''${files[$i]}"
          if [ "$chosen" = "$f" ] && [ -f "$f" ] && [ ! -L "$f" ]; then
            if [ "$1" = --preview ]; then
              preview="$cache/''${chosen##*/}/''${files[$((i + 1))]}.jpg"
              ${wallpaperFrame}/bin/wallpaper-frame --preview-video "$chosen" "$preview" \
                || die "Could not preview $chosen"
              jq -n --arg preview "$preview" '{preview: $preview}'
              exit 0
            fi
            exec awp-apply "$chosen"
          fi
        done
        die "Selection is no longer in $dir"
      '';
    })
  ]);

  services.awww.enable = true;

  systemd.user.services.awww = {
    Unit = {
      Before = [ "wallpaper-restore.service" ];
    };
    Service = {
      # User-unit mount protections require an unprivileged user namespace.
      PrivateUsers = true;
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      PrivateTmp = true;
      NoNewPrivileges = true;
      CapabilityBoundingSet = "";
      AmbientCapabilities = "";
      RestrictAddressFamilies = [ "AF_UNIX" ];
      Environment = [ "XDG_CACHE_HOME=${config.xdg.cacheHome}" ];
      # Only this trusted mkdir runs outside the mount sandbox, before its bind paths exist.
      ExecStartPre = "+${pkgs.coreutils}/bin/mkdir -p -- ${lib.escapeShellArg "${config.xdg.cacheHome}/awww"}";
      ReadWritePaths = [
        "${config.xdg.cacheHome}/awww"
        # awww creates/removes its display-named IPC socket directly in XDG_RUNTIME_DIR.
        "%t"
      ];
      InaccessiblePaths = [
        "-${config.home.homeDirectory}/.ssh"
        "-${config.home.homeDirectory}/.gnupg"
        "-${config.xdg.configHome}/sops"
        "-/run/secrets"
        "-/run/secrets-for-users"
        "-%t/gnupg"
        "-%t/keyring"
      ];
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
          saved=$(cat "$record" && printf '.')
          saved=''${saved%.}
          saved=''${saved%$'\n'}
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
        video=$(cat ${animatedRecord} && printf '.')
        video=''${video%.}
        video=''${video%$'\n'}
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
  };
}
