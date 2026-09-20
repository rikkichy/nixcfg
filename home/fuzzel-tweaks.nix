{ config, pkgs, lib, inputs, nixcfgPath, ... }:

let
  helium = inputs.helium.packages.${pkgs.stdenv.hostPlatform.system}.default;

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

  services.cliphist = {
    enable = true;
    systemdTargets = [ "graphical-session.target" ];
    extraOptions = [];
  };

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
    webApp = name: url: icon: wmClass: {
      inherit name icon;
      exec = "${helium}/bin/helium --app=${url}";
      terminal = false;
      categories = [ "Network" ];
      settings.StartupWMClass = wmClass;
    };
    papirus = "${pkgs.papirus-icon-theme}/share/icons/Papirus-Dark";
    terminalAction = name: command: {
      inherit name;
      exec = "${pkgs.foot}/bin/foot --app-id=nix-menu --title=Nix --hold ${command}";
    };
    maintenanceActions = {
      switch = terminalAction "Rebuild and switch"
        ''sudo nixos-rebuild switch --flake "path:${nixcfgPath}#nix"''
        // { icon = "system-software-update"; };
      boot = terminalAction "Rebuild for the next boot"
        ''sudo nixos-rebuild boot --flake "path:${nixcfgPath}#nix"''
        // { icon = "system-reboot"; };
      update = terminalAction "Update inputs and switch" (toString (pkgs.writeShellScript "nix-update" ''
        nix flake update --flake ${lib.escapeShellArg "path:${nixcfgPath}"} &&
          sudo nixos-rebuild switch --flake ${lib.escapeShellArg "path:${nixcfgPath}#nix"}
      '')) // { icon = "system-software-install"; };
      rollback = terminalAction "Roll back one generation" "sudo nixos-rebuild switch --rollback"
        // { icon = "${papirus}/24x24/actions/edit-undo.svg"; };
      generations = terminalAction "List generations" "nixos-rebuild list-generations"
        // { icon = "${papirus}/24x24/actions/document-open-recent.svg"; };
      gc = terminalAction "Collect garbage" (toString (pkgs.writeShellScript "nix-gc" ''
        nix-collect-garbage --delete-older-than 30d &&
          sudo nix-collect-garbage --delete-older-than 30d
      '')) // { icon = "${papirus}/24x24/actions/trash-empty.svg"; };
      gc-all = terminalAction "Collect garbage, everything old" (toString (pkgs.writeShellScript "nix-gc-all" ''
        nix-collect-garbage -d && sudo nix-collect-garbage -d
      '')) // { icon = "${papirus}/24x24/actions/edit-delete.svg"; };
      verify = terminalAction "Verify the store (slow)" "sudo nix-store --verify --check-contents"
        // { icon = "${papirus}/32x32/devices/drive-harddisk.svg"; };
    };
  in {
    bitwarden = webApp "Bitwarden" "https://vault.bitwarden.com" "bitwarden"
      "chrome-vault.bitwarden.com__-Default";
    spotify = webApp "Spotify" "https://open.spotify.com" "spotify"
      "chrome-open.spotify.com__-Default";

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
    clipp = {
      name = "Clipboard";
      exec = "clipp";
      icon = "${papirus}/24x24/actions/edit-paste.svg";
      terminal = false;
      categories = [ "System" ];
      settings.OnlyShowIn = "X-DesktopTools;";
      actions.delete = { name = "Delete clipboard entry"; exec = "clipp -d"; icon = "${papirus}/24x24/actions/edit-delete.svg"; };
    };
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
      name = "VPN";
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
    network-reset = {
      name = "Network recovery";
      exec = "troubleshootp all";
      icon = "${papirus}/24x24/actions/view-refresh.svg";
      terminal = false;
      categories = [ "System" ];
      settings.Keywords = "troubleshootp;troubleshoot;network;system;helium;browser;discord;cache;";
      settings.OnlyShowIn = "X-DesktopTools;";
      actions = {
        system = { name = "Reset system networking"; exec = "troubleshootp system"; };
        helium = { name = "Kill Helium and reset networking"; exec = "troubleshootp helium"; };
        discord = { name = "Kill Discord, reset networking and clean cache"; exec = "troubleshootp discord"; };
        reconnect = { name = "Reconnect Ethernet"; exec = "troubleshootp reconnect"; };
      };
    };
    nixp = {
      name = "Nix maintenance";
      exec = maintenanceActions.generations.exec;
      icon = "nix-snowflake";
      terminal = false;
      categories = [ "System" ];
      settings.OnlyShowIn = "X-DesktopTools;";
      actions = builtins.removeAttrs maintenanceActions [ "generations" ];
    };
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
      name = "clipp";
      runtimeInputs = [ desktopPicker cliphist wl-clipboard ];
      text = ''
        if [ "''${1:-}" = "-d" ]; then
          prompt="del> "
        else
          prompt="clip> "
        fi

        selected=$(cliphist list | desktop-picker --with-nth='{2..}' \
          --prompt "$prompt" --lines 12) || exit 0
        [[ "$selected" =~ ^[0-9]+$'\t' ]] || exit 0

        if [ "''${1:-}" = "-d" ]; then
          printf '%s\n' "$selected" | cliphist delete
        else
          printf '%s\n' "$selected" | cliphist decode | wl-copy
        fi
      '';
    })

    (writeShellApplication {
      name = "vpnp";
      runtimeInputs = [ desktopPicker ];
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
          } | desktop-picker --index --prompt "vpn [$active · $cur]> " \
                --lines 14 --width 48
        ) || exit 0

        subscription_end=$((2 + ''${#subscriptions[@]}))
        count=$((subscription_end + ''${#rows[@]}))
        [[ "$idx" =~ ^(0|[1-9][0-9]*)$ ]] || exit 0
        (( ''${#idx} <= ''${#count} )) || exit 0
        (( idx < count )) || exit 0
        case "$idx" in
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
