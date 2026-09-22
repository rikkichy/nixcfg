{ pkgs, ... }:

{
  programs.hyprland = {
    enable = true;
    withUWSM = true;
    xwayland.enable = true;
  };

  systemd.packages = [ pkgs.hyprpolkitagent pkgs.hyprsunset ];
  systemd.user.services.hyprpolkitagent.wantedBy = [ "graphical-session.target" ];

  systemd.user.services.hyprsunset.wantedBy = [ "graphical-session.target" ];

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

  services.gnome.gnome-keyring.enable = true;
  security.pam.services.greetd.enableGnomeKeyring = true;

  programs.ydotool.enable = true;

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
    nerd-fonts.departure-mono
  ];
}
