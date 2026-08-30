{ config, pkgs, inputs, nixcfgPath, ... }:

let
  vpn = pkgs.writeShellApplication {
    name = "vpn";
    runtimeInputs = with pkgs; [ curl jq libnotify gnugrep gnused coreutils ];
    text = ''
      api=http://127.0.0.1:9090
      state="''${XDG_STATE_HOME:-$HOME/.local/state}/vpn"
      last_subscription="$state/last-subscription"

      # --noproxy matters: this must reach mihomo even when http_proxy points
      # at mihomo's own mixed-port. Group names are URL-encoded so this remains
      # safe if a future subscription gets a human-readable group name.
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

      # Every node the active subscription offers, minus its AUTO group and
      # the built-ins, sorted fastest first as "delay<TAB>name". Delay 0 means
      # the health check has never succeeded, so those sort last.
      #
      # Two endpoints hold different halves: the subscription group knows its
      # membership but has no node history, while its provider endpoint has the
      # health-check history. Both responses enter jq through file descriptors,
      # not command arguments: Quattro's history is larger than Linux's 128 KiB
      # per-argument limit even though the resulting node rows are small.
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

      # `vpn use sweden` etc. The argument is a case-insensitive regex matched
      # against the active subscription's live node names, and the fastest
      # match wins. Flags, numbering and suffixes in those names can all change
      # without notice, so Stream Deck keys must not depend on a literal name.
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

      # The exact-name counterpart for a caller that picked from the live list.
      # Membership is checked first so a stale row fails loudly rather than a
      # PUT being silently ignored. A here-string avoids grep -q closing a pipe
      # early and turning a successful match into a pipefail/SIGPIPE failure.
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
        # Machine-readable rows for vpnp, as "group<TAB>label".
        subscriptions) printf 'PRIMARY\tPrimary\nQUATTRO\tQuattro\n' ;;
        subscription)
          if [ -n "''${2:-}" ]; then
            select_subscription "$2"
          else
            subscription_label "$(active_subscription)"
          fi
          ;;
        # The same rows `list` prints, as "delay<TAB>name" with no alignment
        # or units, for a picker to feed into fuzzel.
        nodes)  nodes ;;
        # AUTO belongs to the active subscription and selecting it also turns
        # the tunnel on when PROXY is currently at DIRECT.
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

    # The two SATA SSDs mount root-owned, and everything that writes to them
    # runs as ri. `d` rather than `Z` because Z recurses, and reasserting
    # ownership of a full games drive on every boot is not free. Both run
    # after local-fs.target, so they land on the mounted filesystem rather
    # than on an empty directory underneath it.
    "d /games 0755 ri users - -"
    "d /data  0755 ri users - -"
  ];

  # The two spare SATA SSDs, plain XFS with no encryption. Only the NVMe holds
  # anything worth a LUKS header; these are bulk storage, and leaving them
  # unencrypted keeps them readable from a live USB without a passphrase.
  #
  # nofail matters more than it looks. A secondary disk that fails to appear
  # would otherwise hold up local-fs.target and drop the boot into emergency
  # mode over a drive nothing needs to reach the login screen. The device
  # timeout bounds the wait instead of taking the 90s default twice.
  #
  # No discard option: services.fstrim.enable is on, and a weekly batch trim
  # costs less than trimming inline on every delete.
  #
  # x-gvfs-show is what puts them in the file manager sidebar -- it is a GIO
  # hint, so it reaches any GIO-based browser rather than one. GIO decides on its
  # own what counts as worth showing, and a fixed disk mounted outside /media,
  # /run/media and $HOME is not on that list -- so a top-level mount is hidden
  # with nothing to indicate it was a choice. x-gvfs-name sets the label
  # beside it, which otherwise falls back to the mount point's basename.
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

  # Root is declared in hardware-configuration.nix; this adds to the same
  # attribute rather than restating it, so the device and fsType there stay
  # the single definition. Only the option list grows, and both options are
  # userspace-only -- mount and the kernel ignore anything x- prefixed, so
  # nothing here reaches the initrd or the LUKS mapping.
  fileSystems."/".options = [ "x-gvfs-show" "x-gvfs-name=NixOS" ];

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];

    # Off deliberately. Optimisation hardlinks identical files into
    # /nix/store/.links, so one store path is not one file -- it is a share in
    # a pool. An interrupted write corrupts the link, and every path pointing
    # at it is corrupt together. That is how a single unclean shutdown left
    # home.nix as a zero-byte file in the store while the working copy was
    # fine, and the build failed with "unexpected end of file" pointing at a
    # path that looked perfectly normal on disk.
    #
    # It was saving 2.8 GiB on a 928 GB disk with 386 GB free.
    auto-optimise-store = false;

    # Root is XFS, which journals metadata but not file contents, so a file
    # written and not yet flushed comes back at length zero rather than with
    # its old contents. Without this Nix registers a path as valid before its
    # data is durable, which is the exact window that produced the empty store
    # files. The cost is fsync per path on build; the alternative is a store
    # that lies about what it contains after every power loss.
    fsync-store-paths = true;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
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

      # Everything the user sees is run from here, and the session has to be
      # handed to it: the bus address for notify-send, and the Wayland socket
      # for the window behind "View changes". The socket is looked up rather
      # than named -- it is wayland-1 under uwsm, but the number counts up when
      # a compositor is restarted inside one login. The bracket is what
      # separates the socket from the `wayland-1-awww-daemon.sock` and the
      # `.lock` sitting beside it.
      #
      # PATH is nix's own, because nvd shells out to `nix-build` and
      # `nix-store` by name while a unit's PATH is systemd's minimal default
      # and carries neither. That failure is a Python traceback ending in
      # `FileNotFoundError: 'nix-build'`, inside a terminal already opened for
      # it. A unit carries no LANG either, which foot reports as `'C' is not a
      # UTF-8 locale` and every other reader of that variable does not report
      # at all.
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

      # The whole generation, not its kernel. `operation = "boot"` stages every
      # upgrade for next boot, so a pending reboot is the normal outcome even
      # when nothing kernel-side moved -- comparing initrd/kernel/kernel-modules
      # instead reports success for any upgrade that only touched userspace,
      # which is most of them.
      booted="$(readlink -f /run/booted-system)"
      built="$(readlink -f /nix/var/nix/profiles/system)"
      if [ "$booted" = "$built" ]; then
        asuser ${pkgs.libnotify}/bin/notify-send "HalruneNix" "Update successful." || true
        exit 0
      fi

      # The prompt is posted again once the diff window closes, so reading what
      # changed and rebooting for it are not one choice between two. Every
      # other answer -- dismissed, or the 15m timeout -- leaves the upgrade
      # staged, which is where it already was.
      #
      # The round count is the stop. With no notification daemon answering,
      # notify-send returns immediately and every branch below would come back
      # around; ten is past what anyone clicks and still a bound.
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
          # nvd against the two resolved generations rather than the symlinks,
          # so the header names the nixos labels being moved between. It prints
          # a closure-size summary even when no version moved at all, where
          # `nix store diff-closures` prints nothing whatsoever and reads as a
          # dead button. `--hold` keeps the window after it exits, and foot's
          # own 10k lines of scrollback are the pager.
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

  # split_lock_detect=off: Steam's CHTTPClientThread issues atomic operations
  # that straddle a cache line, and the kernel's default `warn` mode traps each
  # one and rate-limits the thread. Measured 2666 traps in 30 minutes, ~89 per
  # minute. A bus lock stalls every core for the duration, not just the thread
  # that caused it, so this is a whole-machine stutter that presents as the
  # compositor hitching rather than as Steam misbehaving. Turning detection off
  # does not fix Steam's alignment, it stops the kernel paying to notice.
  #
  # The last three are kernel hardening, and they are parameters rather than a
  # kernel config for a reason: nixpkgs ships no hardened kernel, and building
  # one here would mean compiling the kernel and the out-of-tree NVIDIA module
  # on every nixpkgs bump, which autoUpgrade does daily. Auditing the stock
  # kernel against KSPP shows why that trade is bad — the settings worth having
  # are already on, and the ones that are not (RANDSTRUCT, CFI, lockdown)
  # conflict with a proprietary GPU module in a kernel built without
  # CONFIG_MODULE_SIG. These three close the rest of the reachable gap for the
  # price of a boot entry:
  #
  # - vsyscall=none removes the legacy vsyscall page. It sits at a fixed
  #   address in every process and is executable, which makes it the one
  #   reliable ROP target left on x86-64. Only pre-2.13 glibc binaries use it.
  # - slab_nomerge keeps same-sized slab caches separate. Merged caches let an
  #   overflow in one kind of object land on another, which is what makes a
  #   heap bug in something harmless into a path to something that is not.
  # - page_alloc.shuffle=1 randomises the page freelist. The kernel supports
  #   this but defaults to auto, which enables it only on machines with a
  #   memory side cache — so it is off here unless asked for.
  #
  # init_on_free is deliberately absent. It is the most valuable of the set and
  # the only one with a measurable cost, zeroing kernel memory on every free;
  # on a machine that exists partly to run games that is the wrong trade.
  boot.kernelParams = [
    "amd_pstate=active"
    "split_lock_detect=off"
    "vsyscall=none"
    "slab_nomerge"
    "page_alloc.shuffle=1"
  ];

  # The two CCDs on a 9950X3D are not interchangeable: cores 0-7 sit under
  # 96 MB of L3 and cores 8-15 under 32 MB. Nothing in the topology ranks them
  # -- acpi_cppc/highest_perf reads the same sequence on both -- so the tie for
  # lightly threaded work is broken by amd_3d_vcache's single knob, which
  # defaults to `frequency` and points that work at the 32 MB half. `cache`
  # points it at the other one, which is the reason the part carries the extra
  # die at all, and it is what a cache-resident game wants.
  #
  # A udev rule rather than tmpfiles or a boot script, because the attribute
  # does not exist until the driver binds. The ACPI device AMDI0101:00 appears
  # first with nothing under it, udev loads amd_3d_vcache from its MODALIAS,
  # and the bind event that follows is the first moment there is anything to
  # write to. Matching on DRIVER== is what waits for that: the key is empty
  # until the bind, so the rule cannot fire too early.
  #
  # amd_pstate=active puts the CPU on amd-pstate-epp, where the two governors
  # are a coarse switch and energy_performance_preference carries the actual
  # bias -- it comes up at balance_performance. The governor is deliberately
  # left at powersave, which for this driver is the dynamic mode rather than a
  # low-power one: selecting `performance` pins min_perf to the maximum on all
  # 32 threads and makes the EPP setting inert, which is a much broader change
  # than biasing the ramp.
  services.udev.extraRules = ''
    ACTION!="remove", SUBSYSTEM=="platform", DRIVER=="amd_x3d_vcache", \
      ATTR{amd_x3d_mode}="cache"

    ACTION!="remove", SUBSYSTEM=="cpu", \
      ATTR{cpufreq/energy_performance_preference}="performance"
  '';

  # The board has an SP5100 TCO watchdog that nothing was using. systemd pings
  # it at half of runtimeTime; if the kernel stops scheduling systemd the board
  # resets the machine instead of leaving it hung until the reset button.
  #
  # This is recovery, not diagnosis, and it is deliberately not a fix for the
  # hard stops: those cut power with no trace at all, which no watchdog can
  # intercept. What it does buy is a distinction -- a reset that leaves a
  # watchdog entry in the log was a hang, one that leaves nothing was not.
  systemd.settings.Manager = {
    RuntimeWatchdogSec = "30s";
    RebootWatchdogSec = "3min";
  };

  # journald fsyncs every 5 minutes by default, so an unclean stop discards up
  # to five minutes of log and leaves the active journal corrupt -- eight files
  # have been rotated out that way. Thirty seconds bounds the loss to something
  # small enough that the last moments before a crash survive, which is the
  # only part worth having.
  services.journald.extraConfig = ''
    SyncIntervalSec=30s
  '';

  # strncpy is no longer part of the kernel's string API, so nct6687.c's one
  # call to it is reported as an implicit declaration rather than as something
  # missing, and the module fails to compile -- which fails the whole switch,
  # a kernel module being part of the system closure. strscpy is the
  # replacement and needs no terminator written afterwards: it always
  # NUL-terminates, where strncpy did not, which is the reason for the change
  # upstream.
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

  # Both ship a user unit, so neither is hand-written here: an interpolated
  # ExecStart has to guess at $out's layout, and hyprpolkitagent's binary is in
  # libexec with no bin/ at all. NixOS does not act on a packaged unit's
  # [Install] section, though, so the wantedBy is still needed to start them.
  systemd.packages = [ pkgs.hyprpolkitagent pkgs.hyprsunset ];
  systemd.user.services.hyprpolkitagent.wantedBy = [ "graphical-session.target" ];

  # The blue-light filter. Its schedule is hypr/hyprsunset.conf, which reaches
  # it through the same out-of-store symlink as the rest of hypr/ -- so the
  # times are a live edit, and `hyprctl hyprsunset reset` reloads them.
  #
  # hyprsunset is deliberately not in environment.systemPackages. Everything
  # that drives it goes through `hyprctl hyprsunset`, and a second copy on PATH
  # is only an invitation to start one by hand -- which the running daemon
  # refuses with "A CTM manager is already running on the current compositor."
  systemd.user.services.hyprsunset.wantedBy = [ "graphical-session.target" ];

  # Shutting down, rebooting and suspending are logind calls, and logind asks
  # polkit. The shipped policy answers `yes` on the `allow_active` branch, which
  # needs the caller to sit in a logind session -- and with uwsm nothing on this
  # desktop does. `session-1.scope` holds greetd and the uwsm bootstrap only;
  # the compositor is a unit under `user@1000.service`, as is everything it
  # spawns, and a process there has no session at all. So the desktop falls to
  # `allow_any`, which is `auth_admin_keep`, and hyprpolkitagent cannot answer
  # for it either: an agent is registered against a session, and there is none
  # to match. The call comes back "Interactive authentication required." on
  # stderr, which from a keybind or a bar button is nowhere, so a power menu
  # entry reads as a dead key rather than a refusal.
  #
  # `pkcheck --action-id org.freedesktop.login1.power-off --process <pid>` is
  # how to see it: a pid inside session-1.scope is authorized, and any pid from
  # the desktop is not.
  #
  # The -multiple-sessions variants are the ids logind picks when another
  # session is logged in, so both are needed to cover the same button. The
  # -ignore-inhibit ones are deliberately left out: an inhibitor holding the
  # machine up is something to be told about, not to override by default.
  #
  # pcscd is built against polkit here and asks it about every client, on the
  # same two branches: `access_pcsc` to open a context and `access_card` to
  # reach the card. It answers a refusal by dropping the connection, which the
  # client can only report as an absent daemon -- Yubico Authenticator says
  # "Failed to open smart card connection: make sure pcscd is installed and
  # running" while pcscd is up and logging `Rejected unauthorized PC/SC client`
  # against that exact pid.
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

  # GrapheneOS hardened_malloc, system-wide. It turns most heap corruption into
  # an immediate abort rather than a silent overwrite: freed memory is zeroed,
  # slabs carry canaries, and size classes sit in separate regions behind guard
  # slabs, so an overflow lands on unmapped memory instead of the neighbouring
  # object.
  #
  # The light template rather than the full one. What it drops -- quarantines,
  # slot randomisation, the write-after-free check, a guard slab every 8 rather
  # than every allocation -- is the part that costs the most and catches the
  # least here, since the value on a desktop is the abort itself, not the depth
  # of the audit trail. Zero-on-free and slab canaries, the two that actually
  # find things, are kept.
  #
  # This is a real compatibility risk, and it is worth knowing which way it
  # breaks: hardened_malloc does not introduce bugs, it stops tolerating ones
  # that were always there. A use-after-free that reads plausible garbage under
  # glibc reads zeroes here and dereferences NULL, so the crash arrives in the
  # program that was already wrong. Anything that ships its own allocator
  # (Chromium's PartitionAlloc, a JVM heap) is untouched, since the preload
  # only replaces malloc.
  #
  # It is applied through /etc/ld-nix.so.preload -- nixpkgs' patched loader, not
  # the FHS /etc/ld.so.preload -- and only affects processes started after the
  # switch. If the desktop stops starting, pick the previous generation in
  # limine; the setting lives in the system closure, so an older generation is
  # already free of it.
  environment.memoryAllocator.provider = "graphene-hardened-light";

  services.fwupd.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
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

    # Steam runs inside a bubblewrap FHS sandbox whose root is a tmpfs, and it
    # binds a fixed list of top-level directories in: /boot /home /root /run
    # /srv /sys /var. A mount outside that list is not there at all, and the
    # failure is quiet and actively misleading -- Steam's library dialog
    # reports the path as a drive with the tmpfs's size, which is half of RAM,
    # so a 500G disk shows up as 15G on a 30G machine. Anything written to it
    # would land in RAM and disappear when Steam exits.
    #
    # The module has no option for this, but its own `apply` only re-overrides
    # extraEnv, extraLibraries and extraPkgs, so an extraBwrapArgs override
    # survives it. The package appends to its own default rather than
    # replacing it, so the crash-dump bind it sets is kept.
    package = pkgs.steam.override {
      extraBwrapArgs = [
        "--bind /games /games"
        "--bind /data /data"
      ];
    };
  };

  programs.gamescope.enable = true;

  programs.gamemode.enable = true;

  # The tablet (One by Wacom M, CTL-672) is driven by osu!lazer's own bundled
  # OpenTabletDriver, which opens /dev/hidraw* directly. This module is what
  # makes that node reachable: its rules tag the tablet's hidraw node and
  # /dev/uinput with uaccess, and without them the node is root-only. osu!
  # then gets EACCES and reports no tablet, while the tablet still moves the
  # cursor through the kernel driver -- so the fault presents as a game
  # setting rather than as a permission on a device node.
  #
  # The blacklist is the other half of it. The kernel wacom driver binds the
  # device and holds it, which OTD reports as "another tablet driver found",
  # and two drivers reading one tablet deliver every motion twice. Blacklisting
  # does not unload a module that is already live, so this one only takes hold
  # on the next boot.
  #
  # The daemon is off because it would claim the device for itself: osu!'s
  # in-process driver could no longer open it, and the game would see the
  # daemon's virtual pointer with its own tablet settings inert. The price is
  # that the tablet does nothing outside osu! -- the module defines no unit
  # when the daemon is disabled, so lending it to the desktop means running
  # `otd-daemon` by hand, and stopping it again before playing.
  hardware.opentabletdriver = {
    enable = true;
    daemon.enable = false;
  };

  # The Wooting 60HE+ (31e3:1322) and its configuration software. The module is
  # both halves at once -- `pkgs.wootility` and `pkgs.wooting-udev-rules` into
  # services.udev.packages -- which is the whole reason to use it rather than
  # listing the package: Wootility reaches the board over hidraw, and an
  # untagged node is root-only, so without the rules the app starts, presents
  # its whole UI and reports no keyboard. That reads as an unsupported model
  # rather than as a permission on a device node.
  #
  # The rules are not per-model. Two Wootings from the AVR era are matched by
  # product id and everything since by vendor alone, so a board that postdates
  # the file is still covered -- the 60HE+ is matched by the generic line.
  #
  # Wootility is an AppImage, so it is on plain glibc malloc whatever
  # environment.memoryAllocator says.
  hardware.wooting.enable = true;

  programs.obs-studio = {
    enable = true;
  };

  services.pcscd.enable = true;
  services.udev.packages = [
    pkgs.yubikey-personalization

    inputs.openwave.packages.${pkgs.stdenv.hostPlatform.system}.default

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

  # Thunar is the file manager. It draws no thumbnails on its own -- every
  # preview comes from tumbler over D-Bus, so without that service a folder of
  # images renders as a wall of generic icons and nothing is logged. xfconf is
  # the settings backend: absent it, Thunar runs but forgets view mode, sort
  # order and sidebar state on every close.
  programs.thunar = {
    enable = true;
    plugins = with pkgs; [
      thunar-volman        # acts on the udisks2 events for removable media
      thunar-archive-plugin
      thunar-vcs-plugin
    ];
  };

  services.tumbler.enable = true;
  programs.xfconf.enable = true;

  # This module installs no browser -- it only writes policy JSON, to
  # /etc/chromium/policies/managed/ among others, and helium reads that
  # directory as any Chromium build does. chrome://policy is where an entry
  # shows up as Platform/Machine/Mandatory once it has been picked up.
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

      # OpenDeck's Discord plugin speaks Discord's RPC protocol over
      # $XDG_RUNTIME_DIR/discord-ipc-0, and a sandbox's runtime directory holds
      # only what has been granted into it. Without this the plugin reports
      # "Could not find the IPC pipe" for a socket that is plainly there on the
      # host, and neither side logs anything. The grant names the socket file
      # rather than a directory, so it is bound at sandbox startup: Discord has
      # to be running by then, and an OpenDeck started first gives the same
      # error until it is restarted.
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

    # osu!'s desktop entry claims six MIME types, but nixpkgs packages no
    # definition for any of them, so the database it is claiming against has
    # never heard of them and the association resolves to nothing. What the
    # file manager sees instead is the fallback: a skin or a beatmap is a zip
    # and opens in the archive manager, a .osu is text. Nothing is logged --
    # the desktop entry is correct in isolation, which is what makes this look
    # like the entry being ignored.
    #
    # These are the types named in that entry, so declaring them is all it
    # takes. xdg.mime.enable compiles anything under share/mime/packages into
    # the system database. The zip and text parents are what keep a
    # double-click on an unhandled variant landing somewhere sensible rather
    # than nowhere; the glob is more specific than the parent's magic, so
    # osu! wins for the extensions it names. The icon is `osu`, the name
    # nixpkgs installs it under -- upstream packaging calls it `osu!`, which
    # resolves to nothing here and leaves the files with a blank page icon.
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

    # Pi Code is the coding harness. Its binary is `pi`, and the wrapper
    # carries ripgrep and fd on an injected PATH, so neither has to be
    # installed for it. It also defaults PI_SKIP_VERSION_CHECK=1, since a
    # store copy is pinned by the flake and the self-update check has nothing
    # to offer it, and PI_TELEMETRY=0. Mutable settings and credentials stay
    # under ~/.pi/agent; Home Manager only owns the tracked extensions.
    pi-coding-agent

    lm_sensors

    # An AppImage, wrapped upstream, shipping the `lms` CLI beside the GUI. The
    # llama.cpp backends are not packaged -- LM Studio downloads the one it
    # wants into ~/.lmstudio at first use, so the only thing this machine has to
    # supply is the driver underneath. That reaches the CUDA runtime through the
    # ld cache buildFHSEnv generates, which carries /run/opengl-driver/lib:
    # neither /etc/ld.so.conf nor LD_LIBRARY_PATH inside the sandbox mentions
    # it, so `dlopen("libcuda.so.1")` succeeding is entirely down to the cache.
    lmstudio

    # Thunar's own search filters visible names in the current folder only; its
    # "Find in this folder" item shells out to catfish for anything recursive
    # or content-based, and silently does nothing when catfish is absent.
    file-roller
    catfish

    # A direct Wayland client with explicit Hyprland support. Image decoding
    # stays in this process instead of starting a sandbox below an RLIMIT_AS;
    # the system-wide hardened allocator reserves terabytes of virtual address
    # space at startup and cannot initialize under a decoder-sized limit.
    swayimg
    mpv
    qbittorrent
    anytype

    # Equicord is what carries the theme: it replaces app.asar with a stub that
    # requires its patcher, and reads ~/.config/Equicord/themes/ from inside the
    # renderer. Nothing else about the client changes, and the injection is
    # part of the derivation rather than something applied to an installed
    # copy, so an update cannot leave it half-patched.
    (discord.override { withEquicord = true; })
    nokochat
    telegram-desktop

    pavucontrol
    zed-editor

    # Unwrapped: the default jdks list is jdk25/21/17/8, which spans every
    # Minecraft era, and gamemodeSupport defaults on to meet programs.gamemode
    # already enabled here. An override would only narrow that.
    prismlauncher

    android-tools

    hyprpolkitagent

    wineWow64Packages.stable

    wl-clipboard mangohud btop nvtopPackages.nvidia git gh wget yt-dlp

    cliphist

    trash-cli

    glib

    bluez

    hyprpicker
    adwaita-icon-theme
    qtengine

    playerctl
    xdg-user-dirs

    # direnv is installed by home-manager (programs.direnv) so nix-direnv comes
    # with it -- a second copy here would shadow the wrapped one.
    starship zoxide eza fzf bat ripgrep lazygit jq fastfetch micro

    # `file` is what BepInEx's run_bepinex.sh uses to decide whether the game
    # binary is 32- or 64-bit, and it picks its doorstop library from the
    # answer. Absent, the script matches neither branch of its case statement
    # and exits with "not compiled for x86 or x64 (might be ARM?)" -- which
    # names the executable, so it reads as a broken game rather than a missing
    # utility. The `file: command not found` line above it goes to the same
    # stream and is easy to scroll past.
    file
    unzip

    tg-ws-proxy
  ];

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";

    # Keep stable Pi prompt prefixes reusable across long coding sessions.
    # Providers that support the setting extend retention (OpenAI to 24h);
    # providers that do not support it ignore it.
    PI_CACHE_RETENTION = "long";

    # This one is not for anything on this system. mesa's libgbm is patched
    # with exactly these two directories as its compiled-in default, so every
    # host program already looks there and naming them changes nothing --
    # `LIBGL_DRIVERS_PATH` is set the same way by `hardware.graphics` and has
    # no GBM counterpart. The reader is pressure-vessel.
    #
    # Building a Proton container means enumerating the host graphics stack
    # and copying it in, and that enumeration walks the library directories
    # the provider's ldconfig reports. There is no ldconfig cache here, so it
    # reports none -- `Unable to determine architecture of provider /
    # ldconfig` on stderr -- and `GBM_BACKENDS_PATH` is the only other place
    # it looks for GBM. Without it the container gets no backends and is
    # still handed a `GBM_BACKENDS_PATH` of its own naming the empty override
    # directories, so inside it every `gbm_create_device()` fails on every
    # DRM node. Drivers that arrive by a different route are unaffected,
    # which is what makes this look like a working container: DXVK picks the
    # right GPU and the game renders.
    #
    # Anything in the container that allocates through GBM gets nothing.
    # spout2pw -- the Spout-to-PipeWire bridge that carries VTube Studio's
    # output to OBS -- allocates its dmabufs that way, so its stream never
    # starts, the PipeWire Video source in OBS stays unconnected, and the
    # only sign of it is `Failed to set up Vulkan for stream (c000000d)`.
    #
    # It has to be set out here. pressure-vessel overwrites the variable
    # inside the container, so a value in Steam's launch options reaches the
    # game already replaced; this one is read before the container is built.
    GBM_BACKENDS_PATH = "/run/opengl-driver/lib/gbm:/run/opengl-driver-32/lib/gbm";
  };

  fonts.packages = with pkgs; [
    noto-fonts

    noto-fonts-color-emoji
    noto-fonts-cjk-sans

    nerd-fonts.jetbrains-mono
    nerd-fonts.caskaydia-cove

    # Google Sans Rounded is the proportional UI face; Departure Mono is the
    # terminal. It is a pixel/bitmap-styled monospace rather than a match for
    # the bar's geometry -- a deliberate contrast, not an accident.
    google-sans-rounded
    nerd-fonts.departure-mono
  ];

  networking.hostName = "nix";
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

      # URLs are sed replacement text rather than patterns. Escape every
      # character with meaning there so query strings remain byte-for-byte
      # credentials and never become part of the tracked template.
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

  # network-online.target is reached immediately here, since nothing waits on
  # the link any more, so mihomo can be started before there is a route and its
  # first subscription fetch fails. The module ships Restart=no, which turns
  # that single miss into a tunnel that is down until someone restarts it by
  # hand -- and a dead tunnel reads as the internet being broken, not as a
  # service that failed. Retrying is only useful because the provider carries
  # `proxy: DIRECT`: a fetch that routed through the tunnel it is trying to
  # build could never repair itself no matter how often it ran.
  systemd.services.mihomo = {
    # The daemon reads the assembled file only at startup. Tie the tracked
    # template to its unit so a switch cannot leave the previous routing graph
    # running against a newly generated /run/mihomo/config.yaml.
    restartTriggers = [ ./dotfiles/mihomo.yaml ];
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  # NetworkManager-wait-online blocks boot until a link is up, which cost
  # 4.9s of every startup. Nothing here needs the network before the login
  # screen: mihomo retries, the flatpak and upgrade units are timer-driven,
  # and fwupd-refresh is on demand.
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

  programs.fish.enable = true;

  users.users.ri = {
    isNormalUser = true;
    shell = pkgs.fish;

    extraGroups = [ "wheel" "networkmanager" "gamemode" "ydotool" "docker" ];
  };

  # Testcontainers backs nokochat's `go test ./... -race`; without a reachable
  # daemon that suite skips silently, which reads as passing.
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
