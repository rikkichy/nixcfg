{ lib, pkgs, inputs, nixcfgPath, ... }:

{
  environment.systemPackages = lib.mkAfter [
    (if pkgs.stdenv.hostPlatform.isDarwin then
      inputs.nixpkgs-nh.legacyPackages.${pkgs.stdenv.hostPlatform.system}.nh.override {
        inherit (pkgs) nix-output-monitor;
      }
    else pkgs.nh)
  ];
  environment.variables.NH_FLAKE = nixcfgPath;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
