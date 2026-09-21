{ writeShellApplication, curl, jq, libnotify, gnugrep, gnused, coreutils }:

writeShellApplication {
  name = "vpn";
  runtimeInputs = [ curl jq libnotify gnugrep gnused coreutils ];
  text = ''
    api=http://127.0.0.1:9090
    state="''${XDG_STATE_HOME:-$HOME/.local/state}/vpn"
    last_subscription="$state/last-subscription"

    api_get() {
      endpoint=$(jq -rn --arg group "$1" '$group | @uri')
      curl -fsS --noproxy '*' --max-time 3 "$api/proxies/$endpoint"
    }
    api_put() {
      endpoint=$(jq -rn --arg group "$1" '$group | @uri')
      curl -fsS --noproxy '*' --max-time 3 -X PUT "$api/proxies/$endpoint" \
        --data "$(jq -nc --arg n "$2" '{name:$n}')"
    }

    api_provider() {
      endpoint=$(jq -rn --arg provider "$1" '$provider | @uri')
      curl -fsS --noproxy '*' --max-time 5 "$api/providers/proxies/$endpoint"
    }

    say() {
      printf '%s\n' "$2"
      notify-send -a VPN -i "$1" VPN "$2" 2>/dev/null || true
    }

    subscription_label() {
      case "$1" in
        PRIMARY) printf '%s\n' Primary ;;
        QUATTRO) printf '%s\n' Quattro ;;
        *) return 1 ;;
      esac
    }

    subscription_provider() {
      case "$1" in
        PRIMARY) printf '%s\n' primary ;;
        QUATTRO) printf '%s\n' quattro ;;
        *) return 1 ;;
      esac
    }

    normalise_subscription() {
      case "''${1,,}" in
        primary) printf '%s\n' PRIMARY ;;
        quattro) printf '%s\n' QUATTRO ;;
        *) return 1 ;;
      esac
    }

    remember_subscription() {
      mkdir -p "$state"
      printf '%s\n' "$1" > "$last_subscription"
    }

    active_subscription() {
      case "$current_group" in
        PRIMARY|QUATTRO) printf '%s\n' "$current_group" ;;
        *)
          if [ -r "$last_subscription" ]; then
            saved=$(cat "$last_subscription")
            case "$saved" in
              PRIMARY|QUATTRO) printf '%s\n' "$saved"; return ;;
            esac
          fi
          printf '%s\n' PRIMARY
          ;;
      esac
    }

    group_selection() { api_get "$1" | jq -er '.now'; }

    display_selection() {
      selection=$(group_selection "$1")
      if [ "$selection" = "$1-AUTO" ]; then
        printf '%s\n' AUTO
      else
        printf '%s\n' "$selection"
      fi
    }

    nodes() {
      active=$(active_subscription)
      provider=$(subscription_provider "$active")
      jq -rn \
        --arg auto "$active-AUTO" \
        --slurpfile g <(api_get "$active") \
        --slurpfile p <(api_provider "$provider") '
        (($p[0].proxies // [])
          | map({key: .name, value: ((.history | last | .delay) // 0)})
          | from_entries) as $d
        | ($g[0].all // [])
        | map(select(. as $n
            | [$auto,"DIRECT","GLOBAL","REJECT","REJECT-DROP","PROXY","COMPATIBLE","PASS","PASS-RULE"]
            | index($n) | not))
        | map({n: ., d: ($d[.] // 0)})
        | (map(select(.d > 0)) | sort_by(.d)) + map(select(.d == 0))
        | .[] | "\(.d)\t\(.n)"
      '
    }

    if ! current_group=$(api_get PROXY | jq -er '.now'); then
      say network-error-symbolic "mihomo is not answering on $api"
      exit 1
    fi

    turn_on() {
      active=$(active_subscription)
      api_put PROXY "$active"
      remember_subscription "$active"
      say network-vpn-symbolic "on -- $(subscription_label "$active") / $(display_selection "$active")"
    }

    turn_off() {
      case "$current_group" in
        PRIMARY|QUATTRO) remember_subscription "$current_group" ;;
      esac
      api_put PROXY DIRECT
      say network-offline-symbolic "off -- direct connection"
    }

    select_subscription() {
      if ! target=$(normalise_subscription "''${1:-}"); then
        echo "usage: vpn subscription <primary|quattro>" >&2
        exit 2
      fi
      api_put PROXY "$target"
      remember_subscription "$target"
      say network-vpn-symbolic "subscription -- $(subscription_label "$target")"
    }

    activate_selection() {
      active=$(active_subscription)
      api_put "$active" "$1"
      api_put PROXY "$active"
      remember_subscription "$active"
    }

    use_node() {
      if [ -z "''${1:-}" ]; then
        echo "usage: vpn use <pattern>" >&2; exit 2
      fi
      target=$(nodes | grep -iP -m1 "\t.*$1" | cut -f2- || true)
      if [ -z "$target" ]; then
        say network-error-symbolic "no node matching '$1'"
        exit 1
      fi
      activate_selection "$target"
      say network-vpn-symbolic "$target"
    }

    select_node() {
      if [ -z "''${1:-}" ]; then
        echo "usage: vpn select <name>" >&2; exit 2
      fi
      names=$(nodes | cut -f2-)
      if ! grep -qxF "$1" <<< "$names"; then
        say network-error-symbolic "no node named '$1'"
        exit 1
      fi
      activate_selection "$1"
      say network-vpn-symbolic "$1"
    }

    status() {
      if [ "$current_group" = DIRECT ]; then
        printf '%s\n' DIRECT
      else
        display_selection "$(active_subscription)"
      fi
    }

    case "''${1:-toggle}" in
      on)     turn_on ;;
      off)    turn_off ;;
      toggle) if [ "$current_group" = DIRECT ]; then turn_on; else turn_off; fi ;;
      use)    use_node "''${2:-}" ;;
      select) select_node "''${2:-}" ;;
      subscriptions) printf 'PRIMARY\tPrimary\nQUATTRO\tQuattro\n' ;;
      subscription)
        if [ -n "''${2:-}" ]; then
          select_subscription "$2"
        else
          subscription_label "$(active_subscription)"
        fi
        ;;
      nodes)  nodes ;;
      auto)   active=$(active_subscription)
              activate_selection "$active-AUTO"
              say network-vpn-symbolic "$(subscription_label "$active") / AUTO" ;;
      status) status ;;
      list)   printf 'subscription: %s\ncurrent: %s\n\n' \
                "$(subscription_label "$(active_subscription)")" "$(status)"
              nodes | while IFS=$'\t' read -r d n; do
                if [ "$d" = 0 ]; then printf '   --   %s\n' "$n"; else printf '%5dms %s\n' "$d" "$n"; fi
              done ;;
      ip)     curl -fsS --max-time 15 https://cloudflare.com/cdn-cgi/trace \
                | sed -n 's/^ip=//p;s/^loc=/ /p' | tr -d '\n'; echo ;;
      *)      echo "usage: vpn [toggle|on|off|auto|subscription [primary|quattro]|subscriptions|use <pattern>|select <name>|nodes|status|list|ip]" >&2; exit 2 ;;
    esac
  '';
}
