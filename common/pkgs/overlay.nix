{ inputs }:

final: prev: {
  omp = inputs.omp.packages.${final.stdenv.hostPlatform.system}.default;

  vpn = final.callPackage ./vpn.nix { };
}
