{ config, pkgs, lib, ... }:

{
  imports = [
    ./system/storage.nix
    ./system/nix.nix
    ./system/boot.nix
    ./system/hardware.nix
    ./system/lighting.nix
    ./system/security.nix
    ./system/desktop.nix
    ./system/audio.nix
    ./system/gaming.nix
    ./system/applications.nix
    ./system/networking.nix
    ./system/packages.nix
  ];

  networking.hostName = "nix";

  time.timeZone = "Europe/Moscow";
  i18n.defaultLocale = "en_US.UTF-8";

  programs.fish = {
    enable = true;
    shellInit = ''
      set -gx NH_FLAKE ${lib.escapeShellArg config.programs.nh.flake}
    '';
  };

  users.users.ri = {
    isNormalUser = true;
    shell = pkgs.fish;

    extraGroups = [ "wheel" "networkmanager" "gamemode" "ydotool" "docker" ];
  };

  system.stateVersion = "26.05";
}
