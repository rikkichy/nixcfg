{ pkgs, ... }:

{
  programs.git.enable = true;

  environment.systemPackages = with pkgs; [
    brave-origin

    filen-desktop
    lan-mouse


    foot
    yubioath-flutter
    age-plugin-yubikey
    yubikey-manager
    pam_u2f


    lm_sensors

    file-roller
    catfish

    swayimg
    mpv
    qbittorrent
    (obsidian.override { electron = electron_42; })
    bitwarden-desktop
    onlyoffice-desktopeditors

    (discord.override { withEquicord = true; })
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
    package = pkgs.obs-studio.override { cudaSupport = true; };
    enableVirtualCamera = true;
  };

  services.gvfs.enable = true;

  programs.thunar = {
    enable = true;
    plugins = with pkgs; [
      thunar-volman
      thunar-archive-plugin
      thunar-vcs-plugin
    ];
  };

  services.tumbler.enable = true;

  programs.chromium = {
    enable = true;
    defaultSearchProviderEnabled = true;
    defaultSearchProviderSearchURL = "https://www.google.com/search?q={searchTerms}";
    extraOpts = {
      TranslateEnabled = false;
      PasswordManagerEnabled = false;
      DefaultSearchProviderName = "Google";
      NewTabPageLocation = "file://${pkgs.writeText "brave-new-tab.html" ''
        <!doctype html>
        <html lang="en">
        <meta charset="utf-8">
        <meta name="color-scheme" content="dark">
        <title>New Tab</title>
        <style>html { background: #000; }</style>
        <body></body>
        </html>
      ''}";
    };
  };

  virtualisation.docker = {
    enable = true;
    enableOnBoot = false;
    autoPrune.enable = true;
  };

  virtualisation.waydroid = {
    enable = true;
    package = pkgs.waydroid-nftables;
  };

  services.printing.enable = false;

}
