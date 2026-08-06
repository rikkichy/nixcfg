{ config, pkgs, inputs, nixcfgPath, ... }:

{
  # The installer clones this repo as root, so without this it stays root-owned
  # and `ri` cannot write to it. That matters because home.nix maps hypr/ into
  # ~/.config/hypr with mkOutOfStoreSymlink specifically so Caelestia can
  # rewrite hypr/scheme/current.lua at runtime -- and Caelestia swallows the
  # resulting PermissionError, so it fails silently and takes most of the
  # Hyprland config down with it. Reasserted on every boot rather than left to
  # a step in the handbook that is easy to skip.
  #
  # Z is the recursive form; the "-" fields leave permission bits and age
  # alone, so this only ever corrects ownership. A path that does not exist is
  # a no-op, so this is harmless before the first clone.
  systemd.tmpfiles.rules = [
    "Z ${nixcfgPath} - ri users - -"
  ];

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  system.autoUpgrade = {
    enable = true;
    operation = "boot";
    flake = nixcfgPath;

    flags = [
      "--update-input" "nixpkgs"
      "--update-input" "home-manager"
      "--update-input" "caelestia-shell"
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
      booted="$(readlink /run/booted-system/{initrd,kernel,kernel-modules})"
      built="$(readlink /nix/var/nix/profiles/system/{initrd,kernel,kernel-modules})"
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

  nixpkgs.config.allowUnfree = true;

  boot.loader.timeout = 0;

  boot.loader.limine = {
    enable = true;
    efiSupport = true;
    maxGenerations = 10;
  };
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.systemd.enable = true;
  # Adds to the mapping hardware-configuration.nix already declares -- it must
  # not introduce a second one. Naming a different device that points at the
  # same partition makes initrd generate two systemd-cryptsetup@ units racing
  # for /dev/nvme0n1p2; the loser finds it busy, and when the loser was the one
  # named "cryptroot", /dev/mapper/cryptroot never appeared and the boot died
  # waiting for root. That is a race, so it survived three boots before failing.
  # Without allowDiscards, services.fstrim runs but no discard reaches the SSD
  # through the crypt layer.
  boot.initrd.luks.devices."cryptroot".allowDiscards = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  boot.kernelParams = [ "amd_pstate=active" ];

  boot.kernel.sysctl = {
    "vm.max_map_count" = 2147483642;
    "vm.swappiness" = 180;
    "vm.page-cluster" = 0;
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

  # Use the unit hyprpolkitagent ships rather than hand-writing one. A local
  # copy pointed ExecStart at $out/bin/hyprpolkitagent, which does not exist --
  # the binary is in $out/libexec and the package has no bin/ at all. The unit
  # failed 203/EXEC and restarted forever, so no polkit agent was ever
  # registered and every authorisation prompt fell back to pkexec's text mode.
  # systemd.packages installs it; NixOS does not act on a packaged unit's
  # [Install], so wantedBy still has to be stated.
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

    remotePlay.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;

    extraCompatPackages = [ pkgs.proton-ge-bin ];
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

  # Flatpak has no declarative install in nixpkgs, so this replaces the
  # "reboot, then one time only" step in the handbook. Idempotent: remote-add
  # is --if-not-exists and install is a no-op once the ref is present, so later
  # boots exit immediately.
  #
  # Driven by a timer rather than default.target on purpose. Pulling this into
  # the login target puts it in the path of "reloading user units for ri"
  # during nixos-rebuild, so a slow or hung flatpak wedges the whole switch --
  # which is exactly what happened. Off the target and behind TimeoutStartSec
  # it cannot stall activation no matter how badly the network behaves.
  #
  # dl.flathub.org, not flathub.org: the latter is unreachable from here and
  # remote-add hangs on it indefinitely rather than failing. Same repo.
  systemd.user.services.flatpak-bootstrap = {
    description = "Install the Flatpak apps this config expects";
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "10min";
    };
    # Deliberately not `|| true`. The first version swallowed every error, so
    # when remote-add quietly produced a remote with no refs both installs died
    # with "No remote refs found" and the unit still reported success -- it went
    # green having installed nothing, which is how this went unnoticed. Off the
    # activation path a failed unit costs nothing and shows up in
    # `systemctl --user --failed`, so let it fail.
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
    chromium
    inputs.vhelper.packages.${pkgs.stdenv.hostPlatform.system}.default

    inputs.openwave.packages.${pkgs.stdenv.hostPlatform.system}.default

    filen-desktop

    heroic
    foot
    yubioath-flutter
    claude-code

    nautilus
    file-roller
    mpv
    anytype

    pavucontrol
    zed-editor

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

    starship direnv zoxide eza fzf bat ripgrep lazygit jq fastfetch micro

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
  ];

  networking.hostName = "nix";
  networking.networkmanager.enable = true;

  # Mihomo (ClashMeta) as a system service rather than a GUI client. The GUI
  # clients keep their own copy of the config and push it into a core they
  # supervise, so the two desync and the UI reports a tunnel that is not there.
  # A systemd unit has one source of truth and fails loudly.
  #
  # The config itself is `dotfiles/mihomo.yaml`, in this repo, except for the
  # subscription URL: that is a credential and the repo is public. Rather than
  # keep the whole file out of git and hand-write it on every install, only the
  # URL lives outside, in /etc/mihomo/subscription.url, and gets spliced into a
  # copy at boot. So a fresh machine needs one line written by hand, not a
  # config reconstructed from memory.
  #
  # /run, not /etc, for the assembled file: it is derived state, it holds the
  # credential, and tmpfs means it cannot outlive a boot. configFile is a
  # *string* path rather than a `./` literal so nothing copies it into the
  # world-readable store -- the module warns about exactly this at the top --
  # and LoadCredential has systemd read it as root at start, so 0600 is fine.
  systemd.services.mihomo-config = {
    description = "Assemble mihomo's config from the template and the subscription URL";
    before = [ "mihomo.service" ];
    requiredBy = [ "mihomo.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    # No `|| true` and no placeholder fallback: a missing URL file should stop
    # mihomo from starting with a config that would silently proxy nothing.
    #
    # The HWID is seeded from machine-id but then *kept*, because machine-id is
    # regenerated by a fresh install while the panel counts device slots and
    # caps them. Reinstalling would otherwise burn a slot every time and need
    # one freed by hand before the VPN worked again. Back up /etc/mihomo
    # alongside the subscription link and a reinstall reuses the same slot.
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

  # tunMode grants CAP_NET_ADMIN to an otherwise heavily sandboxed DynamicUser
  # unit. That is the whole privilege story: no setuid binary, no passwordless
  # sudo, no writable copy of the app outside the store.
  services.mihomo = {
    enable = true;
    tunMode = true;
    webui = pkgs.metacubexd;
    configFile = "/run/mihomo/config.yaml";
  };

  # `tun.device: mihomo` in that config file is what ties these three together
  # -- change the name there and all three need changing here.
  #
  # NetworkManager assumes any tun device it sees and starts applying its own IP
  # configuration to an interface it does not own; two managers then race, and
  # NM re-evaluates exactly when the tunnel churns. The failure does not look
  # like "TUN failed": the link stays UP holding only its link-local v6 address
  # while the v4 address and every policy route quietly vanish, so traffic goes
  # straight out enp11s0 with the tunnel apparently connected. `ip -br addr show
  # mihomo` -- specifically whether the v4 address is present -- is the honest
  # signal.
  networking.networkmanager.unmanaged = [ "interface-name:mihomo" ];
  networking.firewall.trustedInterfaces = [ "mihomo" ];

  # trustedInterfaces alone is not enough, and this one is not mihomo-specific:
  # any TUN-mode client on this machine hits it. rpfilter runs in mangle
  # PREROUTING, ahead of the filter chains, so it drops before "trusted" is
  # consulted, and the NixOS default (`true`) means *strict*.
  #
  # The symptom is oddly narrow -- name resolution dies while raw-IP connections
  # tunnel perfectly -- and it hits exactly one address: whichever nameserver
  # /etc/resolv.conf lists, since DHCP hands out the router's LAN address.
  # Mihomo hijacks :53 and answers as the queried server, so the reply enters the
  # host on the tun device carrying a source from the LAN subnet. rpfilter then
  # re-runs a routing lookup on that source with `iif lo` and *no ports set*.
  # The missing ports are the trick: sing-tun installs
  #
  #   9001: not from all dport 53 lookup main suppress_prefixlength 0
  #
  # which is inverted on dport, so a lookup with dport 0 does take it, landing in
  # main -- where the connected LAN route has prefix length 24 and survives
  # suppress_prefixlength 0. The device comes back enp11s0, not the tun, and
  # strict mode drops the reply. A source outside any connected subnet matches
  # only the default route, which *is* suppressed, so it falls through to table
  # 2022, resolves to the tun, and passes. Hence 1.1.1.1 works as a nameserver
  # and the router does not.
  #
  # Ground truth is the counter split, since nothing is logged anywhere: during a
  # failing query `nstat` shows IpInReceives climbing while IpInDelivers holds
  # level and UdpInDatagrams never moves. The replies reach IP input and die.
  networking.firewall.checkReversePath = "loose";

  time.timeZone = "Europe/Moscow";
  i18n.defaultLocale = "en_US.UTF-8";

  programs.fish.enable = true;

  users.users.ri = {
    isNormalUser = true;
    shell = pkgs.fish;

    extraGroups = [ "wheel" "networkmanager" "gamemode" "ydotool" ];
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
