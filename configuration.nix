{ config, pkgs, inputs, nixcfgPath, ... }:

let
  vpn = pkgs.writeShellApplication {
    name = "vpn";
    runtimeInputs = with pkgs; [ curl jq libnotify gnugrep gnused coreutils ];
    text = ''
      api=http://127.0.0.1:9090
      group=PROXY
      state="''${XDG_STATE_HOME:-$HOME/.local/state}/vpn"
      last="$state/last-node"

      # --noproxy matters: this must reach mihomo even when http_proxy points
      # at mihomo's own mixed-port.
      api_get() { curl -fsS --noproxy '*' --max-time 3 "$api/proxies/$group"; }
      api_put() {
        curl -fsS --noproxy '*' --max-time 3 -X PUT "$api/proxies/$group" \
          --data "$(jq -nc --arg n "$1" '{name:$n}')"
      }

      api_providers() { curl -fsS --noproxy '*' --max-time 5 "$api/providers/proxies"; }

      say() {
        printf '%s\n' "$2"
        notify-send -a VPN -i "$1" VPN "$2" 2>/dev/null || true
      }

      # Every node the group currently offers, minus the pseudo-entries, sorted
      # fastest first, as "delay<TAB>name". Delay 0 means the health check has
      # never succeeded -- a dead node -- so those sort last rather than first.
      #
      # Two endpoints, because they hold different halves: /proxies/PROXY knows
      # which nodes the group offers but carries no history for them (only the
      # nine built-ins like DIRECT and AUTO are top-level entries there), while
      # /providers/proxies carries the health-check history but not group
      # membership. Reading only the first is why every latency showed as "--".
      #
      # Delays are merged across *all* providers, so a second subscription is
      # picked up with no change here and no change on the Stream Deck.
      nodes() {
        jq -rn --argjson g "$(api_get)" --argjson p "$(api_providers)" '
          ($p.providers | to_entries | map(.value.proxies // []) | flatten
            | map({key: .name, value: ((.history | last | .delay) // 0)})
            | from_entries) as $d
          | ($g.all // [])
          | map(select(. as $n
              | ["AUTO","DIRECT","GLOBAL","REJECT","REJECT-DROP","PROXY","COMPATIBLE","PASS","PASS-RULE"]
              | index($n) | not))
          | map({n: ., d: ($d[.] // 0)})
          | (map(select(.d > 0)) | sort_by(.d)) + map(select(.d == 0))
          | .[] | "\(.d)\t\(.n)"
        '
      }

      if ! cur=$(api_get | jq -er '.now'); then
        say network-error-symbolic "mihomo is not answering on $api"
        exit 1
      fi

      turn_on() {
        target=AUTO
        if [ -r "$last" ]; then
          saved=$(cat "$last")
          if [ -n "$saved" ] && [ "$saved" != DIRECT ]; then target=$saved; fi
        fi
        api_put "$target"
        say network-vpn-symbolic "on -- $target"
      }

      turn_off() {
        if [ "$cur" != DIRECT ]; then
          mkdir -p "$state"
          printf '%s\n' "$cur" > "$last"
        fi
        api_put DIRECT
        say network-offline-symbolic "off -- direct connection"
      }

      # `vpn use sweden` etc. The argument is a case-insensitive regex matched
      # against live node names, and the fastest match wins -- deliberately not
      # an exact name. Subscription node names carry flags, Cyrillic, numbering
      # and trailing spaces that change without notice, so a Stream Deck key
      # pinned to one literal name would break the next time the provider
      # renamed anything.
      use_node() {
        if [ -z "''${1:-}" ]; then
          echo "usage: vpn use <pattern>" >&2; exit 2
        fi
        target=$(nodes | grep -iP -m1 "\t.*$1" | cut -f2- || true)
        if [ -z "$target" ]; then
          say network-error-symbolic "no node matching '$1'"
          exit 1
        fi
        api_put "$target"
        say network-vpn-symbolic "$target"
      }

      case "''${1:-toggle}" in
        on)     turn_on ;;
        off)    turn_off ;;
        toggle) if [ "$cur" = DIRECT ]; then turn_on; else turn_off; fi ;;
        use)    use_node "''${2:-}" ;;
        # AUTO is excluded from `use` (it is a group, not a node), so it needs
        # its own verb -- a Stream Deck key has nothing else to call.
        auto)   api_put AUTO; say network-vpn-symbolic "AUTO" ;;
        status) printf '%s\n' "$cur" ;;
        list)   printf 'current: %s\n\n' "$cur"; nodes | while IFS=$'\t' read -r d n; do
                  if [ "$d" = 0 ]; then printf '   --   %s\n' "$n"; else printf '%5dms %s\n' "$d" "$n"; fi
                done ;;
        ip)     curl -fsS --max-time 15 https://cloudflare.com/cdn-cgi/trace \
                  | sed -n 's/^ip=//p;s/^loc=/ /p' | tr -d '\n'; echo ;;
        *)      echo "usage: vpn [toggle|on|off|auto|use <pattern>|status|list|ip]" >&2; exit 2 ;;
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
  # x-gvfs-show is what puts them in the Nautilus sidebar. GIO decides on its
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
      # "--update-input" "caelestia-shell"
      "--update-input" "vhelper"
      "--update-input" "openwave"
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
      notify() {
        ${pkgs.util-linux}/bin/runuser -u "$user" -- ${pkgs.coreutils}/bin/env \
          DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus \
          ${pkgs.libnotify}/bin/notify-send "$@"
      }
      # The whole generation, not its kernel. `operation = "boot"` stages every
      # upgrade for next boot, so a pending reboot is the normal outcome even
      # when nothing kernel-side moved -- comparing initrd/kernel/kernel-modules
      # instead reports success for any upgrade that only touched userspace,
      # which is most of them.
      booted="$(readlink -f /run/booted-system)"
      built="$(readlink -f /nix/var/nix/profiles/system)"
      if [ "$booted" = "$built" ]; then
        notify "HalruneNix" "Update successful." || true
      else
        choice=$(${pkgs.coreutils}/bin/timeout 15m \
          ${pkgs.util-linux}/bin/runuser -u "$user" -- ${pkgs.coreutils}/bin/env \
          DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus \
          ${pkgs.libnotify}/bin/notify-send -u critical \
            -A reboot="Reboot now" \
            "HalruneNix" "Update requires reboot.") || true
        if [ "$choice" = "reboot" ]; then
          ${pkgs.systemd}/bin/systemctl reboot
        fi
      fi
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

  boot.extraModulePackages = [ config.boot.kernelPackages.nct6687d ];
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

  systemd.packages = [ pkgs.hyprpolkitagent ];
  systemd.user.services.hyprpolkitagent.wantedBy = [ "graphical-session.target" ];

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

  services.geoclue2 = {
    enable = true;
    appConfig.gammastep = {
      isAllowed = true;
      isSystem = false;
      users = [ ];
    };
  };

  programs.ydotool.enable = true;

  programs.localsend = {
    enable = true;
    openFirewall = false;
  };

  services.scx = {
    enable = true;
    scheduler = "scx_lavd";
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

    chromium
    inputs.vhelper.packages.${pkgs.stdenv.hostPlatform.system}.default

    inputs.openwave.packages.${pkgs.stdenv.hostPlatform.system}.default

    filen-desktop

    heroic
    protonplus
    osu-lazer-bin
    foot
    yubioath-flutter
    claude-code
    lm_sensors

    nautilus
    file-roller
    mpv
    anytype

    discord
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

    wl-clipboard mangohud btop nvtopPackages.nvidia git gh wget

    cliphist

    trash-cli
    gammastep

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

    tg-ws-proxy
  ];

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
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
    description = "Assemble mihomo's config from the template and the subscription URL";
    before = [ "mihomo.service" ];
    requiredBy = [ "mihomo.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu
      url=$(tr -d '[:space:]' < /etc/mihomo/subscription.url)
      [ -n "$url" ]

      if [ ! -s /etc/mihomo/hwid ]; then
        tr -d '[:space:]' < /etc/machine-id > /etc/mihomo/hwid
        chmod 600 /etc/mihomo/hwid
      fi
      hwid=$(tr -d '[:space:]' < /etc/mihomo/hwid)

      install -d -m 700 /run/mihomo
      ${pkgs.gnused}/bin/sed -e "s|@SUBSCRIPTION_URL@|$url|" -e "s|@HWID@|$hwid|" \
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
  systemd.services.mihomo.serviceConfig = {
    Restart = "on-failure";
    RestartSec = "5s";
  };

  # NetworkManager-wait-online blocks boot until a link is up, which cost
  # 4.9s of every startup. Nothing here needs the network before the login
  # screen: mihomo retries, the flatpak and upgrade units are timer-driven,
  # and geoclue and fwupd-refresh are on demand.
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
