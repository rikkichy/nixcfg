{ config, pkgs, ... }:

{
  programs.hyprland = {
    enable = true;
    withUWSM = true;
    xwayland.enable = true;
  };

  services.speechd.enable = false;

  systemd.packages = [ pkgs.hyprpolkitagent pkgs.hyprsunset ];
  systemd.user.services.hyprpolkitagent.wantedBy = [ "graphical-session.target" ];

  systemd.user.services.hyprsunset.wantedBy = [ "graphical-session.target" ];

  programs.dconf.enable = true;

  xdg.portal = {
    enable = true;
    config.common.default = [ "hyprland" "gtk" ];
  };

  console = {
    # KOI8-R's Unicode map covers Cyrillic, box drawing and the fire glyphs.
    font = "${pkgs.terminus_font}/share/consolefonts/ter-k32n.psf.gz";
    earlySetup = true;
    colors = [
      "0b1220" "e78284" "a6d189" "e5c890"
      "42698f" "babbf1" "8daac4" "d6ebff"
      "18304d" "ea999c" "b5df9c" "f1d8a5"
      "7ebaff" "c8c4ff" "b6e9ff" "e6f5ff"
    ];
  };

  services.greetd = {
    enable = true;
    useTextGreeter = true;
    settings = {
      initial_session = {
        command = "uwsm start hyprland-uwsm.desktop";
        user = "ri";
      };

      default_session = {
        command = "${pkgs.coreutils}/bin/env LANGUAGE=ru_RU ${pkgs.tuigreet}/bin/tuigreet --config ${../../dotfiles/ricing/tuigreet/nix-frost.toml} --user ri --cmd 'uwsm start hyprland-uwsm.desktop'";
        user = "greeter";
      };
    };
  };

  services.gnome.gnome-keyring.enable = true;
  security.pam.services.greetd = {
    enableGnomeKeyring = true;
    # greetd delegates to login; its useDefaultRules=false ignores u2f.enable.
    rules.auth.u2f = {
      order = config.security.pam.services.greetd.rules.auth.login.order - 10;
      control = "sufficient";
      modulePath = "${pkgs.pam_u2f}/lib/security/pam_u2f.so";
      settings = config.security.pam.u2f.settings // {
        cue_prompt = "Прикоснитесь к YubiKey";
      };
    };
  };

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
  ];
}
