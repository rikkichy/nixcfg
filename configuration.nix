{ config, pkgs, inputs, ... }:

{
  ## Nix ######################################################

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Hands-off updates. Once a day -- catching up right after boot if
  # the PC was off, the timer is persistent (verified, default true) --
  # this pulls the latest inputs and builds the new system in the
  # background, then STAGES it for the next boot ("boot", not
  # "switch"): a kernel/nvidia bump never touches the running session,
  # you simply start into it next power-on. Bad update? Pick the
  # previous generation in the Limine menu.
  # Watch it: journalctl -u nixos-upgrade.service
  # NOTE: the service runs as root, so flake.lock in your repo becomes
  # root-owned after the first run; `sudo chown ri flake.lock`
  # if git ever complains. Prefer live userland updates instead (with
  # the classic risk of a running session drifting from new libs)?
  # Change operation to "switch".
  #
  # GOTCHA once /home/ri/nixcfg is a git repo: `--flake /home/ri/nixcfg` makes
  # nix treat it as a git tree and evaluate only COMMITTED content. An edit you
  # forgot to commit is not an error -- the nightly build just quietly rebuilds
  # the last commit, and you get to wonder why your change never took. Commit,
  # or use `path:/home/ri/nixcfg` to opt out of the git handling.
  #
  # `--update-input` is still accepted by nixos-rebuild-ng (it is a real flag
  # in flake_eval_flags, and the autoUpgrade module's own docs still recommend
  # exactly this pattern), but nix itself now prints "'--update-input' is a
  # deprecated alias for 'flake update' and will be removed in a future
  # version" for each one. It works today; when it goes, replace the flags
  # below with a `nix flake update` in an ExecStartPre.
  system.autoUpgrade = {
    enable = true;
    operation = "boot";
    flake = "/home/ri/nixcfg";
    # These are APPENDED to what the module itself computes -- with `flake`
    # set it already contributes [ "--refresh" "--flake /home/ri/nixcfg" ],
    # and listOf merges rather than overrides. No need to repeat them.
    flags = [
      "--update-input" "nixpkgs"
      "--update-input" "home-manager"
      "--update-input" "caelestia-shell"
      "--update-input" "vhelper"
      "--update-input" "openwave"
    ];
    dates = "daily";
    randomizedDelaySec = "10min";
  };

  # Desktop notifications for the upgrade above. Runs only on success
  # (systemd OnSuccess). Uses the module's own reboot-needed test:
  # compare kernel/initrd/modules of the running system vs the staged
  # one. Same -> "Update successful."; different -> a persistent
  # notification with a [Reboot now] action button (waits up to 15min
  # for a click, then gives up quietly). All notify calls are sent as
  # your user onto the session bus, so Caelestia renders them.
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

  ## Boot #####################################################

  boot.loader.timeout = 0;   # hold an arrow key during POST for the menu

  boot.loader.limine = {
    enable = true;
    efiSupport = true;
    maxGenerations = 10;   # ~150MB each in the ESP. Make the ESP 2GB.

    # OPTIONAL tamper detection for the unencrypted ESP (option names
    # verified in nixpkgs master 2026-08-04). Uncomment once stable:
    # enrollConfig = true;
    # panicOnChecksumMismatch = true;
    # enableEditor = false;   # editable cmdline defeats the point
  };
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.systemd.enable = true;

  # TRIM through LUKS. fstrim below does nothing for the SSD unless
  # discards pass the crypt layer. Copy the device NAME from the
  # luks entry nixos-generate-config wrote into
  # hardware-configuration.nix (usually "luks-<uuid>"), then uncomment:
  # boot.initrd.luks.devices."luks-XXXXXXXX".allowDiscards = true;

  # Mainline-ядро (на 2026-08-04: 7.1.6): ночной автоапдейт тянет
  # каждую новую версию. Trade-off на NVIDIA: в первые дни новой
  # ветки драйвер в nixpkgs иногда отстаёт -- ночная сборка падает,
  # система спокойно живёт на текущем поколении до починки
  # (staged-обновления это прощают). Вернуться на LTS: удалить
  # строку (дефолт nixpkgs = linux_default, сейчас 6.18).
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # NOTE (verified in nixpkgs nvidia module 2026-08-04): do NOT add
  # nvidia-drm.modeset or NVreg_PreserveVideoMemoryAllocations here.
  # modesetting.enable and powerManagement.enable below already add
  # them (plus nvidia-drm.fbdev where applicable).
  boot.kernelParams = [ "amd_pstate=active" ];

  boot.kernel.sysctl = {
    # NOT set by the steam module (checked) -- ours is load-bearing.
    "vm.max_map_count" = 2147483642;   # several Proton titles need it
    "vm.swappiness" = 180;             # correct for zram, not disk swap
    "vm.page-cluster" = 0;
  };

  zramSwap.enable = true;   # 50% of RAM is the default

  ## GPU ######################################################

  hardware.graphics = {
    enable = true;
    enable32Bit = true;   # Steam will not launch without this
  };

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;       # adds nvidia-drm.modeset=1 itself
    open = true;
    nvidiaSettings = true;
    powerManagement.enable = true;   # adds NVreg_PreserveVideoMemoryAllocations=1
  };

  ## Desktop ##################################################

  programs.hyprland = {
    enable = true;
    withUWSM = true;
    xwayland.enable = true;
  };
  # hyprland's portal is added automatically via programs.hyprland
  # (portalPackage -> extraPortals); only gtk needs listing below.

  programs.dconf.enable = true;   # GTK theming needs this

  # Раскладка us+ru живёт ТОЛЬКО в hyprland.conf (единственное место,
  # которое сессия реально читает):
  #   input { kb_layout = us,ru  kb_options = grp:alt_shift_toggle }
  # Консоль/TTY намеренно оставлены us-only: русский в голой консоли
  # -- источник случайных опечаток, а не польза.

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = [ "hyprland" "gtk" ];   # avoids ambiguity
  };

  services.greetd = {
    enable = true;
    settings = {
      # Autologin on boot: LUKS already gates physical access, so the
      # greeter would just be a second password at every start.
      initial_session = {
        command = "uwsm start hyprland-uwsm.desktop";
        user = "ri";
      };
      # Logging OUT still lands on tuigreet (rescue / user switch).
      # pkgs.tuigreet, NOT pkgs.greetd.tuigreet: the greetd scope is
      # gone on unstable; the old path fails eval (verified 2026-08-04).
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd 'uwsm start hyprland-uwsm.desktop'";
        user = "greeter";
      };
    };
  };

  security.rtkit.enable = true;   # also sets security.polkit.enable (verified)

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Secret service. Without it Chromium nags for a keyring on every
  # launch and nothing can store credentials.
  # AUTOLOGIN NOTE: PAM unlocks the keyring with your typed password;
  # autologin types none, so the keyring would stay locked. Decision:
  # give the login keyring a BLANK password -- at the FIRST keyring
  # dialog after install, leave it empty and confirm. At rest it's
  # under LUKS (the real protection); a running session reads an
  # unlocked keyring regardless of its password, so nothing is lost.
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.greetd.enableGnomeKeyring = true;

  # Location, for gammastep's night light (started from hypr/execs.lua).
  # enableDemoAgent defaults to true and gives you the agent as a systemd USER
  # service, which is why the `/usr/lib/geoclue-2.0/demos/agent` exec-once from
  # the CachyOS config is gone rather than rewritten.
  # The appConfig entry is load-bearing: geoclue refuses to answer app-ids it
  # has not been told about, and gammastep just exits with "unable to get
  # location from provider" if it isn't listed.
  services.geoclue2 = {
    enable = true;
    appConfig.gammastep = {
      isAllowed = true;
      isSystem = false;
      users = [ ];   # empty = every user
    };
  };

  # CTRL+SHIFT+ALT+V in hypr/keybinds.lua types the last clipboard entry via
  # ydotool. The bare package is not enough -- the bind needs ydotoold running
  # and the uinput permissions; this module sets up both plus the ydotool group.
  programs.ydotool.enable = true;

  ## Scheduling ###############################################

  # The part of the CachyOS feel that survives on stock everything:
  # scx_lavd (gaming-tuned, per-LLC domains -- suits your 2-CCD
  # V-Cache split). Try scx_rusty if a game stutters under lavd.
  services.scx = {
    enable = true;
    scheduler = "scx_lavd";
  };

  services.ananicy = {
    enable = true;
    package = pkgs.ananicy-cpp;
    rulesProvider = pkgs.ananicy-rules-cachyos;   # plain nixpkgs pkg
  };

  ## Gaming ###################################################

  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;
    # Игры по локалке с ноутбуком: стриминг и передача установленных
    # игр между машинами без интернета.
    remotePlay.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
    # GE-Proton, prebuilt from nixpkgs. Valve's own Proton 11 already
    # defaults to ntsync; GE adds codecs/patches gacha and non-Steam
    # ports tend to want. Heroic downloads its own runners regardless.
    extraCompatPackages = [ pkgs.proton-ge-bin ];
  };

  # capSysNice REMOVED 2026-08-04: confirmed to crash Steam-launched
  # gamescope (bwrap capability error; nixpkgs #351516, still open,
  # re-reported June 2026). Re-add only if the issue closes.
  programs.gamescope.enable = true;

  programs.gamemode.enable = true;   # module creates the group itself

  # Screen capture on Hyprland goes through the portal you already
  # have (xdg-desktop-portal-hyprland) -- pick the PipeWire source
  # in OBS. NVENC works via the nvidia driver at runtime.
  programs.obs-studio = {
    enable = true;
    # plugins = with pkgs.obs-studio-plugins; [ ... ];
    # enableVirtualCamera adds the v4l2loopback module -- on the stock
    # kernel it's prebuilt by hydra, so it's safe to flip on if you
    # ever need a virtual cam:
    # enableVirtualCamera = true;
  };

  ## Apps #####################################################

  services.pcscd.enable = true;   # required by yubioath-flutter
  services.udev.packages = [
    pkgs.yubikey-personalization
    # Wave XLR access rule baked into the openwave package -- the
    # app's first-run permission check finds it already in place.
    inputs.openwave.packages.${pkgs.system}.default

    # Stream Deck access for OpenDeck (Flatpak) -- generates content
    # identical to upstream's src-tauri/bundle/40-streamdeck.rules
    # (fetched & diffed 2026-08-04): every model incl. Modules, usb +
    # hidraw, uaccess-tagged so the seated user gets access, no group.
    (pkgs.runCommand "streamdeck-udev-rules" { } ''
      mkdir -p $out/lib/udev/rules.d
      r=$out/lib/udev/rules.d/40-streamdeck.rules
      for pid in 0060 0063 006c 006d 0080 0084 0086 008f 0090 00b3 009a 00a5 00b8 00b9 00ba 00c6; do
        printf 'SUBSYSTEM=="usb", ATTRS{idVendor}=="0fd9", ATTRS{idProduct}=="%s", MODE="0660", TAG+="uaccess"\n' "$pid" >> $r
        printf 'KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0fd9", ATTRS{idProduct}=="%s", MODE="0660", TAG+="uaccess"\n' "$pid" >> $r
      done
    '')
  ];

  # Nautilus wants this for trash, network mounts, and MTP --
  # i.e. browsing your phone's storage, pairs with adb below.
  services.gvfs.enable = true;
  # ...а монтирует gvfs через udisks2 -- без него кнопка "подключить"
  # на флешке в Nautilus молча не работает.
  services.udisks2.enable = true;

  # Browser extensions, declaratively: ExtensionInstallForcelist
  # policy. Chromium fetches them from the Web Store on first launch
  # and they SELF-UPDATE there -- no pinning, no rot. If one fails to
  # appear, re-check its ID against the store page URL.
  programs.chromium = {
    enable = true;
    extensions = [
      "ddkjiahejlhfcafbddmgiahcphecmpfh" # uBlock Origin Lite
      "mnjggcdmjocbbbhaepdhchncahnbgone" # SponsorBlock
      "gebbhagfogifgggkldgodflihgfeippi" # Return YouTube Dislike
      "ammjkodgmmoknidbanneddgankgfejfh" # 7TV (ID verified via store URL)
    ];

    # Arbitrary Chromium enterprise policies. These show as "managed"
    # (greyed out) in chrome://settings -- that's the declarative
    # contract; change them here, not there.
    extraOpts = {
      TranslateEnabled = false;         # no "translate this page?" popups
      PasswordManagerEnabled = false;   # Bitwarden's job, not Chromium's
    };
  };

  services.flatpak.enable = true;

  # Flatpak (Sober, OpenDeck) в том же ночном ритуале, что и система:
  # ежедневно, с догоном после включения. Обновления применяются при
  # следующем запуске приложения, ребут не нужен.
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
  # One time, after first boot:
  #   flatpak remote-add --user --if-not-exists flathub \
  #     https://flathub.org/repo/flathub.flatpakrepo
  #   flatpak install --user flathub org.vinegarhq.Sober
  #   flatpak install --user flathub me.amankhanna.opendeck

  environment.systemPackages = with pkgs; [
    chromium
    inputs.vhelper.packages.${pkgs.system}.default
                       # your own VTubing helper. protontricks is
                       # wrapped in; it installs its bundled obs-pwvideo
                       # into ~/.config/obs-studio/plugins itself and
                       # self-checks the libobs soname (obs-pwvideo is
                       # NOT in nixpkgs -- verified 2026-08-04).
    inputs.openwave.packages.${pkgs.system}.default
                       # your Wave XLR control app. NOTE: the in-app
                       # "install audio service" writes a user unit
                       # pinned to a store path that rots on rebuilds;
                       # re-run it after updates, or ask me for a
                       # declarative HM service using openwave-daemon.
    filen-desktop      # network-drive mount is broken (nixpkgs
                       # #412631); sync folders work
    heroic
    foot
    yubioath-flutter

    nautilus           # GNOME file manager (gvfs above: trash/MTP/network)
    file-roller        # archive create/extract inside Nautilus
    mpv
    anytype           # local-first P2P notes -- genuinely no web
                      # version, so this Electron app earns its slot
    pavucontrol       # caelestia's bar audio click opens this (its default)
    zed-editor        # if an extension's downloaded LSP ever fails
                      # to run, swap to zed-editor.fhs
    android-tools      # adb + fastboot. programs.adb was REMOVED from
                       # nixpkgs (PR #454366): systemd 258 grants device
                       # access via uaccess -- no adbusers group, no
                       # udev rules package needed anymore.

    hyprpolkitagent   # polkit being enabled is NOT enough -- without an
                      # agent running, GUI privilege prompts silently fail

    wineWow64Packages.stable
                       # native Wine: OpenDeck runs Windows-built
                       # Stream Deck plugins through it (the Wine
                       # Flatpak cannot be used). Swap to .full if a
                       # plugin wants bundled mono/gecko; drop it if
                       # all your plugins are Linux-native.
                       # NOT wineWowPackages -- that attrset now evaluates
                       # through lib.warn ("no longer preferred by upstream,
                       # use wineWow64Packages"), so every single rebuild
                       # prints the deprecation. Same 64+32-bit build.

    wl-clipboard mangohud btop nvtopPackages.nvidia git wget

    ## Everything hypr/ shells out to #########################
    # These are all invoked by NAME from the Lua config (execs.lua /
    # keybinds.lua), so they have to be on PATH -- a missing one fails
    # silently at session start, which is the worst way to find out.

    cliphist          # execs.lua: wl-paste --watch cliphist store, and
                      # SUPER+V -> `caelestia clipboard`. Also comes in via
                      # caelestia-cli's closure; pinned here so it survives
                      # if that ever changes upstream.
    trash-cli         # execs.lua: trash-empty 30
    gammastep         # execs.lua: night light (paired with the
                      # services.geoclue2 block further up)
    glib              # execs.lua: `gsettings set ...` for the cursor theme.
                      # gsettings lives in glib's bin output; dconf being
                      # enabled is not the same thing as having the CLI.
    bluez             # execs.lua: mpris-proxy. hardware.bluetooth.enable
                      # runs bluetoothd but puts nothing on your PATH.
    hyprpicker        # SUPER+SHIFT+C colour picker
    adwaita-icon-theme  # the cursor theme hypr/variables.lua now names
    qtengine          # hypr/env.lua sets QT_QPA_PLATFORMTHEME=qtengine;
                      # without the plugin Qt apps ignore the scheme.
                      # caelestia writes qtengine/config.json at runtime.
    playerctl         # MPRIS control behind the media keys
    xdg-user-dirs     # ~/Downloads etc., which the file rules assume

    ## fish's interactive line (see programs.fish in home.nix) ##
    starship direnv zoxide eza fzf bat ripgrep lazygit jq fastfetch micro
  ];

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";   # Chromium/Electron -> Wayland
    # ntsync is default in Proton 11+ / GE; PROTON_NO_NTSYNC opts out.
  };

  fonts.packages = with pkgs; [
    noto-fonts
    # NOT noto-fonts-emoji -- that attribute was converted from an alias into
    # a hard `throw` in nixpkgs on 2025-10-27, so it aborts evaluation of the
    # whole flake rather than warning. The package is noto-fonts-color-emoji.
    noto-fonts-color-emoji
    noto-fonts-cjk-sans   # CJK, matching the noto-fonts-cjk you had on CachyOS

    # caelestia-shell bakes caskaydia-cove into its own fontconfig, so the
    # shell renders regardless -- but the configs you actually carried over
    # ask for JetBrains Mono NF by name and would silently fall back without
    # it: foot.ini (JetBrains Mono Nerd Font), fuzzel.ini and hypr's groupbar
    # font_family (JetBrains Mono NF).
    nerd-fonts.jetbrains-mono
    nerd-fonts.caskaydia-cove
  ];

  ## System ###################################################

  networking.hostName = "nix";
  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Moscow";
  i18n.defaultLocale = "en_US.UTF-8";

  # fish -- логин-шелл ri (shell ниже); foot подхватит автоматически,
  # bash остаётся для скриптов.
  programs.fish.enable = true;

  users.users.ri = {
    isNormalUser = true;
    shell = pkgs.fish;
    # "ydotool" is not cosmetic: ydotoold's socket is created 0660 root:ydotool,
    # so without the group the paste-type bind fails with a permission error
    # on the socket rather than anything that mentions ydotool.
    extraGroups = [ "wheel" "networkmanager" "gamemode" "ydotool" ];
  };

  # Печать: современные принтеры работают драйверлесс (IPP
  # Everywhere), Avahi находит сетевые. Если твой старый/USB и не
  # обнаружится -- скажи модель, добавлю пакет в
  # services.printing.drivers.
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
