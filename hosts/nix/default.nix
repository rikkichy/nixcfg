{ pkgs, ... }:

{
  imports = [
    ./hardware.nix
    ./storage.nix
    ./modules/system/nix.nix
    ./modules/system/maintenance.nix
    ./boot.nix
    ./hardware-policy.nix
    ./lighting.nix
    ./modules/system/security.nix
    ./modules/system/session.nix
    ./modules/system/audio.nix
    ./modules/system/gaming.nix
    ./modules/system/flatpak.nix
    ./modules/system/networking.nix
    ./modules/system/cli.nix
    ./modules/system/applications.nix
    ./modules/system/locale.nix
  ];

  networking.hostName = "nix";

  nixpkgs.config.allowUnfree = true;

  programs.fish.enable = true;

  users.users.ri = {
    isNormalUser = true;
    shell = pkgs.fish;

    extraGroups = [ "wheel" "networkmanager" "gamemode" "ydotool" "docker" ];
  };

  system.stateVersion = "26.05";
}
