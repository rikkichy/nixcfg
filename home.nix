{ config, pkgs, lib, inputs, nixcfgPath, ... }:

let

  helium = inputs.helium.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # Where the generated terminal palette lands. term-sequences reads it back;
  # it is state rather than config because nothing but that script consumes it.
  terminalColours = "${config.xdg.stateHome}/theme/terminal-colors.conf";

  # The accent the cursor is rendered from, and the theme it is rendered into.
  # State for the same reason the terminal palette is: cursor-apply is the only
  # thing that reads either.
  #
  # The theme name never changes -- only what is inside it -- which is what
  # lets hypr/ name it once, in vars.cursorTheme, and set XCURSOR_THEME and the
  # two gsettings keys from there at startup. A name that moved with the
  # wallpaper would leave all three naming the previous rendering.
  cursorColours = "${config.xdg.stateHome}/theme/cursor.conf";
  cursorTheme = "Bibata-Material-Dynamic";
  cursorDir = "${config.xdg.dataHome}/icons/${cursorTheme}";

  # matugen renders these against the palette it derives from the wallpaper,
  # writing each one straight into place. None of the outputs can be owned by
  # xdg.configFile: they are rewritten on every wallpaper change, and a
  # read-only store symlink would fail the write every time.
  #
  # gtk.css and thunar.css go to both gtk-3.0 and gtk-4.0 because gtk.css
  # @imports thunar.css by relative name, so the pair has to sit together in
  # each directory.
  #
  # The hypr scheme is written through ~/.config/hypr, which is an out-of-store
  # symlink to this repo, so the file lands in the working tree and stays
  # writable. That is the whole reason hypr/ is mapped in rather than copied.
  # The Equicord theme: Midnight, with the half of this machine's
  # configuration that does not follow the wallpaper appended to it. The
  # colours are not in here. They are rendered into Equicord's QuickCSS
  # instead, which is what keeps a wallpaper change from flashing the client
  # unstyled: a theme file arrives in the renderer as
  # `@import url("vencord:///themes/<name>?v=<timestamp>")`, and any change to
  # any theme rewrites that <style> element's whole content with a fresh
  # stamp, dropping every theme until the import resolves. Nothing rewrites
  # this file, so nothing triggers that.
  #
  # It is built rather than tracked because Midnight arrives as a store path,
  # which a tracked file would have to name and then go stale on. Concatenated
  # rather than @imported because Equicord hands a theme's text to a page
  # served from https://discord.com, where a file:// subresource is refused by
  # the renderer whatever the CSP says -- and the URL the theme documents
  # importing is fetched afresh at every start.
  #
  # The meta block has to be the first thing in the file: Equicord reads the
  # name and description out of it, and shows the filename for a theme that
  # has none.
  # The line dropped from Midnight is its webfont @import. Both faces the
  # overrides name are installed, so it fetches a font nothing then asks for --
  # at every Discord start, since a theme's CSS is parsed fresh each time.
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
    cat ${./dotfiles/discord/theme.css} >> $out
  '';

  matugenConfig = pkgs.writeText "matugen-config.toml" (
    let
      templates = ./dotfiles/matugen/templates;
      cfg = "${config.home.homeDirectory}/.config";
      entryPath = name: input: output: ''
        [templates.${name}]
        input_path = '${input}'
        output_path = '${output}'
      '';
      entry = name: input: entryPath name "${templates}/${input}";
    in
    ''
      [config]

    ''
    + entry "fuzzel" "fuzzel.ini" "${cfg}/fuzzel/fuzzel.ini"
    + entry "gtk3" "gtk.css" "${cfg}/gtk-3.0/gtk.css"
    + entry "gtk4" "gtk.css" "${cfg}/gtk-4.0/gtk.css"
    + entry "thunar3" "thunar.css" "${cfg}/gtk-3.0/thunar.css"
    + entry "thunar4" "thunar.css" "${cfg}/gtk-4.0/thunar.css"
    + entry "hypr" "hypr-scheme.lua" "${cfg}/hypr/scheme/current.lua"
    + entry "terminal" "terminal-colors.conf" terminalColours
    + entry "btop" "btop.theme" "${cfg}/btop/themes/wallpaper.theme"
    + entry "nvtop" "nvtop.colors" "${cfg}/nvtop/nvtop.colors"
    + entry "qt" "qt.colors" "${cfg}/qtengine/scheme.colors"
    + entry "cursor" "cursor.conf" cursorColours
    + entry "halrune" "halrune.svg" "${config.xdg.dataHome}/icons/hicolor/scalable/apps/halrune.svg"
    + entry "discord" "discord-palette.css" "${cfg}/Equicord/settings/quickCss.css"
  );

  # Pushes the generated palette at every terminal that will take it. foot
  # carries no colours of its own, so without this it sits on its stock palette
  # while everything else follows the wallpaper.
  #
  # /dev/pts is walked directly rather than /proc/*/fd: the sequences are
  # harmless to anything that is not a terminal, but a blocking open on a pty
  # whose reader has gone away would hang the whole theme run, hence O_NONBLOCK
  # and a failure that is ignored per-terminal rather than fatal.
  termSequences = pkgs.writeShellApplication {
    name = "term-sequences";
    runtimeInputs = [ pkgs.coreutils pkgs.gnused ];
    text = ''
      colours=${terminalColours}
      [ -r "$colours" ] || exit 0

      # hex -> the OSC form terminals expect: ESC ] <slots> ; rgb:RR/GG/BB ST,
      # where ST is ESC followed by a backslash. That backslash is written
      # \x5c rather than \\ so shellcheck does not read the pair as a botched
      # attempt at escaping a quote (SC1003) and fail the build.
      osc() {
        printf '\033]%s;rgb:%s/%s/%s\033\x5c' \
          "$1" "''${2:0:2}" "''${2:2:2}" "''${2:4:2}"
      }

      get() { sed -n "s/^$1=//p" "$colours" | head -1; }

      # Named `out` rather than `seq`: the loop below calls seq(1), and a
      # variable of that name reads as though it shadows the command.
      out=""
      out+=$(osc 10 "$(get foreground)")
      out+=$(osc 11 "$(get background)")
      out+=$(osc 12 "$(get cursor)")
      out+=$(osc 17 "$(get selection)")

      # `if` rather than `[ -n "$c" ] && ...`: as the last statement in the loop
      # body a failed test is the body's exit status, and set -e would take the
      # whole script down on the first colour the template did not define.
      for i in $(seq 0 18); do
        c=$(get "color$i")
        if [ -n "$c" ]; then
          out+=$(osc "4;$i" "$c")
        fi
      done

      mkdir -p "$(dirname "$colours")"
      printf '%s' "$out" > "$(dirname "$colours")/sequences.txt"

      for pt in /dev/pts/[0-9]*; do
        [ -w "$pt" ] || continue
        printf '%s' "$out" > "$pt" 2>/dev/null || true
      done
    '';
  };

  # Re-renders the cursor from the accent matugen just wrote, and puts it in
  # front of the compositor. Split out of theme-apply the way term-sequences
  # is: it is one step of a theme run, and it is worth being able to run on
  # its own when only the cursor is in question.
  #
  # The two halves are rendered separately because they are wanted at
  # different times, and the order is what decides whether the cursor turns
  # over with the wallpaper or several seconds behind it.
  #
  # The hyprcursor half is SVG copied into a zip -- 0.2s -- and it is what
  # Hyprland draws with, so it goes first and setcursor follows it
  # immediately. The X11 half is 19 sizes of 88 cursors through rsvg, 2s even
  # with pkgs/bibata-parallel-render.patch, and nothing reads it until it next
  # starts up: CCursorManager reloads its Xcursor copy in its constructor and
  # otherwise only when hyprcursor fails to load, and XWayland and GTK3
  # clients each read the files themselves when they start. So it has no
  # deadline inside a theme run and takes the time it takes, after the visible
  # change has already happened.
  #
  # setcursor is what reloads it. The rendering is swapped in under a name
  # that has not changed, so nothing notices on its own -- and hyprctl needs
  # HYPRLAND_INSTANCE_SIGNATURE, which is why a failure here is not fatal: the
  # theme on disk is correct either way, and this only decides whether the
  # session picks it up now or at the next login.
  #
  # XCURSOR_SIZE is hypr/hyprland/env.lua's, set from vars.cursorSize, so the
  # size follows that file rather than a second copy of the number here. A
  # unit outside the session has neither the variable nor a compositor to
  # tell, and falls through both.
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

  # The animated counterpart, holding a video path. Separate from the record
  # above rather than a mode flag inside it, because the two coexist: an
  # animated wallpaper always has a still frame behind it, and that frame is
  # what the static record points at. Its absence is what tells the unit below
  # there is nothing to play.
  animatedRecord = ''"''${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper/animated"'';

  # Where a video's extracted frame is kept, shared by the picker's thumbnails
  # and the full-size still that gets themed.
  animatedCache = ''"''${XDG_CACHE_HOME:-$HOME/.cache}/animated-wallpaper"'';

  # The half of wpp that is not the picker, split out so the restore unit can
  # reach it too. wayle draws the wallpaper and derives its own bar palette;
  # matugen derives the same Material palette again and renders every file
  # outside the bar from it.
  #
  # --source-color-index is not optional. An image usually yields several
  # candidate source colours, and without a preference matugen refuses to
  # choose: it asks, and when there is no terminal to ask it exits non-zero.
  # From a keybind or a systemd unit that is a theme run that silently did
  # nothing. 0 is the most dominant colour, which is also what matugen picked
  # by default before 4.0.
  #
  # scheme-content keeps the source image's own chroma rather than normalising
  # it towards a tonal spot, which is what makes a wallpaper's palette look
  # like the wallpaper.
  themeApply = pkgs.writeShellApplication {
    name = "theme-apply";
    runtimeInputs = [ pkgs.wayle pkgs.matugen pkgs.psmisc termSequences cursorApply ];
    text = ''
      wallpaper="''${1:?usage: theme-apply <image>}"
      record=${wallpaperRecord}

      wayle wallpaper set --fit fill "$wallpaper"

      matugen image "$wallpaper" \
        --type scheme-content \
        --mode dark \
        --source-color-index 0 \
        --config ${matugenConfig}

      term-sequences
      cursor-apply

      # btop re-reads its theme on SIGUSR2 and otherwise holds the old palette
      # until it is restarted. Nothing else here needs poking: fuzzel and the
      # pickers are started fresh every time, and GTK watches gtk.css itself.
      killall -USR2 btop 2>/dev/null || true

      mkdir -p "$(dirname "$record")"
      printf '%s\n' "$wallpaper" > "$record"
    '';
  };

  # The half of awpp that is not the picker, the animated mirror of
  # theme-apply. A video cannot be handed to either colour engine, so a frame
  # is pulled out of it and put through the whole static path: that gives the
  # palette its root, and leaves the still on wayle's surface underneath the
  # video as what shows whenever mpvpaper is paused or stopped.
  #
  # The seek is 3 seconds in because a lot of these open on a fade from black,
  # which extracts as a frame with no colour in it at all and themes the
  # desktop grey. -ss ahead of -i seeks by keyframe rather than decoding up to
  # the mark, so it costs the same on a 480 MB file as on a 2 MB one; a clip
  # shorter than the seek yields no frame and an empty file, hence the retry
  # from the start.
  awpApply = pkgs.writeShellApplication {
    name = "awp-apply";
    runtimeInputs = [ pkgs.ffmpeg pkgs.systemd themeApply ];
    text = ''
      video="''${1:?usage: awp-apply <video>}"
      record=${animatedRecord}
      cache=${animatedCache}
      frame="$cache/''${video##*/}.png"

      mkdir -p "$cache"
      if [ ! -s "$frame" ] || [ "$video" -nt "$frame" ]; then
        ffmpeg -y -loglevel error -ss 3 -i "$video" -frames:v 1 "$frame" \
          < /dev/null || true
        if [ ! -s "$frame" ]; then
          ffmpeg -y -loglevel error -i "$video" -frames:v 1 "$frame" < /dev/null
        fi
      fi

      theme-apply "$frame"

      mkdir -p "$(dirname "$record")"
      printf '%s\n' "$video" > "$record"
      systemctl --user restart animated-wallpaper.service
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
  home.stateVersion = "26.05";

  xdg.desktopEntries = let
    webApp = name: url: icon: wmClass: {
      inherit name icon;
      exec = "${helium}/bin/helium --app=${url}";
      terminal = false;
      categories = [ "Network" ];
      settings.StartupWMClass = wmClass;
    };
  in {
    bitwarden = webApp "Bitwarden" "https://vault.bitwarden.com" "bitwarden"
      "chrome-vault.bitwarden.com__-Default";
    spotify = webApp "Spotify" "https://open.spotify.com" "spotify"
      "chrome-open.spotify.com__-Default";

    # The one launcher entry the desktop's own tools have between them.
    # fuzzel's launcher lists desktop entries rather than $PATH, so a bare
    # `wpp` is unreachable from it however short the name is -- and an entry
    # each would put eight of this repo's own scripts on the launcher's first
    # page. This one opens the menu that reaches all eight instead.
    #
    # `hal` is enough to find it, and nothing else installed here starts that
    # way. The short names are not lost with the entries: the menu carries
    # each one as its second column and fuzzel matches on the whole row, so
    # `wpp` typed into the menu still selects the wallpaper picker.
    #
    # `icon` names a theme icon the way every other entry here does, but the
    # icon it names is not from a theme: matugen renders it from
    # dotfiles/matugen/templates/halrune.svg into hicolor under
    # ~/.local/share/icons, where fuzzel's lookup finds it beside the Papirus
    # names. So the one entry that opens this machine's own tools is drawn in
    # this machine's own accent, and like everything else the colour engine
    # writes it does not exist until something has themed the desktop once.
    halrune = {
      name = "Halrune Commander";
      genericName = "Desktop tools";
      comment = "Wallpapers, clipboard, VPN, nix and the session";
      icon = "halrune";
      exec = "halrune";
      terminal = false;
      categories = [ "System" ];
    };
  };

  # Wayle drives wallpapers by shelling out to `swww-daemon` by name, with no
  # setting to point it elsewhere -- the only backend key in its schema is
  # Wallust's image sampler, which is colour extraction rather than the
  # wallpaper daemon. nixpkgs carries that project under its new name, awww,
  # and ships no swww alias, so the lookup fails and the desktop stays blank
  # with one WARN line at startup and nothing later.
  # The launcher. ~/.config/fuzzel/fuzzel.ini is left out of xdg.configFile
  # deliberately: matugen rewrites it on every wallpaper, so a read-only store
  # symlink there would fail that write every time. The template it is rendered
  # from is dotfiles/matugen/templates/fuzzel.ini, which is tracked.
  home.packages = with pkgs; [
    papirus-icon-theme
    adw-gtk3
    fuzzel
    wayle

    # The Pi attention extension calls notify-send by name after checking that
    # its Foot window is not focused. Wayle owns org.freedesktop.Notifications.
    libnotify

    # The emoji and glyph picker on SUPER + Period. It drives whichever of
    # fuzzel/wofi/rofi it finds and copies the selection, and it ships its own
    # data rather than fetching a list over HTTP the first time it runs.
    bemoji

    # Screenshots. hyprshot carries grim, slurp, jq and wl-clipboard on an
    # injected PATH, so none of those need installing here -- none of them are
    # on this user's PATH at all.
    hyprshot

    # wayle's own bar/popover colours. theme-provider = matugen makes it shell
    # out to a `matugen` binary by name, exactly as it does to `swww-daemon`,
    # and the failure is the same shape: it logs `cannot execute color
    # extractor` once and then repeats `palette file not found:
    # ~/.cache/wayle/matugen-colors.json` forever, while the bar silently keeps
    # its built-in palette. Nothing in the UI says the theme provider is dead.
    matugen

    themeApply
    awpApply
    termSequences

    # Reached by name from config.toml below: wayle runs a custom module's
    # command through `sh -c` with the session PATH, which carries the
    # per-user profile this lands in.
    specialWs

    # What puts an entry at the top of the launcher. fuzzel ranks by launch
    # count and offers no way to pin: with no filter typed the list is the
    # cache in descending order, so the only lever is the count itself.
    #
    # ~/.cache/fuzzel is `<desktop-file-id>|<count>` a line, read at startup
    # and rewritten on exit with the chosen entry incremented -- so a count
    # written here survives, and one large enough is a pin. The rewrite also
    # means the count set here is not drift: fuzzel takes it to 1000001 on the
    # launch that follows and the next call puts it back.
    #
    # The launcher keybind calls this immediately before opening fuzzel rather
    # than something seeding the cache once, because the cache is a cache --
    # deleting it is meant to be free, and Shift+Delete on a row drops that
    # row from it. Reapplying on the way in is what makes either harmless.
    #
    # awk with index() rather than grep: a desktop file id carries a dot, and
    # as a regex that matches any character, so `nixp.desktop` would take
    # `nixpXdesktop` with it. The rewrite goes through a temporary file in the
    # same directory so a crash cannot leave the cache half-written -- an
    # empty one loses every count on the machine.
    (writeShellApplication {
      name = "fuzzel-pin";
      runtimeInputs = [ coreutils gawk ];
      text = ''
        id="''${1:?usage: fuzzel-pin <desktop-file-id> [count]}"
        count="''${2:-1000000}"
        cache="''${XDG_CACHE_HOME:-$HOME/.cache}/fuzzel"

        mkdir -p "$(dirname "$cache")"
        tmp=$(mktemp "$cache.XXXXXX")
        trap 'rm -f "$tmp"' EXIT

        if [ -e "$cache" ]; then
          awk -v p="$id|" 'index($0, p) != 1' "$cache" > "$tmp"
        fi
        printf '%s|%s\n' "$id" "$count" >> "$tmp"
        mv "$tmp" "$cache"
        trap - EXIT
      '';
    })

    # The menu behind the launcher entry above, and the only thing in the
    # launcher that reaches any of the scripts below it. Each of those is a
    # fuzzel picker in its own right, so this is a picker over pickers.
    #
    # The second column is the command, because that is what the same tool is
    # called from a terminal, from a keybind and on the Stream Deck. fuzzel
    # matches a dmenu row on the whole line rather than on a name field, so
    # carrying it here means `wpp` selects the wallpaper picker from inside
    # this menu exactly as it does from a shell -- the short names stay the
    # fast path, and the descriptions are what makes the menu readable to
    # someone who does not know them.
    #
    # fuzzel opening fuzzel is fine in both directions. The launcher exits as
    # soon as it has spawned this, and this has exited by the time the
    # selection is read -- a dmenu instance prints its answer and is gone --
    # so the picker that follows has the overlay layer and the keyboard to
    # itself rather than contending with either. `exec` is what keeps this
    # shell from sitting behind a menu that has already finished.
    #
    # The eight are left to PATH rather than named in runtimeInputs: every one
    # of them is installed by this same list, so they are in the profile the
    # session, the keybinds and this script all share -- which is how the
    # desktop entry above reaches `halrune` in the first place.
    (writeShellApplication {
      name = "halrune";
      runtimeInputs = [ fuzzel ];
      text = ''
        idx=$(
          printf '%-20s%s\x00icon\x1f%s\n' \
            "Wallpaper"          wpp       preferences-desktop-wallpaper \
            "Animated wallpaper" awpp      applications-multimedia \
            "Clipboard"          clipp     edit-paste \
            "Emoji"              bemoji    face-smile \
            "Blue-light filter"  sunp      redshift \
            "VPN"                vpnp      network-vpn \
            "Nix"                nixp      nix-snowflake \
            "Session"            powermenu system-shutdown \
            | fuzzel --dmenu --index --prompt "halrune> " \
              --font "Google Sans Flex Rounded:size=15" \
              --line-height=32px --lines 8 --width 36
        ) || exit 0

        # --index for the reason every picker here uses it: a row carrying an
        # icon is no longer the line that was fed in, so the answer is a
        # position rather than something that has to survive being rendered.
        case "$idx" in
          0) exec wpp ;;
          1) exec awpp ;;
          2) exec clipp ;;
          3) exec bemoji ;;
          4) exec sunp ;;
          5) exec vpnp ;;
          6) exec nixp ;;
          7) exec powermenu ;;
          *) exit 0 ;;
        esac
      '';
    })

    (writeShellApplication {
      name = "wpp";
      runtimeInputs = [
        fuzzel
        gdk-pixbuf
        coreutils
        findutils
        libnotify
        systemd
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

        # A still image is the whole wallpaper, so anything playing over it has
        # been replaced rather than covered. Dropping the record as well as the
        # process is what keeps it from coming back at the next login.
        rm -f ${animatedRecord}
        systemctl --user stop animated-wallpaper.service || true

        theme-apply "$chosen"
      '';
    })

    # The animated picker. Everything about the fuzzel side of it is wpp's,
    # for the same reasons; what differs is where the icons come from, since
    # gdk-pixbuf-thumbnailer reads images and these are videos.
    (writeShellApplication {
      name = "awpp";
      runtimeInputs = [
        fuzzel
        ffmpeg
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

        # No fallback to a shipped default here, unlike wpp: there is no
        # animated wallpaper in the repo to fall back to, and the desktop
        # already has a working static one either way.
        [ "''${#files[@]}" -gt 0 ] || die "No videos in $dir"

        mkdir -p "$cache"

        for f in "''${files[@]}"; do
          thumb="$cache/''${f##*/}.png"
          if [ ! -s "$thumb" ] || [ "$f" -nt "$thumb" ]; then
            ffmpeg -y -loglevel error -ss 3 -i "$f" -frames:v 1 \
              -vf scale=256:-2 "$thumb" < /dev/null || true
            if [ ! -s "$thumb" ]; then
              ffmpeg -y -loglevel error -i "$f" -frames:v 1 \
                -vf scale=256:-2 "$thumb" < /dev/null || true
            fi
          fi
        done

        # The extension is dropped from the label only -- these names are
        # sentences and the row is narrow -- while the cache stays keyed on the
        # full filename, so two videos of the same scene in different
        # containers keep their own thumbnails.
        idx=$(
          for f in "''${files[@]}"; do
            base="''${f##*/}"
            printf '%s\x00icon\x1f%s\n' "''${base%.*}" "$cache/$base.png"
          done | fuzzel --dmenu --index --prompt "awp> " \
            --font "Google Sans Flex Rounded:size=17" --line-height=64px --lines 8
        ) || exit 0

        case "$idx" in
          "" | *[!0-9]*) exit 0 ;;
        esac

        awp-apply "''${files[$idx]}"
      '';
    })

    # What the bar's power button opens. The module is only an icon -- every
    # one of its click fields defaults to the empty string, so an unconfigured
    # power button is not a broken one, it is a button with nothing bound and
    # no way to tell from looking at it.
    #
    # A menu rather than a bare `systemctl poweroff` because this sits in a
    # corner of the bar next to the systray, where the cost of a misclick is
    # otherwise the whole session. --index keeps the actions addressed by
    # position, so the labels can carry an icon without the case below
    # depending on how a row renders.
    #
    # Logging out is uwsm's job, not the compositor's: greetd starts the
    # session as `uwsm start hyprland-uwsm.desktop`, so the compositor is one
    # unit inside a session envelope and stopping only the compositor leaves
    # the rest of it running. uwsm is left to the PATH wayle inherits from the
    # session, for the reason hyprctl is above -- the copy that matters is the
    # one already managing the session.
    (writeShellApplication {
      name = "powermenu";
      runtimeInputs = [ fuzzel systemd libnotify ];
      text = ''
        idx=$(
          printf '%s\x00icon\x1f%s\n' \
            "Shutdown" system-shutdown \
            "Reboot"   system-reboot \
            "Suspend"  system-suspend \
            "Log out"  system-log-out \
            | fuzzel --dmenu --index --prompt "power> " \
              --font "Google Sans Flex Rounded:size=17" \
              --line-height=32px --lines 4
        ) || exit 0

        case "$idx" in
          0) act=(systemctl poweroff) ;;
          1) act=(systemctl reboot) ;;
          2) act=(systemctl suspend) ;;
          3) act=(uwsm stop) ;;
          *) exit 0 ;;
        esac

        # Everything here answers through logind and polkit, and a refusal is
        # one line on stderr -- which, opened from a keybind or the bar, has
        # nowhere to go. Without this the menu takes the click, closes, and
        # leaves the machine running with no account of why.
        if ! err=$("''${act[@]}" 2>&1); then
          notify-send -a powermenu -u critical \
            "Power" "''${err:-''${act[*]} failed}" 2>/dev/null || true
          echo "powermenu: ''${act[*]}: ''${err:-failed}" >&2
          exit 1
        fi
      '';
    })

    # The clipboard picker. cliphist is fed by the two wl-paste watchers in
    # hypr/hyprland/execs.lua and accumulates from the moment the session
    # starts; this is the only thing that reads it back interactively.
    #
    # -d deletes the chosen entry rather than copying it, which is why the
    # chosen line goes to `cliphist delete` unchanged: delete matches on the
    # id prefix cliphist itself printed, so decoding first would lose it.
    #
    # The list is held in an array and the row addressed by --index, as vpnp
    # and the two wallpaper pickers do, because a row carrying an icon is no
    # longer the line that was fed in -- what fuzzel echoes back is the label
    # alone, and putting that through `cliphist delete` would be trusting the
    # icon spec to have been stripped exactly. An index cannot be reshaped by
    # how a row renders. cliphist marks an image as `[[ binary data ... ]]`
    # rather than showing it, which is the only thing in a row that says what
    # kind of entry it is; that string is what picks the icon.
    (writeShellApplication {
      name = "clipp";
      runtimeInputs = [ fuzzel cliphist wl-clipboard ];
      text = ''
        if [ "''${1:-}" = "-d" ]; then
          prompt="del> "
        else
          prompt="clip> "
        fi

        mapfile -t rows < <(cliphist list)
        [ "''${#rows[@]}" -gt 0 ] || exit 0

        idx=$(
          for r in "''${rows[@]}"; do
            case "$r" in
              *"[[ binary data"*) icon=image-x-generic ;;
              *)                  icon=edit-paste ;;
            esac
            printf '%s\x00icon\x1f%s\n' "$r" "$icon"
          done | fuzzel --dmenu --index --prompt "$prompt" \
            --font "Google Sans Flex Rounded:size=15" --lines 12
        ) || exit 0

        case "$idx" in
          "" | *[!0-9]*) exit 0 ;;
        esac

        if [ "''${1:-}" = "-d" ]; then
          printf '%s\n' "''${rows[idx]}" | cliphist delete
        else
          printf '%s\n' "''${rows[idx]}" | cliphist decode | wl-copy
        fi
      '';
    })

    # The VPN picker. `vpn nodes` emits only the active subscription, sorted
    # fastest first. DIRECT, AUTO and every subscription are pinned above that
    # list, so changing providers and choosing a node are one fuzzel surface.
    # Each subscription row restores that provider's own saved AUTO/manual
    # selection; AUTO applies to whichever subscription is active.
    #
    # Node selections go back through `vpn select`, not `vpn use`. Names carry
    # | and ( ), so putting one back through the regex path can silently match
    # an alternation of its own fragments. Every row is addressed by --index,
    # which also avoids depending on the icon-decorated line fuzzel returns.
    #
    # A node whose health check has never succeeded reports 0 and sorts last;
    # showing that as "0ms" would read as the fastest thing on the list, so it
    # prints as a dash instead.
    #
    # The icons use Rofi's extended dmenu protocol. vpn itself is left to PATH:
    # it is a system writeShellApplication from configuration.nix rather than a
    # Home Manager package that can be named in runtimeInputs.
    (writeShellApplication {
      name = "vpnp";
      runtimeInputs = [ fuzzel ];
      text = ''
        cur=$(vpn status)
        active=$(vpn subscription)
        mapfile -t subscriptions < <(vpn subscriptions)
        mapfile -t rows < <(vpn nodes)

        idx=$(
          {
            printf 'DIRECT  — off\x00icon\x1fnetwork-offline\n'
            printf 'AUTO    — fastest in %s\x00icon\x1fnetwork-vpn\n' "$active"
            for subscription in "''${subscriptions[@]}"; do
              label=''${subscription#*$'\t'}
              if [ "$label" = "$active" ]; then
                printf '%-8s— active subscription\x00icon\x1fnetwork-vpn\n' "$label"
              else
                printf '%-8s— switch subscription\x00icon\x1fnetwork-server\n' "$label"
              fi
            done
            for r in "''${rows[@]}"; do
              d=''${r%%$'\t'*}
              n=''${r#*$'\t'}
              if [ "$d" = 0 ]; then
                printf '  --    %s\x00icon\x1fnetwork-server\n' "$n"
              else
                printf '%5dms %s\x00icon\x1fnetwork-server\n' "$d" "$n"
              fi
            done
          } | fuzzel --dmenu --index --prompt "vpn [$active · $cur]> " \
                --font "Google Sans Flex Rounded:size=15" --lines 14 --width 48
        ) || exit 0

        subscription_end=$((2 + ''${#subscriptions[@]}))
        case "$idx" in
          "" | *[!0-9]*) exit 0 ;;
          0) vpn off ;;
          1) vpn auto ;;
          *)
            if (( idx < subscription_end )); then
              vpn subscription "''${subscriptions[idx - 2]%%$'\t'*}"
            else
              vpn select "''${rows[idx - subscription_end]#*$'\t'}"
            fi
            ;;
        esac
      '';
    })

    # The blue-light filter's manual override. hyprsunset runs its own schedule
    # out of hypr/hyprsunset.conf and needs nothing from here; this is for the
    # evenings the clock gets wrong -- a film that should not be orange, or a
    # late edit where colour matters.
    #
    # Each action is a single request, because a temperature clears the
    # identity matrix by itself: from `identity true`, a bare `temperature
    # 4000` lands on 4000K without the identity having to be lifted first.
    # `reset` with no argument is the way back -- it re-reads the config and
    # reapplies whichever profile the clock is currently in, so an override
    # does not quietly outlive the next boundary.
    #
    # The prompt carries the temperature and nothing else, because identity has
    # no live getter: `profile` answers with the fields of the active profile
    # block rather than with the current state, so it would report the schedule
    # back rather than what is on screen. hyprctl also writes its connect
    # failure to stdout rather than stderr, which is why the reading is checked
    # for digits instead of by exit status -- the daemon being down would
    # otherwise put a whole sentence in the prompt.
    #
    # hyprctl is left to the PATH, as it is in powermenu: the copy that matters
    # is the one already managing the session.
    (writeShellApplication {
      name = "sunp";
      runtimeInputs = [ fuzzel libnotify ];
      text = ''
        cur=$(hyprctl hyprsunset temperature 2>/dev/null || true)
        case "$cur" in "" | *[!0-9]*) cur="--" ;; esac

        idx=$(
          printf '%s\x00icon\x1f%s\n' \
            "Follow the schedule" preferences-system-time \
            "Off"                 weather-clear \
            "Warm     4000 K"     redshift \
            "Warmer   3400 K"     redshift \
            "Warmest  2700 K"     redshift \
            | fuzzel --dmenu --index --prompt "sun [''${cur}K]> " \
              --font "Google Sans Flex Rounded:size=15" \
              --line-height=32px --lines 5 --width 30
        ) || exit 0

        case "$idx" in
          0) req=(reset) ;;
          1) req=(identity true) ;;
          2) req=(temperature 4000) ;;
          3) req=(temperature 3400) ;;
          4) req=(temperature 2700) ;;
          *) exit 0 ;;
        esac

        # A refused request is one line on stdout and the menu has already
        # closed, so without this a stopped daemon is a picker that takes the
        # click and does nothing. `ok` is the only answer that means applied --
        # an unparseable request answers `invalid command` and still exits 0.
        out=$(hyprctl hyprsunset "''${req[@]}" 2>&1 || true)
        if [ "$out" != "ok" ]; then
          notify-send -a sunp -u critical \
            "Blue-light filter" "''${req[*]}: ''${out:-no response}" 2>/dev/null || true
          echo "sunp: ''${req[*]}: ''${out:-no response}" >&2
          exit 1
        fi
      '';
    })

    # The maintenance menu. It answers to `nix` in the launcher through its
    # desktop entry, while the binary is `nixp`: the package manager already
    # owns `bin/nix`, and two derivations claiming one name collide in the
    # profile rather than shadowing each other in any predictable order.
    #
    # Every entry here is long-running, prints output worth reading, and most
    # of them ask sudo for a password -- none of which a background process
    # from a launcher can offer. So the choice opens a terminal, and `--hold`
    # keeps that window after the command exits, which is where the output and
    # the exit status stay readable. A picker with no terminal would be the
    # powermenu problem again: a click, a closed menu, and no account of what
    # happened.
    #
    # This is the only way these commands are reached. Nothing wraps them for
    # a shell -- the long forms are here, in one place, rather than in a
    # `rebuild` on PATH that would be a second copy of the same decisions.
    #
    # nixos-rebuild, nix and nix-collect-garbage are left to PATH the way vpnp
    # leaves `vpn`: all three come with the system, so there is nothing here to
    # name in runtimeInputs.
    (writeShellApplication {
      name = "nixp";
      runtimeInputs = [ fuzzel foot bashInteractive ];
      text = ''
        idx=$(
          printf '%s\x00icon\x1f%s\n' \
            "Rebuild and switch"              system-software-update \
            "Rebuild for the next boot"       system-reboot \
            "Update inputs and switch"        system-software-install \
            "Roll back one generation"        edit-undo \
            "List generations"                document-open-recent \
            "Collect garbage"                 trash-empty \
            "Collect garbage, everything old" edit-delete \
            "Verify the store (slow)"         drive-harddisk \
            | fuzzel --dmenu --index --prompt "nix> " \
              --font "Google Sans Flex Rounded:size=15" \
              --line-height=32px --lines 8 --width 46
        ) || exit 0

        # The flake is addressed as `path:`, which reads the working tree
        # directly. A bare directory ref goes through git, where a file that
        # has never been `git add`ed is invisible -- so a new module would be
        # left out of the build while the rebuild reported success.
        build="sudo nixos-rebuild"
        flake="--flake path:${nixcfgPath}#nix"

        # `nix.gc` already runs the first collection weekly; this is that same
        # sweep on demand, and the second one is the deeper version of it. Both
        # run twice, because ri's profile generations are a separate set from
        # the system ones and root's copy does not reach them.
        sweep="nix-collect-garbage --delete-older-than 30d"
        drop="nix-collect-garbage -d"

        case "$idx" in
          0) label="switch";      cmd="$build switch $flake" ;;
          1) label="boot";        cmd="$build boot $flake" ;;
          2) label="update";      cmd="nix flake update --flake path:${nixcfgPath} && $build switch $flake" ;;
          # --rollback is mutually exclusive with --flake, so this one names no
          # flake at all: it selects a generation of the system profile rather
          # than anything the flake evaluates to.
          3) label="rollback";    cmd="$build switch --rollback" ;;
          4) label="generations"; cmd="nixos-rebuild list-generations" ;;
          5) label="gc";          cmd="$sweep && sudo $sweep" ;;
          6) label="gc -d";       cmd="$drop && sudo $drop" ;;
          7) label="verify";      cmd="sudo nix-store --verify --check-contents" ;;
          *) exit 0 ;;
        esac

        exec foot --app-id=nix-menu --title="nix: $label" --hold bash -c "$cmd"
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
  # It covers the bar, notifications, OSDs and the wallpaper. There is no
  # launcher and no lock screen in it, which is why fuzzel is installed
  # separately and why nothing here binds a lock key.
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
  # A user unit rather than a home.activation script, because both halves of
  # what it drives need a session: wayle answers `wallpaper set` over D-Bus,
  # and term-sequences has terminals to write to only once there are any.
  # Activation runs before either exists. The sleep is for wayle:
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

  # Plays the recorded video over the static wallpaper, and is skipped
  # entirely when nothing has chosen one -- ExecCondition rather than a test
  # inside the script, so an unused animated wallpaper reads as a clean skip in
  # `systemctl --user status` instead of a unit that exits immediately for
  # reasons of its own.
  #
  # mpvpaper draws on the bottom layer while awww holds the background one, so
  # the video sits above the still frame regardless of which surface was
  # created first, and still below every window. Left on the default layer the
  # two share a level and the order they happened to start in decides which is
  # visible -- mpvpaper says as much on startup, warning that a running
  # swww-daemon "may block mpvpaper from being seen".
  #
  # -p pauses decoding whenever the wallpaper is hidden, which is most of the
  # time a game is running, and leaves the last frame on screen. hwdec keeps a
  # 4K60 clip off the CPU; the videos are silent by intent, not by encoding, so
  # no-audio is what stops one from taking over the speakers.
  systemd.user.services.animated-wallpaper = {
    Unit = {
      Description = "Play the animated wallpaper";
      PartOf = [ "graphical-session.target" ];
      After = [
        "graphical-session.target"
        "wayle.service"
        "wallpaper-restore.service"
      ];
    };
    Service = {
      Type = "simple";
      ExecCondition = toString (pkgs.writeShellScript "animated-wallpaper-check" ''
        test -s ${animatedRecord}
      '');
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

  # wpp and awpp read these directories; the collections inside them are user
  # data and are not in the repo, but the directories existing is what keeps a
  # fresh install from looking like a broken one.
  home.file."Pictures/Wallpapers/.keep".text = "";
  home.file."Videos/Animated Wallpapers/.keep".text = "";

  # Pi's mutable settings and credentials remain application-owned, while the
  # code extending the harness is immutable and versioned with the machine.
  # force migrates the header created before it was brought into this flake.
  home.file.".pi/agent/extensions/pi-code-header.ts" = {
    source = ./dotfiles/pi/extensions/pi-code-header.ts;
    force = true;
  };
  home.file.".pi/agent/extensions/attention.ts".source =
    ./dotfiles/pi/extensions/attention.ts;

  # /settings rewrites settings.json, so Home Manager must not make it a store
  # symlink. Seed useful defaults once and leave subsequent model, theme, and
  # interaction choices to Pi. Authentication is a separate file and is never
  # part of this repository.
  home.activation.piSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    settings="${config.home.homeDirectory}/.pi/agent/settings.json"
    if [ ! -e "$settings" ]; then
      run mkdir -p "$(dirname "$settings")"
      run cp ${
        pkgs.writeText "pi-settings.json" (
          builtins.toJSON {
            quietStartup = true;
            theme = "dark";
            defaultProvider = "openai-codex";
            defaultModel = "gpt-5.6-sol";
            defaultThinkingLevel = "xhigh";
            externalEditor = "micro";
            enableInstallTelemetry = false;
          }
        )
      } "$settings"
      run chmod u+w "$settings"
    fi
  '';

  # Widevine, without which every DRM-gated web app loads, searches and browses
  # normally and then refuses to play -- nothing in the UI or the logs names a
  # missing decryption module, so it presents as broken audio and the sink and
  # the mute state get investigated first.
  #
  # helium takes the CDM only as a component, from its own user data directory:
  # `Registering hinted Widevine` and `Registering bundled Widevine` are two
  # different builds, and the second needs a patch at compile time that a build
  # from a binary release cannot have. So this is the component updater's own
  # layout, seeded from the store instead of downloaded -- a versioned directory
  # under WidevineCdm/, which startup scans, registers, and records in the hint
  # file beside it. The version is read off the package because that scan picks
  # the highest one it finds and the manifest inside has to agree with the name.
  #
  # recursive is what keeps that hint stable: it makes the directory itself real
  # and symlinks the three files inside, so the recorded path is this one rather
  # than a store path that a nixpkgs bump would move out from under it.
  home.file.".config/net.imput.helium/WidevineCdm/${pkgs.widevine-cdm.version}" = {
    source = "${pkgs.widevine-cdm}/share/google/chrome/WidevineCdm";
    recursive = true;
  };

  # Equicord rewrites this file whenever anything changes in its settings UI, so
  # it cannot be a home-manager file -- a read-only store symlink there fails
  # the first toggle. Seeding it only when it is absent is what turns the theme
  # on without a trip through that UI, on a machine where Equicord has never
  # run; everything after that is Equicord's to write, including turning the
  # theme off again. A partial file is enough, since the defaults are merged in
  # underneath whatever it holds.
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

  # osu! keeps its settings as plain files beside client.realm and rewrites
  # them when the game exits, so they cannot be home-manager files -- a
  # read-only store symlink there loses every settings change. Seeding only
  # when absent is what carries them onto a machine osu! has not run on, and
  # leaves everything after that to the game. A partial file is enough:
  # osu!framework applies the keys it finds and keeps its own defaults for the
  # rest.
  #
  # input.json is the half worth having. It holds the tablet's mapped area,
  # rotation and pressure threshold -- the settings that cannot be reproduced
  # by eye -- and it is copied verbatim because each handler is resolved
  # through a $type discriminator that has to lead its object.
  #
  # game.ini is the settings panel, minus three kinds of key. Token is a live
  # OAuth credential and this repo is public, and Username is the account it
  # belongs to. Skin and Ruleset are GUIDs into client.realm, so against a
  # fresh database they name nothing. Version, ReleaseStream, WasSupporter,
  # LastProcessedMetadataId and LastOnlineTagsPopulation are the game's own
  # bookkeeping. What the login writes stays osu!'s to write.
  #
  # Keybinds are not here and cannot be: client.realm is a binary Realm
  # database, schema-versioned and migrated per release, and it is where
  # KeyBinding lives along with skins, beatmaps and scores.
  #
  # framework.ini is left out as well -- it pins resolution, display and
  # renderer, which are what another machine most needs to choose for itself.
  home.activation.osuSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    osudir="${config.home.homeDirectory}/.local/share/osu"
    run mkdir -p "$osudir"
    for f in game.ini input.json; do
      if [ ! -e "$osudir/$f" ]; then
        run cp ${./dotfiles/osu}/"$f" "$osudir/$f"
        run chmod u+w "$osudir/$f"
      fi
    done
  '';

  # GTK reads these three from dconf rather than from any file, so they are the
  # half of GTK theming that gtk.css cannot carry: the stylesheet supplies the
  # colours, and these decide the widget theme and icon set the colours are
  # painted onto. Declared rather than written once, because a dconf key set by
  # hand survives only until something else writes it.
  #
  # The cursor is not among them: hypr/hyprland/execs.lua sets cursor-theme and
  # cursor-size from the same variables the compositor's own env is built from,
  # so declaring them here would be a second copy of both, free to drift.
  dconf.settings."org/gnome/desktop/interface" = {
    gtk-theme = "adw-gtk3-dark";
    color-scheme = "prefer-dark";
    icon-theme = "Papirus-Dark";
  };

  # Thunar keeps every preference in xfconf, and home-manager writes these with
  # xfconf-query at activation rather than owning a file -- so a value declared
  # here is reasserted on every switch and the matching GUI toggle stops
  # holding, while anything left out (view mode, zoom, window geometry) stays
  # Thunar's own. hidden-bookmarks suppresses the built-in sidebar entries,
  # which are addressed by URI and so have no on-disk representation to edit;
  # dropping the menubar moves those menus into the toolbar's hamburger.
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
    # Swayimg handles these as a direct Wayland client, but a declared handler
    # is what decides between two applications that both claim a type --
    # helium answers for image/png and the rest through the same MimeType
    # mechanism, and wins on cache order alone when neither is named here.
    # Listing them individually is the only way: the association is per type,
    # and an `image/*` wildcard is not part of the format.
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
    # The types themselves are declared in configuration.nix; osu! is the only
    # application claiming them, so these lines are what make the association
    # deterministic rather than a matter of cache order. The scheme handler is
    # the one that is not decorative: an osu:// link from the browser has no
    # other candidate, and without a named default helium has nothing to
    # hand it to. The desktop id carries the `!` -- it is the filename.
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
      pic = "pi --continue";
      pir = "pi --resume";
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

      # Live colour scheme. term-sequences pushes these escape codes at every
      # terminal that is already open; this is the other half, for shells that
      # start afterwards. foot carries no palette of its own, so without one of
      # the two it sits on stock colours.
      cat ${builtins.dirOf terminalColours}/sequences.txt 2> /dev/null

      # For jumping between prompts in foot terminal
      function mark_prompt_start --on-event fish_prompt
          echo -en "\e]133;A\e\\"
      end

      # Your own overrides; the `2> /dev/null` means an absent file is simply
      # a no-op rather than an error on every new shell.
      source $HOME/.config/fish/user-config.fish 2> /dev/null
    '';

    functions.fish_greeting = ''
      fastfetch --key-padding-left 5
    '';
  };

  # The mark the bar draws at the top of the strip. It is an icon rather than
  # a label because nothing installed here has a runic glyph: both fonts on
  # this machine would draw a box, which is what a label of it would come out
  # as.
  #
  # It is a second drawing of the launcher's rune rather than the same file,
  # and the difference is how each one gets its colour. GTK recolours a
  # symbolic icon by filling its shapes: wayle's own icons carry
  # `gpa:fill='foreground'` on paths with `stroke='none'`, and the toolkit
  # paints those from whatever the module asks for. A stroked drawing has
  # nothing to fill, so it would arrive black on a dark bar. This copy is the
  # same three shapes as filled capsules for that reason, and the launcher's
  # stays stroked because matugen writes its colours in.
  #
  # hicolor/scalable/actions is where wayle's own 362 icons land from its
  # package, so this is found by the same theme lookup, under a name that
  # ends in -symbolic as that lookup expects. Tracked rather than generated,
  # so a read-only store symlink is right: nothing rewrites it, and the
  # colour is decided at the other end.
  xdg.dataFile."icons/hicolor/scalable/actions/halrune-symbolic.svg".source =
    ./dotfiles/wayle/halrune-symbolic.svg;

  xdg.configFile = {
    # Wayle splits its configuration in two, which is what makes this one safe
    # to own from here: config.toml is read and never written, while
    # `wayle config set` and anything changed
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

      # A quarter-unit gap keeps the numbered and special workspaces visually
      # distinct while they remain one cluster. This is the gap inside a group;
      # module-gap, which separates the whole cluster from notifications, is a
      # different setting.
      button-group-module-gap = 0.25

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
          # First in `left`, which on a vertical bar is the top of the strip.
          # A mark rather than a control: it opens the same menu its launcher
          # entry does, so the corner of the screen the desktop's own tools
          # live in is the same corner in both places.
          "custom-halrune",
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
      # Corner rounding for dropdowns, popovers and dialogs -- a scale, not a
      # shape. "full" is 9999px, and GTK clamps a radius to half the box, so
      # it turns every container it reaches into an ellipse rather than a
      # pill: the calendar's grid wrapper and a notification card both come
      # out as circles with the content sitting outside them. "lg" is
      # 0.875rem, which is still half the height of the small boxes -- the
      # calendar day cells, the inline chips -- so those stay fully round
      # while the large ones become rounded rectangles. The bar has its own
      # rounding keys above and is unaffected by this one.
      rounding = "lg"

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

      # The mark at the top of the bar. No command and no label: it is an icon
      # and a click target, which is the whole module.
      #
      # interval-ms = 0 is manual polling, where no timer is started at all.
      # With no command there is nothing to run either way, but the default
      # 5000 would leave a poller ticking against a module that can never
      # change.
      #
      # icon-color is a palette token rather than a colour, and that is what
      # makes the glyph follow the wallpaper: wayle resolves --accent from the
      # scheme matugen hands it, so the mark retints with the bar rather than
      # being rewritten on disk the way the launcher's copy of it is. A hex
      # value would read back from `wayle config get` and never move again.
      #
      # button-variant = "basic" above is what leaves it a bare glyph: the
      # default block-prefix would put the same coloured pill behind it that
      # every other icon here has lost.
      [[modules.custom]]
      id = "halrune"
      interval-ms = 0
      icon-name = "halrune-symbolic"
      icon-color = "accent"
      label-show = false
      left-click = "halrune"

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

      # The power module ships every click field empty, so it draws an icon
      # and answers nothing until one is set. Left-click only: the remaining
      # fields stay empty deliberately, since a scroll landing on a bar corner
      # should not reach anything that ends the session.
      [modules.power]
      left-click = "powermenu"

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

      # The line across the top of a popup is the urgency bar, drawn as
      # `inset 0 2px 0 0` on the card rather than as a border, so it sits
      # inside the rounded corners and reads as a stray rule rather than as
      # an edge. popup-urgency-bar is a threshold and its default, "low",
      # means every notification carries one -- "critical" would keep it for
      # the ones that want the emphasis. Nothing else is lost with it off:
      # a critical notification still tints its icon and a low one still
      # dims it.
      [modules.notifications]
      popup-urgency-bar = "none"

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
      // Match each dropdown's title bar to its main surface. The remaining
      // border keeps the header legible without introducing a raised strip.
      .dropdown-header {
          background: var(--bg-surface);
      }

      .custom.ws-open menubutton.bar-button > button.toggle {
          background-color: var(--accent);
      }

      .custom.ws-open menubutton.bar-button > button.toggle image {
          color: var(--fg-on-accent);
      }
    '';

    # The Discord theme, which is a file rather than a matugen output because
    # nothing in it follows the wallpaper. Owning it from here is
    # what guarantees that: a store symlink cannot be rewritten, so the
    # themes directory never changes under Equicord's watcher and the client
    # never drops its stylesheets to re-import them.
    #
    # Equicord only ever reads a theme file -- listThemes is a readdir and a
    # readFile, so a symlink is as good as a file, and enabling or disabling
    # one is a key in settings.json rather than anything on disk. force,
    # because the themes directory is otherwise written by hand and by the
    # settings UI, and home-manager refuses to clobber a file it does not
    # already own rather than failing only that file.
    "Equicord/themes/wallpaper.theme.css" = {
      source = discordTheme;
      force = true;
    };

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

    # Only the palette underneath this is generated; the file itself never
    # varies, so it is owned here rather than rendered. colorScheme points at
    # the one matugen writes, and the fonts are this machine's rather than the
    # "Sans Serif"/"Monospace" a generic theme would ask fontconfig for.
    # force, because this path already exists as a plain file and home-manager
    # will not clobber an unmanaged one -- it fails the whole switch instead.
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

    # The file manager sidebar. This is the GTK bookmarks file rather than
    # anything Thunar-specific, so it is shared with every other GIO browser,
    # and a label after the URI overrides what would otherwise be the
    # basename. Owning it from here costs the UI side of the feature: the file
    # is a read-only store symlink, so "Add Bookmark" and dragging a folder
    # onto the sidebar both stop working, and the list is only editable
    # through this attribute. force is what keeps a switch from failing the
    # first time something writes a bookmark before home-manager gets there.
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

    "hypr".source =
      config.lib.file.mkOutOfStoreSymlink "${nixcfgPath}/hypr";
  };
}
