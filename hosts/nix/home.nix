{ pkgs, ... }:

{
  imports = [
    ./modules/home/quickshell.nix
    ./modules/home/fuzzel.nix
    ./modules/home/matugen.nix
    ./modules/home/network-reset.nix
    ./modules/home/applications.nix
    ../../common/modules/shell.nix
    ../../common/modules/zed.nix
    ./modules/home/foot.nix
  ];

  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    papirus-icon-theme
    adw-gtk3

    libnotify

    bemoji

    hyprshot
  ];
}
