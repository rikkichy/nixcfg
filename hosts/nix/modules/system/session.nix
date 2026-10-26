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
    # Keep the Russian PAM touch cue readable on the plain console.
    font = "${pkgs.terminus_font}/share/consolefonts/ter-k32n.psf.gz";
    earlySetup = true;
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
        command = "${config.services.greetd.package}/bin/agreety --cmd 'uwsm start hyprland-uwsm.desktop'";
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
