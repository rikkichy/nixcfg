{ pkgs, ... }:

{
  imports = [
    ../../modules/home/linux-desktop/quickshell.nix
    ../../modules/home/linux-desktop/fuzzel.nix
    ../../modules/home/linux-desktop/matugen.nix
    ../../modules/home/linux-desktop/network-reset.nix
    ../../modules/home/linux-desktop/applications.nix
    ../../modules/home/common/shell.nix
    ../../modules/home/linux-desktop/foot.nix
  ];

  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    papirus-icon-theme
    adw-gtk3

    libnotify

    bemoji

    hyprshot

    matugen
  ];
}
