{ lib, pkgs, inputs, nixcfgPath, ... }:

{
  environment.systemPackages = lib.mkAfter [
    (if pkgs.stdenv.hostPlatform.isDarwin then
      pkgs.nh.override {
        nh-unwrapped = inputs.nixpkgs-nh.legacyPackages.${pkgs.stdenv.hostPlatform.system}.nh-unwrapped;
      }
    else pkgs.nh)
  ];
  environment.variables.NH_FLAKE = nixcfgPath;
}
