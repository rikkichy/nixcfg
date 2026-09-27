{ pkgs, lib, ... }:

{
  imports = [
    ../../common/modules/nh.nix
    ./modules/system/nix.nix
    ./modules/system/homebrew.nix
    ./modules/system/preferences.nix
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "discord" "spotify" ];

  programs.fish.enable = true;

  networking.hostName = "ne";
  system.primaryUser = "rii";
  users.users.rii.home = "/Users/rii";
  users.users.rii.shell = pkgs.fish;

  # Keep the initial compatibility version when upgrading nix-darwin.
  system.stateVersion = 6;
}
