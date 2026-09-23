{ pkgs, ... }:

{
  imports = [
    ./hardware.nix
    ./storage.nix
    ../../modules/nix/system/nix.nix
    ../../modules/nix/system/maintenance.nix
    ./boot.nix
    ./hardware-policy.nix
    ./lighting.nix
    ../../modules/nix/system/security.nix
    ../../modules/nix/system/session.nix
    ../../modules/nix/system/audio.nix
    ../../modules/nix/system/gaming.nix
    ../../modules/nix/system/flatpak.nix
    ../../modules/nix/system/networking.nix
    ../../modules/nix/system/cli.nix
    ../../modules/nix/system/applications.nix
    ../../modules/nix/system/locale.nix
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
