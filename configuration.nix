{ config, pkgs, lib, inputs, nixcfgPath, ... }:

let
  vpn = pkgs.writeShellApplication {
    name = "vpn";
    runtimeInputs = with pkgs; [ curl jq libnotify gnugrep gnused coreutils ];
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
  };

in
{
  systemd.tmpfiles.rules = [
    "Z ${nixcfgPath} - ri users - -"

    "d /var/lib/xfsprogs 0700 root root - -"

    "d /games 0755 ri users - -"
    "d /data  0755 ri users - -"
  ];

  fileSystems."/games" = {
    device = "/dev/disk/by-uuid/3a42fc06-c2d0-46fa-8a30-2ba6992ed35c";
    fsType = "xfs";
    options = [
      "defaults" "noatime" "nofail" "x-systemd.device-timeout=10s"
      "x-gvfs-show" "x-gvfs-name=Games"
    ];
  };

  fileSystems."/data" = {
    device = "/dev/disk/by-uuid/20685cc5-abf8-47e5-ada2-6519305369e7";
    fsType = "xfs";
    options = [
      "defaults" "noatime" "nofail" "x-systemd.device-timeout=10s"
      "x-gvfs-show" "x-gvfs-name=Data"
    ];
  };

  fileSystems."/".options = [ "x-gvfs-show" "x-gvfs-name=NixOS" ];

  systemd.timers.xfs_scrub_all.wantedBy = [ "timers.target" ];

  systemd.services = {
    xfs_scrub_all_fail.serviceConfig = {
      User = "root";
      Group = "root";
      SupplementaryGroups = [ "" ];
      ExecStart = [
        ""
        "${pkgs.systemd}/bin/systemd-cat --identifier=xfs-scrub --priority=err ${pkgs.coreutils}/bin/echo XFS scrub-all failed -- inspect journalctl -u xfs_scrub_all.service"
      ];
    };

    "xfs_scrub_fail@" = {
      overrideStrategy = "asDropin";
      serviceConfig = {
        User = "root";
        Group = "root";
        SupplementaryGroups = [ "" ];
        ExecStart = [
          ""
          "${pkgs.systemd}/bin/systemd-cat --identifier=xfs-scrub --priority=err ${pkgs.coreutils}/bin/echo XFS metadata scrub failed for %f -- inspect journalctl -u xfs_scrub@%i.service"
        ];
      };
    };

    "xfs_scrub_media_fail@" = {
      overrideStrategy = "asDropin";
      serviceConfig = {
        User = "root";
        Group = "root";
        SupplementaryGroups = [ "" ];
        ExecStart = [
          ""
          "${pkgs.systemd}/bin/systemd-cat --identifier=xfs-scrub --priority=err ${pkgs.coreutils}/bin/echo XFS media scrub failed for %f -- inspect journalctl -u xfs_scrub_media@%i.service"
        ];
      };
    };
  };

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];

    auto-optimise-store = false;

    fsync-store-paths = true;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  programs.nh = {
    enable = true;
    flake = "path:${nixcfgPath}";
  };

  programs.git = {
    enable = true;
    config.safe.directory = nixcfgPath;
  };

  system.autoUpgrade = {
    enable = true;
    operation = "boot";
    flake = nixcfgPath;

    flags = [
      "--update-input" "nixpkgs"
      "--update-input" "home-manager"
      "--update-input" "vhelper"
      "--update-input" "openwave"
      "--update-input" "helium"
      "--update-input" "omp"
      "--update-input" "tg-ws-proxy"
    ];
    dates = "daily";
    randomizedDelaySec = "10min";
  };

  systemd.services.nixos-upgrade-notify = {
    description = "HalruneNix upgrade notification";
    serviceConfig.Type = "oneshot";
    script = ''
      user=ri
      uid=$(${pkgs.coreutils}/bin/id -u "$user")

      wl=$(cd /run/user/"$uid" && ls -d wayland-[0-9] 2>/dev/null | head -1)
      asuser() {
        ${pkgs.util-linux}/bin/runuser -u "$user" -- ${pkgs.coreutils}/bin/env \
          HOME="/home/$user" \
          LANG=${config.i18n.defaultLocale} \
          PATH=${config.nix.package}/bin \
          XDG_RUNTIME_DIR=/run/user/"$uid" \
          WAYLAND_DISPLAY="$wl" \
          DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/"$uid"/bus \
          "$@"
      }

      booted="$(readlink -f /run/booted-system)"
      built="$(readlink -f /nix/var/nix/profiles/system)"
      if [ "$booted" = "$built" ]; then
        asuser ${pkgs.libnotify}/bin/notify-send "HalruneNix" "Update successful." || true
        exit 0
      fi

      round=0
      while [ "$round" -lt 10 ]; do
        round=$((round + 1))
        choice=$(asuser ${pkgs.coreutils}/bin/timeout 15m \
          ${pkgs.libnotify}/bin/notify-send -u critical \
            -A view="View changes" \
            -A reboot="Reboot now" \
            "HalruneNix" "Update requires reboot.") || true
        case "$choice" in
          reboot)
            ${pkgs.systemd}/bin/systemctl reboot
            exit 0
            ;;
          view)
            asuser ${pkgs.foot}/bin/foot --app-id=nix-menu \
              --title="nix: pending update" --hold \
              ${pkgs.nvd}/bin/nvd diff "$booted" "$built" || true
            ;;
          *) exit 0 ;;
        esac
      done
    '';
  };
  systemd.services.nixos-upgrade.onSuccess = [ "nixos-upgrade-notify.service" ];

  systemd.services.nixos-upgrade-failed = {
    description = "HalruneNix upgrade failure notification";
    serviceConfig.Type = "oneshot";
    script = ''
      user=ri
      uid=$(${pkgs.coreutils}/bin/id -u "$user")
      ${pkgs.util-linux}/bin/runuser -u "$user" -- ${pkgs.coreutils}/bin/env \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus \
        ${pkgs.libnotify}/bin/notify-send -u critical \
          "HalruneNix" "Update failed — journalctl -u nixos-upgrade" || true
    '';
  };
  systemd.services.nixos-upgrade.onFailure = [ "nixos-upgrade-failed.service" ];

  nixpkgs.config.allowUnfree = true;

  boot.loader.timeout = 0;

  boot.loader.limine = {
    enable = true;
    efiSupport = true;
    maxGenerations = 10;
  };
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.systemd.enable = true;
  boot.initrd.luks.devices."cryptroot".allowDiscards = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  boot.kernelParams = [
    "amd_pstate=active"
    "split_lock_detect=off"
    "vsyscall=none"
    "slab_nomerge"
    "page_alloc.shuffle=1"
  ];

  services.udev.extraRules = ''
    ACTION!="remove", SUBSYSTEM=="platform", DRIVER=="amd_x3d_vcache", \
      ATTR{amd_x3d_mode}="cache"

    ACTION!="remove", SUBSYSTEM=="cpu", \
      ATTR{cpufreq/energy_performance_preference}="performance"
  '';

  systemd.settings.Manager = {
    RuntimeWatchdogSec = "30s";
    RebootWatchdogSec = "3min";
  };

  services.journald.settings.Journal.SyncIntervalSec = "30s";

  boot.extraModulePackages = [
    (config.boot.kernelPackages.nct6687d.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        sed -i 's/strncpy(valcp, val, 16);/strscpy(valcp, val, sizeof(valcp));/' \
          nct6687.c
      '';
    }))
  ];
  boot.kernelModules = [ "nct6687" ];
  boot.blacklistedKernelModules = [ "nct6683" ];
  boot.extraModprobeConfig = ''
    options nct6687 force=true msi_fan_brute_force=true
  '';

  boot.kernel.sysctl = {
    "vm.max_map_count" = 2147483642;
    "vm.swappiness" = 180;
    "vm.page-cluster" = 0;

    "kernel.dmesg_restrict" = 1;

    "kernel.unprivileged_bpf_disabled" = 2;
    "net.core.bpf_jit_harden" = 1;

    "kernel.yama.ptrace_scope" = 1;
  };

  zramSwap.enable = true;

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    open = true;
    nvidiaSettings = true;
    powerManagement.enable = true;
  };

  programs.hyprland = {
    enable = true;
    withUWSM = true;
    xwayland.enable = true;
  };

  systemd.packages = [ pkgs.hyprpolkitagent pkgs.hyprsunset ];
  systemd.user.services.hyprpolkitagent.wantedBy = [ "graphical-session.target" ];

  systemd.user.services.hyprsunset.wantedBy = [ "graphical-session.target" ];

  security.polkit.extraConfig = ''
    polkit.addRule(function (action, subject) {
      if (subject.user == "ri" && (
            action.id == "org.freedesktop.login1.power-off" ||
            action.id == "org.freedesktop.login1.power-off-multiple-sessions" ||
            action.id == "org.freedesktop.login1.reboot" ||
            action.id == "org.freedesktop.login1.reboot-multiple-sessions" ||
            action.id == "org.freedesktop.login1.suspend" ||
            action.id == "org.freedesktop.login1.suspend-multiple-sessions" ||
            action.id == "org.debian.pcsc-lite.access_pcsc" ||
            action.id == "org.debian.pcsc-lite.access_card")) {
        return polkit.Result.YES;
      }
    });
  '';

  programs.dconf.enable = true;

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = [ "hyprland" "gtk" ];
  };

  services.greetd = {
    enable = true;
    settings = {
      initial_session = {
        command = "uwsm start hyprland-uwsm.desktop";
        user = "ri";
      };

      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd 'uwsm start hyprland-uwsm.desktop'";
        user = "greeter";
      };
    };
  };

  security.rtkit.enable = true;

  security.protectKernelImage = true;

  security.sudo-rs.enable = true;

  environment.memoryAllocator.provider = "graphene-hardened-light";

  services.fwupd.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;

    extraConfig.pipewire."90-blessing3-eq" = {
      "context.modules" = [
        {
          name = "libpipewire-module-filter-chain";
          args = {
            "node.description" = "Blessing 3 EQ";
            "media.name" = "Blessing 3 EQ";

            "filter.graph" = {
              nodes = [
                {
                  type = "builtin";
                  name = "preamp";
                  label = "linear";
                  control = {
                    Mult = 0.630957;
                    Add = 0.0;
                  };
                }
                {
                  type = "builtin";
                  name = "bass";
                  label = "bq_lowshelf";
                  control = {
                    Freq = 105.0;
                    Q = 0.70;
                    Gain = 4.0;
                  };
                }
              ];
              links = [
                {
                  output = "preamp:Out";
                  input = "bass:In";
                }
              ];
            };

            "audio.channels" = 2;
            "audio.position" = [ "FL" "FR" ];

            "capture.props" = {
              "node.name" = "blessing3_eq";
              "node.description" = "Blessing 3 EQ";
              "media.class" = "Audio/Sink";
              "filter.smart" = true;
              "filter.smart.name" = "blessing3-eq";
              "filter.smart.target" = {
                "alsa.card_name" = "Elgato Wave XLR";
              };
            };

            "playback.props" = {
              "node.name" = "blessing3_eq_output";
              "node.passive" = true;
              "stream.dont-remix" = true;
            };
          };
        }
      ];
    };
  };

  services.gnome.gnome-keyring.enable = true;
  security.pam.services.greetd.enableGnomeKeyring = true;

  programs.ydotool.enable = true;

  programs.localsend = {
    enable = true;
    openFirewall = false;
  };

  services.ananicy = {
    enable = true;
    package = pkgs.ananicy-cpp;
    rulesProvider = pkgs.ananicy-rules-cachyos;
  };

  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;

    remotePlay.openFirewall = false;
    localNetworkGameTransfers.openFirewall = false;

    extraCompatPackages = [ pkgs.proton-ge-bin ];

    package = pkgs.steam.override {
      extraBwrapArgs = [
        "--bind /games /games"
        "--bind /data /data"
      ];
    };
  };

  programs.gamescope.enable = true;

  programs.gamemode.enable = true;

  hardware.opentabletdriver = {
    enable = true;
    daemon.enable = false;
  };

  hardware.wooting.enable = true;

  programs.obs-studio = {
    enable = true;
  };

  services.pcscd.enable = true;
  services.udev.packages = [
    pkgs.yubikey-personalization

    inputs.openwave.packages.${pkgs.stdenv.hostPlatform.system}.default

    (pkgs.writeTextDir "lib/udev/rules.d/70-lc87.rules" ''
      KERNEL=="hidraw*", ATTRS{idVendor}=="056a", TAG+="uaccess"
      SUBSYSTEM=="usb", ATTR{idVendor}=="0ac3", TAG+="uaccess"
    '')

    (pkgs.runCommand "streamdeck-udev-rules" { } ''
      mkdir -p $out/lib/udev/rules.d
      r=$out/lib/udev/rules.d/40-streamdeck.rules
      for pid in 0060 0063 006c 006d 0080 0084 0086 008f 0090 00b3 009a 00a5 00b8 00b9 00ba 00c6; do
        printf 'SUBSYSTEM=="usb", ATTRS{idVendor}=="0fd9", ATTRS{idProduct}=="%s", MODE="0660", TAG+="uaccess"\n' "$pid" >> $r
        printf 'KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0fd9", ATTRS{idProduct}=="%s", MODE="0660", TAG+="uaccess"\n' "$pid" >> $r
      done
    '')
  ];

  services.gvfs.enable = true;

  services.udisks2.enable = true;

  programs.thunar = {
    enable = true;
    plugins = with pkgs; [
      thunar-volman
      thunar-archive-plugin
      thunar-vcs-plugin
    ];
  };

  services.tumbler.enable = true;
  programs.xfconf.enable = true;

  programs.chromium = {
    enable = true;
    extensions = [
      "ddkjiahejlhfcafbddmgiahcphecmpfh"
      "mnjggcdmjocbbbhaepdhchncahnbgone"
      "gebbhagfogifgggkldgodflihgfeippi"
      "ammjkodgmmoknidbanneddgankgfejfh"
    ];

    extraOpts = {
      TranslateEnabled = false;
      PasswordManagerEnabled = false;
    };
  };

  services.flatpak.enable = true;

  systemd.user.services.flatpak-bootstrap = {
    description = "Install the Flatpak apps this config expects";
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "10min";
    };
    script = ''
      set -eu
      flatpak=${pkgs.flatpak}/bin/flatpak
      $flatpak remote-add --user --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
      for app in org.vinegarhq.Sober me.amankhanna.opendeck; do
        $flatpak install --user -y --noninteractive flathub "$app"
      done

      $flatpak override --user --filesystem=xdg-run/discord-ipc-0 \
        me.amankhanna.opendeck
    '';
  };

  systemd.user.timers.flatpak-bootstrap = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnStartupSec = "2min";
      AccuracySec = "1min";
    };
  };

  systemd.user.services.flatpak-update = {
    description = "Update Flatpak apps";
    serviceConfig.Type = "oneshot";
    script = "${pkgs.flatpak}/bin/flatpak update --user -y --noninteractive";
  };
  systemd.user.timers.flatpak-update = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "15min";
      Persistent = true;
    };
  };

  environment.systemPackages = with pkgs; [
    vpn

    inputs.helium.packages.${pkgs.stdenv.hostPlatform.system}.default
    inputs.vhelper.packages.${pkgs.stdenv.hostPlatform.system}.default

    inputs.openwave.packages.${pkgs.stdenv.hostPlatform.system}.default

    filen-desktop

    heroic
    protonplus
    osu-lazer-bin

    (writeTextDir "share/mime/packages/osu.xml" ''
      <?xml version="1.0" encoding="UTF-8"?>
      <mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
        <mime-type type="application/x-osu-beatmap">
          <comment>osu! beatmap</comment>
          <glob pattern="*.osu"/>
          <sub-class-of type="text/plain"/>
          <magic priority="60">
            <match type="string" offset="0" value="osu file format v"/>
          </magic>
          <icon name="osu"/>
        </mime-type>
        <mime-type type="application/x-osu-storyboard">
          <comment>osu! storyboard</comment>
          <glob pattern="*.osb"/>
          <sub-class-of type="text/plain"/>
          <icon name="osu"/>
        </mime-type>
        <mime-type type="application/x-osu-skin-archive">
          <comment>osu! skin archive</comment>
          <glob pattern="*.osk"/>
          <sub-class-of type="application/zip"/>
          <icon name="osu"/>
        </mime-type>
        <mime-type type="application/x-osu-beatmap-archive">
          <comment>osu! beatmap archive</comment>
          <glob pattern="*.osz"/>
          <glob pattern="*.osz2"/>
          <sub-class-of type="application/zip"/>
          <icon name="osu"/>
        </mime-type>
        <mime-type type="application/x-osu-replay">
          <comment>osu! replay</comment>
          <glob pattern="*.osr"/>
          <sub-class-of type="application/octet-stream"/>
          <icon name="osu"/>
        </mime-type>
      </mime-info>
    '')

    foot
    yubioath-flutter

    inputs.omp.packages.${pkgs.stdenv.hostPlatform.system}.omp

    lm_sensors

    inputs.unsloth.packages.${pkgs.stdenv.hostPlatform.system}.unsloth-desktop

    file-roller
    catfish

    swayimg
    mpv
    qbittorrent
    anytype
    onlyoffice-desktopeditors

    (discord.override { withEquicord = true; })
    nokochat
    telegram-desktop

    pavucontrol
    zed-editor

    prismlauncher

    android-tools

    hyprpolkitagent

    wineWow64Packages.stable

    wl-clipboard mangohud btop nvtopPackages.nvidia git gh wget yt-dlp


    trash-cli

    glib

    bluez

    hyprpicker
    adwaita-icon-theme
    qtengine

    playerctl
    xdg-user-dirs

    starship zoxide eza fzf bat ripgrep lazygit jq fastfetch micro

    file
    unzip

    tg-ws-proxy
  ];

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";

    PI_CACHE_RETENTION = "long";

    GBM_BACKENDS_PATH = "/run/opengl-driver/lib/gbm:/run/opengl-driver-32/lib/gbm";
  };

  fonts.packages = with pkgs; [
    noto-fonts

    noto-fonts-color-emoji
    noto-fonts-cjk-sans

    nerd-fonts.jetbrains-mono
    nerd-fonts.caskaydia-cove

    google-sans-rounded
    nerd-fonts.departure-mono
  ];

  networking.hostName = "nix";
  networking.enableIPv6 = false;
  networking.networkmanager.enable = true;

  systemd.services.mihomo-config = {
    description = "Assemble mihomo's config from the template and subscription credentials";
    before = [ "mihomo.service" ];
    requiredBy = [ "mihomo.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu
      primary_url=$(tr -d '[:space:]' < /etc/mihomo/subscription.url)
      quattro_url=$(tr -d '[:space:]' < /etc/mihomo/quattro.url)
      [ -n "$primary_url" ]
      [ -n "$quattro_url" ]

      if [ ! -s /etc/mihomo/hwid ]; then
        tr -d '[:space:]' < /etc/machine-id > /etc/mihomo/hwid
        chmod 600 /etc/mihomo/hwid
      fi
      hwid=$(tr -d '[:space:]' < /etc/mihomo/hwid)

      escape_sed() { printf '%s' "$1" | ${pkgs.gnused}/bin/sed 's/[\\&|]/\\&/g'; }
      primary_url=$(escape_sed "$primary_url")
      quattro_url=$(escape_sed "$quattro_url")
      hwid=$(escape_sed "$hwid")

      install -d -m 700 /run/mihomo
      ${pkgs.gnused}/bin/sed \
        -e "s|@PRIMARY_SUBSCRIPTION_URL@|$primary_url|" \
        -e "s|@QUATTRO_SUBSCRIPTION_URL@|$quattro_url|" \
        -e "s|@HWID@|$hwid|" \
        ${./dotfiles/mihomo.yaml} > /run/mihomo/config.yaml
      chmod 600 /run/mihomo/config.yaml
    '';
  };

  services.mihomo = {
    enable = true;
    tunMode = true;
    webui = pkgs.metacubexd;
    configFile = "/run/mihomo/config.yaml";
  };

  systemd.services.mihomo = {
    restartTriggers = [ ./dotfiles/mihomo.yaml ];
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  systemd.services.NetworkManager-wait-online.enable = false;

  networking.networkmanager.unmanaged = [ "interface-name:mihomo" ];
  networking.firewall.trustedInterfaces = [ "mihomo" ];

  networking.firewall.interfaces =
    let
      lan = {
        allowedTCPPorts = [ 27036 27037 27040 53317 ];
        allowedUDPPorts = [ 10400 10401 27036 53317 ];
        allowedUDPPortRanges = [ { from = 27031; to = 27035; } ];
      };
    in
    {
      enp11s0 = lan;
      wlp8s0 = lan;
    };

  networking.firewall.checkReversePath = "loose";

  time.timeZone = "Europe/Moscow";
  i18n.defaultLocale = "en_US.UTF-8";

  programs.fish = {
    enable = true;
    shellInit = ''
      set -gx NH_FLAKE ${lib.escapeShellArg config.programs.nh.flake}
    '';
  };

  users.users.ri = {
    isNormalUser = true;
    shell = pkgs.fish;

    extraGroups = [ "wheel" "networkmanager" "gamemode" "ydotool" "docker" ];
  };

  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };

  services.printing.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  hardware.bluetooth.enable = true;
  services.fstrim.enable = true;

  system.stateVersion = "26.05";
}
