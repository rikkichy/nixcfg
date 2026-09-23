{ pkgs, ... }:

{
  imports = [
    ../../modules/nix/home/quickshell.nix
    ../../modules/nix/home/fuzzel.nix
    ../../modules/nix/home/matugen.nix
    ../../modules/nix/home/network-reset.nix
    ../../modules/nix/home/applications.nix
    ../../modules/common/shell.nix
    ../../modules/common/zed.nix
    ../../modules/nix/home/foot.nix
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
