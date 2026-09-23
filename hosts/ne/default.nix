{ pkgs, ... }:

{
  nixpkgs.hostPlatform = "aarch64-darwin";

  nix.package = pkgs.lix;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  environment.systemPackages = [ pkgs.nh ];

  programs.fish.enable = true;

  networking.hostName = "ne";
  system.primaryUser = "rii";
  users.users.rii.home = "/Users/rii";
  users.users.rii.shell = pkgs.fish;

  # Keep the initial compatibility version when upgrading nix-darwin.
  system.stateVersion = 6;
}
