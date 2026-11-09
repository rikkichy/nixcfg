{ config, inputs, pkgs, ... }:

let
  waydroidNvidia = inputs.waydroid-nvidia;
  waydroid = pkgs.callPackage ../../pkgs/waydroid.nix {
    waydroidNvidia = waydroidNvidia.packages.${pkgs.stdenv.hostPlatform.system};
  };
in

{
  programs.git.enable = true;

  environment.systemPackages = with pkgs; [
    google-chrome

    filen-desktop


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
    obsidian
    bitwarden-desktop
    onlyoffice-desktopeditors

    discord
    telegram-desktop

    pavucontrol

    android-tools

    wl-clipboard nvtopPackages.nvidia yt-dlp

    glib

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
      # uBlock Origin Lite: installed (user may disable, not remove) and configured
      # through its managed storage schema.
      ExtensionSettings.ddkjiahejlhfcafbddmgiahcphecmpfh = {
        installation_mode = "normal_installed";
        update_url = "https://clients2.google.com/service/update2/crx";
      };
      "3rdparty".extensions.ddkjiahejlhfcafbddmgiahcphecmpfh = {
        defaultFiltering = "complete";
        disableFirstRunPage = true;
        rulesets = [
          "+annoyances-cookies"
          "+annoyances-overlays"
          "+annoyances-social"
          "+annoyances-widgets"
          "+annoyances-notifications"
          "+annoyances-others"
          "+annoyances-ai"
          "+rus-0"
          "+rus-1"
        ];
      };
      NewTabPageLocation = "file://${pkgs.writeText "chromium-new-tab.html" ''
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
    package = waydroid;
  };

  # waydroid-nvidia's container drop-in, restated because NixOS owns the unit directory:
  # start after the NVIDIA render node exists and refuse an ungated vendor image.
  systemd.services.waydroid-container = {
    wants = [ "sys-subsystem-waydroid_nvidia-render.device" ];
    after = [ "sys-subsystem-waydroid_nvidia-render.device" ];
    path = waydroid.runtimePath ++ [ config.system.path ];
    preStart = "${waydroid}/lib/waydroid-nvidia/native/dev/driver-mode verify-active";
  };
  services.udev.packages = [
    (pkgs.writeTextDir "lib/udev/rules.d/70-waydroid-nvidia-gpu.rules" (
      builtins.readFile "${waydroidNvidia.inputs.wnv-src}/packaging/aur/waydroid-nvidia-bin/waydroid-nvidia-gpu.rules"
    ))
  ];

}
