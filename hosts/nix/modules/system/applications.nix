{ pkgs, inputs, ... }:

{
  programs.git.enable = true;

  environment.systemPackages = with pkgs; [
    omp

    inputs.helium.packages.${pkgs.stdenv.hostPlatform.system}.default
    inputs.vhelper.packages.${pkgs.stdenv.hostPlatform.system}.default

    inputs.openwave.packages.${pkgs.stdenv.hostPlatform.system}.default

    filen-desktop


    foot
    yubioath-flutter
    age-plugin-yubikey
    yubikey-manager
    pam_u2f


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

    android-tools

    hyprpolkitagent

    wl-clipboard nvtopPackages.nvidia yt-dlp

    glib

    bluez

    hyprpicker
    adwaita-icon-theme
    qtengine

    playerctl
    xdg-user-dirs

    tg-ws-proxy
    trash-cli
  ];

  programs.localsend = {
    enable = true;
    openFirewall = false;
  };

  programs.obs-studio = {
    enable = true;
  };

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

  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };

  services.printing.enable = true;

}
