{
  lib,
  pkgs,
  nixcfgPath,
  ...
}:

{
  nix.package = pkgs.lix;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.channel.enable = false;

  environment.systemPackages = lib.mkAfter [ pkgs.nh ];
  environment.variables.NH_FLAKE = nixcfgPath;
}
