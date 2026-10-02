{ config, pkgs, lib, nixcfgPath, ... }:

let
  desktopPicker = pkgs.writeShellApplication {
    name = "desktop-picker";
    runtimeInputs = [ pkgs.fuzzel ];
    text = ''
      exec fuzzel --dmenu --only-match --no-run-if-empty \
        --font 'Google Sans Flex Rounded:size=15' --line-height=32px "$@"
    '';
  };

  toolEntryNames = lib.mapAttrsToList (name: _: "${name}.desktop")
    (lib.filterAttrs (_: entry: (entry.settings.OnlyShowIn or "") == "X-DesktopTools;")
      config.xdg.desktopEntries);
  desktopTools = pkgs.symlinkJoin {
    name = "desktop-tools";
    paths = builtins.filter (package: builtins.elem (package.name or "") toolEntryNames)
      config.home.packages ++ [ pkgs.papirus-icon-theme ];
  };
in
{
  _module.args.desktopPicker = desktopPicker;

  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        include = "${config.xdg.configHome}/fuzzel/colors.ini";
        font = "Google Sans Flex Rounded:size=17";
        line-height = "40px";
        lines = 5;
        icon-theme = "Papirus-Dark";
        terminal = "foot -e";
        prompt = "> ";
        layer = "overlay";
        width = 60;
        dpi-aware = "no";
        inner-pad = 10;
        horizontal-pad = 40;
        vertical-pad = 15;
        match-counter = true;
        show-actions = false;
        filter-desktop = true;
        fields = "filename,name,generic,exec,keywords";
      };
      border = { radius = 22; width = 3; };
      key-bindings.execute-input = "none";
    };
  };
  xdg.configFile."fuzzel/fuzzel.ini".force = true;
  xdg.dataFile."desktop-tools".source = "${desktopTools}/share";

  xdg.desktopEntries = let
    papirus = "${pkgs.papirus-icon-theme}/share/icons/Papirus-Dark";
    terminalEntry = name: command: icon: {
      inherit name icon;
      exec = "${pkgs.foot}/bin/foot --app-id=nix-menu --title=Nix --hold ${command}";
      terminal = false;
      categories = [ "System" ];
      settings.OnlyShowIn = "X-DesktopTools;";
    };
  in {
    bemoji = {
      name = "Emoji";
      exec = "bemoji";
      icon = "face-smile";
      terminal = false;
      categories = [ "System" ];
      settings.OnlyShowIn = "X-DesktopTools;";
    };
    sunp = {
      name = "Blue-light filter";
      exec = "sunp";
      icon = "redshift";
      terminal = false;
      categories = [ "System" ];
      settings.OnlyShowIn = "X-DesktopTools;";
    };
    vpnp = {
      name = "VPN server";
      exec = "vpnp";
      icon = "${papirus}/32x32/devices/network-vpn.svg";
      terminal = false;
      categories = [ "System" ];
      settings.OnlyShowIn = "X-DesktopTools;";
    };
    powermenu = {
      name = "Session";
      exec = "powermenu";
      icon = "system-shutdown";
      terminal = false;
      categories = [ "System" ];
      settings.OnlyShowIn = "X-DesktopTools;";
    };
    nix-switch = terminalEntry "nh os switch"
      ''nh os switch "${nixcfgPath}" --hostname nix --no-update-lock-file''
      "system-software-update";
    nix-update = terminalEntry "nh os switch --update"
      ''nh os switch "${nixcfgPath}" --hostname nix --update''
      "system-software-install";
    nix-clean = terminalEntry "Garbage collection — nh clean all"
      "nh clean all"
      "${papirus}/24x24/actions/trash-empty.svg";
  };

  home.packages = lib.mkAfter (with pkgs; [
    (writeShellApplication {
      name = "powermenu";
      runtimeInputs = [ desktopPicker systemd libnotify ];
      text = ''
        idx=$(
          printf '%s\x00icon\x1f%s\n' \
            "Shutdown" system-shutdown \
            "Reboot"   system-reboot \
            "Suspend"  system-suspend \
            "Log out"  system-log-out \
            | desktop-picker --index --prompt "power> " \
              --font "Google Sans Flex Rounded:size=17" --lines 4
        ) || exit 0

        case "$idx" in
          0) act=(systemctl poweroff) ;;
          1) act=(systemctl reboot) ;;
          2) act=(systemctl suspend) ;;
          3) act=(uwsm stop) ;;
          *) exit 0 ;;
        esac

        if ! err=$("''${act[@]}" 2>&1); then
          notify-send -a powermenu -u critical \
            "Power" "''${err:-''${act[*]} failed}" 2>/dev/null || true
          echo "powermenu: ''${act[*]}: ''${err:-failed}" >&2
          exit 1
        fi
      '';
    })

    (writeShellApplication {
      name = "vpnp";
      runtimeInputs = [ desktopPicker pkgs.zed-editor ];
      text = ''
        mode=$(vpn mode 2>/dev/null || true)
        if [ "$mode" = global ]; then target=scoped; else target=global; fi
        menu=$(
          printf '%s\x00icon\x1f%s\n' \
            "Switch subscription" network-vpn \
            "Choose server" network-server \
            "Switch to $target" network-vpn \
            "Edit config" document-edit \
            | desktop-picker --index --prompt "vpn [''${mode:-unavailable}]> " \
                --lines 4 --width 48
        ) || exit 0

        case "$menu" in
          0)
            active=$(vpn subscription)
            action=subscription
            mapfile -t rows < <(vpn subscriptions)
            prompt="subscription [$active]> "
            lines=2
            ;;
          1)
            active=$(vpn subscription)
            cur=$(vpn status)
            action=select
            mapfile -t rows < <(vpn nodes)
            prompt="server [$active · $cur]> "
            lines=14
            ;;
          2) exec vpn mode "$target" ;;
          3) exec zeditor ${lib.escapeShellArg "${nixcfgPath}/common/dotfiles/mihomo.yaml"} ;;
          *) exit 0 ;;
        esac

        idx=$(
          for r in "''${rows[@]}"; do
            n=''${r#*$'\t'}
            if [ "$action" = subscription ]; then
              printf '%s\x00icon\x1fnetwork-vpn\n' "$n"
            else
              d=''${r%%$'\t'*}
              if [ "$d" = 0 ]; then
                printf '  --    %s\x00icon\x1fnetwork-server\n' "$n"
              else
                printf '%5dms %s\x00icon\x1fnetwork-server\n' "$d" "$n"
              fi
            fi
          done | desktop-picker --index --prompt "$prompt" \
                   --lines "$lines" --width 48
        ) || exit 0

        count=''${#rows[@]}
        [[ "$idx" =~ ^(0|[1-9][0-9]*)$ ]] || exit 0
        (( ''${#idx} <= ''${#count} )) || exit 0
        (( idx < count )) || exit 0
        if [ "$action" = subscription ]; then
          vpn subscription "''${rows[idx]%%$'\t'*}"
        else
          vpn select "''${rows[idx]#*$'\t'}"
        fi
      '';
    })

    (writeShellApplication {
      name = "sunp";
      runtimeInputs = [ desktopPicker libnotify ];
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
            | desktop-picker --index --prompt "sun [''${cur}K]> " \
              --lines 5 --width 30
        ) || exit 0

        case "$idx" in
          0) req=(reset) ;;
          1) req=(identity true) ;;
          2) req=(temperature 4000) ;;
          3) req=(temperature 3400) ;;
          4) req=(temperature 2700) ;;
          *) exit 0 ;;
        esac

        out=$(hyprctl hyprsunset "''${req[@]}" 2>&1 || true)
        if [ "$out" != "ok" ]; then
          notify-send -a sunp -u critical \
            "Blue-light filter" "''${req[*]}: ''${out:-no response}" 2>/dev/null || true
          echo "sunp: ''${req[*]}: ''${out:-no response}" >&2
          exit 1
        fi
      '';
    })
  ]);
}
