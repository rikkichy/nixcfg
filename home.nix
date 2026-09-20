{ pkgs, ... }:

{
  imports = [
    ./home/wayle.nix
    ./home/fuzzel-tweaks.nix
    ./home/matugen.nix
    ./home/network-reset.nix
    ./home/applications.nix
    ./home/shell.nix
  ];

  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    papirus-icon-theme
    adw-gtk3
    wayle

    libnotify

    bemoji

    hyprshot

    matugen
  ];
}
