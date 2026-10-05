{ pkgs, inputs, ... }:

{
  programs.git.enable = true;

  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
  };

  environment.systemPackages = with pkgs; [
    omp

    (brave-origin.overrideAttrs (old: {
      postInstall = (old.postInstall or "") + ''
        cp ${pkgs.writeText "brave-origin-initial-preferences" (builtins.toJSON {
          brave.new_tab_page = {
            show_stats = false;
            show_background_image = false;
          };
        })} "$out/opt/brave.com/brave-origin/initial_preferences"
      '';
    }))
    inputs.vhelper.packages.${pkgs.stdenv.hostPlatform.system}.default

    inputs.openwave.packages.${pkgs.stdenv.hostPlatform.system}.default

    filen-desktop


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
    obsidian
    bitwarden-desktop
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
    enableVirtualCamera = true;
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
    defaultSearchProviderEnabled = true;
    defaultSearchProviderSearchURL = "https://www.google.com/search?q={searchTerms}";
    extraOpts = {
      TranslateEnabled = false;
      PasswordManagerEnabled = false;
      DefaultSearchProviderName = "Google";
    };
  };

  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };

  services.printing.enable = true;

}
