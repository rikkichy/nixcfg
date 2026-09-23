{ pkgs, lib, ... }:

let
  networkReset = pkgs.writeShellApplication {
    name = "network-reset";
    runtimeInputs = with pkgs; [ coreutils jq procps util-linux curl networkmanager libnotify ];
    text = ''
      scope="''${1:-all}"
      cfg="''${XDG_CONFIG_HOME:-$HOME/.config}"
      roots=()
      names=""
      case "$scope" in
        all) roots=("$cfg/net.imput.helium" "$cfg/discord"); names='helium|helium_crashpad|Discord|\.Discord-wrappe' ;;
        helium) roots=("$cfg/net.imput.helium"); names='helium|helium_crashpad' ;;
        discord) roots=("$cfg/discord"); names='Discord|\.Discord-wrappe' ;;
        system|reconnect) ;;
        *) echo "usage: network-reset [all|system|helium|discord|reconnect]" >&2; exit 2 ;;
      esac
      [ "$#" -le 1 ] || exit 2

      umask 077
      state="''${XDG_STATE_HOME:-$HOME/.local/state}/network-reset"
      mkdir -p "$state"
      chmod 700 "$state"
      exec 9>"$state/reset.lock"
      flock -n 9 || { echo "A network reset is already running." >&2; exit 1; }

      temporary=()
      quarantine=""
      cleanup() {
        local status=$?
        rm -f -- "''${temporary[@]}"
        if [ "$status" != 0 ]; then
          [ -z "$quarantine" ] || printf 'Staged caches retained: %s\n' "$quarantine" >&2
          notify-send -a network-reset -u critical "Network reset failed" \
            "See the troubleshooting terminal for details." 2>/dev/null || true
        fi
        exit "$status"
      }
      trap cleanup EXIT

      owned() {
        if [ -L "$1" ] || [ ! -O "$1" ]; then
          printf 'Refusing symlink or foreign-owned path: %s\n' "$1" >&2
          exit 1
        fi
      }

      if [ -n "$names" ]; then
        pkill -KILL -u "$UID" -x "$names" || (( $? == 1 ))
        timeout 5s pidwait -u "$UID" -x "$names" || (( $? == 1 ))
      fi

      shopt -s nullglob
      files=()
      caches=()
      for root in "''${roots[@]}"; do
        if [ ! -e "$root" ] && [ ! -L "$root" ]; then continue; fi
        owned "$root"
        if [ "$root" = "$cfg/discord" ]; then
          if [ -e "$root/Network Persistent State" ] || [ -L "$root/Network Persistent State" ]; then
            files+=("$root/Network Persistent State")
          fi
          for name in Cache "Code Cache" GPUCache DawnGraphiteCache DawnWebGPUCache; do
            cache="$root/$name"
            if [ ! -e "$cache" ] && [ ! -L "$cache" ]; then continue; fi
            owned "$cache"
            [ -d "$cache" ] || { echo "Not a cache directory: $cache" >&2; exit 1; }
            caches+=("$cache")
          done
        else
          files+=("$root"/*/"Network Persistent State")
        fi
      done

      for file in "''${files[@]}"; do
        owned "$(dirname "$file")"
        owned "$file"
        [ -f "$file" ] || { echo "Not a network-state file: $file" >&2; exit 1; }
        tmp=$(mktemp "$file.reset.XXXXXX")
        temporary+=("$tmp")
        jq -e -s '
          if length != 1 or (.[0] | type) != "object" then
            error("expected one network-state object")
          else
            .[0] |
            if (.net // {} | type) != "object" or
               (.net.http_server_properties // {} | type) != "object" then
              error("invalid network-state schema")
            else
              del(.net.http_server_properties.broken_alternative_services)
            end
          end
        ' "$file" > "$tmp"
      done

      if [ "''${#files[@]}" -gt 0 ]; then
        backup=$(mktemp -d "$state/backup.XXXXXXXX")
        for file in "''${files[@]}"; do
          relative="''${file#"$cfg/"}"
          mkdir -p "$backup/$(dirname "$relative")"
          cp -p -- "$file" "$backup/$relative"
        done
        printf 'Network-state backup: %s\n' "$backup"
        for i in "''${!files[@]}"; do
          mv -- "''${temporary[$i]}" "''${files[$i]}"
        done
      fi

      if [ "''${#caches[@]}" -gt 0 ]; then
        quarantine=$(mktemp -d "$cfg/discord/.network-reset.XXXXXXXX")
        mv -- "''${caches[@]}" "$quarantine/"
      fi

      if [ "$scope" = reconnect ]; then
        connection=$(nmcli -g GENERAL.CON-UUID device show enp11s0)
        [ -n "$connection" ] && [ "$connection" != "--" ] || {
          echo "No active Ethernet connection to reconnect." >&2; exit 1;
        }
        status=0
        nmcli --wait 15 device disconnect enp11s0 || status=$?
        nmcli --wait 30 connection up uuid "$connection" ifname enp11s0
        [ "$status" = 0 ] || exit "$status"
      fi
      if [[ "$scope" = all || "$scope" = system || "$scope" = reconnect ]]; then
        nmcli general reload dns-rc
        curl -fsS --noproxy '*' --max-time 5 -X POST http://127.0.0.1:9090/cache/dns/flush
        curl -fsS --noproxy '*' --max-time 5 -X DELETE http://127.0.0.1:9090/connections
      fi

      if [ -n "$quarantine" ]; then
        rm -rf --one-file-system -- "$quarantine"
        quarantine=""
      fi
      printf 'Completed %s reset. Applications are not reopened.\n' "$scope"
    '';
  };
in
{
  xdg.desktopEntries = {
    network-reset = {
      name = "Network recovery";
      exec = "troubleshootp all";
      icon = "${pkgs.papirus-icon-theme}/share/icons/Papirus-Dark/24x24/actions/view-refresh.svg";
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
  };

  home.packages = lib.mkAfter (with pkgs; [
    (writeShellApplication {
      name = "troubleshootp";
      runtimeInputs = [ foot networkReset ];
      text = ''
        exec foot --app-id=troubleshoot-menu --title="Network recovery" \
          --hold network-reset "$@"
      '';
    })

    networkReset
  ]);
}
