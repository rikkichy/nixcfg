{ writeShellApplication, curl, jq, libnotify, gnugrep, gnused, coreutils }:

writeShellApplication {
  name = "vpn";
  runtimeInputs = [ curl jq libnotify gnugrep gnused coreutils ];
  text = ''
    api=http://127.0.0.1:9090

    # api COLLECTION NAME [SELECTION]: GET the item, or PUT SELECTION into the proxy group.
    api() {
      url=$api/$1/$(jq -rn --arg n "$2" '$n | @uri')
      case "$1" in proxies) timeout=3 ;; *) timeout=5 ;; esac
      if [ $# -eq 3 ]; then
        set -- -X PUT --data "$(jq -nc --arg n "$3" '{name:$n}')"
      else
        set --
      fi
      curl -fsS --noproxy '*' --header @/run/mihomo-api.header --max-time "$timeout" "$@" "$url"
    }

    say() {
      printf '%s\n' "$2"
      notify-send -a VPN -i "$1" VPN "$2" 2>/dev/null || true
    }

    # Prints "GROUP<TAB>Label" for a case-insensitive subscription name.
    subscription_row() {
      case "''${1,,}" in
        primary) printf 'PRIMARY\tPrimary\n' ;;
        quattro) printf 'QUATTRO\tQuattro\n' ;;
        *) return 1 ;;
      esac
    }

    active_subscription() {
      if [ "$(subscription_row "$current_group" | cut -f1)" != "$current_group" ]; then
        echo "unexpected PROXY selection: $current_group" >&2; return 1
      fi
      printf '%s\n' "$current_group"
    }

    nodes() {
      active=$(active_subscription)
      jq -rn \
        --slurpfile g <(api proxies "$active") \
        --slurpfile p <(api providers/proxies "''${active,,}") '
        ($p[0].testUrl // "") as $url
        | (($p[0].proxies // [])
          | map({key: .name, value: (.extra[$url]
              | if .alive then ((.history | last | .delay) // 0) else 0 end)})
          | from_entries) as $d
        | ($g[0].all // [])
        | map(select(. as $n
            | ["DIRECT","GLOBAL","REJECT","REJECT-DROP","PROXY","COMPATIBLE","PASS","PASS-RULE"]
            | index($n) | not))
        | map({n: ., d: ($d[.] // 0)})
        | (map(select(.d > 0)) | sort_by(.d)) + map(select(.d == 0))
        | .[] | "\(.d)\t\(.n)"
      '
    }

    if ! current_group=$(api proxies PROXY | jq -er '.now'); then
      say network-error-symbolic "mihomo is not answering on $api"
      exit 1
    fi

    select_subscription() {
      if ! target=$(subscription_row "''${1:-}" | cut -f1); then
        echo "usage: vpn subscription <primary|quattro>" >&2
        exit 2
      fi
      api proxies PROXY "$target"
      say network-vpn-symbolic "subscription -- $(subscription_row "$target" | cut -f2)"
    }

    activate_selection() {
      active=$(active_subscription)
      api proxies "$active" "$1"
      api proxies PROXY "$active"
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
      if ! grep -qxF -- "$1" <<< "$names"; then
        say network-error-symbolic "no node named '$1'"
        exit 1
      fi
      activate_selection "$1"
      say network-vpn-symbolic "$1"
    }

    status() {
      api proxies "$(active_subscription)" | jq -er '.now'
    }

    case "''${1:-status}" in
      use)    use_node "''${2:-}" ;;
      select) select_node "''${2:-}" ;;
      subscriptions) subscription_row primary; subscription_row quattro ;;
      subscription)
        if [ -n "''${2:-}" ]; then
          select_subscription "$2"
        else
          subscription_row "$(active_subscription)" | cut -f2
        fi
        ;;
      nodes)  nodes ;;
      status) status ;;
      list)   printf 'subscription: %s\ncurrent: %s\n\n' \
                "$(subscription_row "$(active_subscription)" | cut -f2)" "$(status)"
              nodes | while IFS=$'\t' read -r d n; do
                if [ "$d" = 0 ]; then printf '   --   %s\n' "$n"; else printf '%5dms %s\n' "$d" "$n"; fi
              done ;;
      ip)     curl -fsS --max-time 15 https://cloudflare.com/cdn-cgi/trace \
                | sed -n 's/^ip=//p;s/^loc=/ /p' | tr -d '\n'; echo ;;
      *)      echo "usage: vpn [subscription [primary|quattro]|subscriptions|use <pattern>|select <name>|nodes|status|list|ip]" >&2; exit 2 ;;
    esac
  '';
}
