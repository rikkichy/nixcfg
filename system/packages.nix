{ pkgs, lib, inputs, ... }:

{
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
    sops
    age
    age-plugin-yubikey
    yubikey-manager
    pam_u2f

    (inputs.omp.packages.${pkgs.stdenv.hostPlatform.system}.omp.override (args: {
      # nix-bun's dependency predicates still use deprecated stdenv platform aliases.
      bun = args.bun.overrideAttrs {
        nativeBuildInputs = [ unzip ] ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
        buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib zlib ];
      };
    }))

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

  fonts.packages = with pkgs; [
    noto-fonts

    noto-fonts-color-emoji
    noto-fonts-cjk-sans

    nerd-fonts.jetbrains-mono
    nerd-fonts.caskaydia-cove

    google-sans-rounded
    nerd-fonts.departure-mono
  ];
}
