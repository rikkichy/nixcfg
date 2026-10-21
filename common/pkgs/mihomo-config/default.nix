{ lib, rustPlatform }:
rustPlatform.buildRustPackage {
  pname = "mihomo-config";
  version = "1.0.0";
  src = lib.cleanSource ./.;
  cargoLock.lockFile = ./Cargo.lock;
  meta = {
    description = "Private runtime configuration renderer for Mihomo";
    mainProgram = "mihomo-config";
    platforms = lib.platforms.unix;
  };
}
