{
  lib,
  rustPlatform,
  zip,
}:

rustPlatform.buildRustPackage {
  pname = "vts-opendeck";
  version = "0.1.0";
  src = lib.cleanSource ./.;
  cargoLock.lockFile = ./Cargo.lock;
  nativeBuildInputs = [ zip ];

  installPhase = ''
    runHook preInstall
    plugin=$out/share/opendeck/plugins/com.rikkichy.vtubestudio.sdPlugin
    mkdir -p "$plugin/bin"
    cp -r assets/. "$plugin/"
    install -m755 target/*/release/vts-opendeck "$plugin/bin/vts-opendeck"
    mkdir -p "$out/bin"
    ln -s "$plugin/bin/vts-opendeck" "$out/bin/vts-opendeck"
    (cd "$out/share/opendeck/plugins" && zip -qr "$out/share/com.rikkichy.vtubestudio.streamDeckPlugin" com.rikkichy.vtubestudio.sdPlugin)
    runHook postInstall
  '';

  meta = {
    description = "Native OpenDeck hotkeys and model switching for VTube Studio";
    mainProgram = "vts-opendeck";
    platforms = [ "x86_64-linux" ];
  };
}
