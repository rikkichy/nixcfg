{ pkgs, ... }:

{
  imports = [
    ./hardware.nix
    ./storage.nix
    ../../modules/nixos/common/nix.nix
    ../../modules/nixos/desktop/maintenance.nix
    ./boot.nix
    ./hardware-policy.nix
    ./lighting.nix
    ../../modules/nixos/desktop/security.nix
    ../../modules/nixos/desktop/session.nix
    ../../modules/nixos/desktop/audio.nix
    ../../modules/nixos/desktop/gaming.nix
    ../../modules/nixos/desktop/flatpak.nix
    ../../modules/nixos/desktop/networking.nix
    ../../modules/nixos/common/base_apps.nix
    ../../modules/nixos/desktop/base_apps.nix
    ../../modules/nixos/common/locale.nix
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
