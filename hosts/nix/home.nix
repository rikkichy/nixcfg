{ pkgs, ... }:

{
  imports = [
    ./modules/home/quickshell.nix
    ./modules/home/fuzzel.nix
    ./modules/home/matugen.nix
    ./modules/home/applications.nix
    ../../common/modules/discord.nix
    ../../common/modules/spotify.nix
    ../../common/modules/shell.nix
    ../../common/modules/ssh.nix
    ../../common/modules/zed.nix
    ./modules/home/foot.nix
  ];

  home.stateVersion = "26.05";

  home.pointerCursor = {
    enable = true;
    package = pkgs.callPackage ./pkgs/ricing/bibata-modern-ice.nix { };
    name = "Bibata-Modern-Ice";
    size = 24;
    gtk.enable = true;
    x11.enable = true;
  };

  home.packages = with pkgs; [
    papirus-icon-theme
    adw-gtk3

    libnotify

    bemoji

    hyprshot
  ];
}
