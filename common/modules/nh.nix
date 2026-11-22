{ lib, pkgs, nixcfgPath, ... }:

{
  environment.systemPackages = lib.mkAfter [ pkgs.nh ];
  environment.variables.NH_FLAKE = nixcfgPath;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
