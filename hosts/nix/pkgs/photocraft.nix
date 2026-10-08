{ lib, appimageTools, fetchurl }:

let
  pname = "photocraft";
  version = "0.5.0";
  src = fetchurl {
    url = "https://github.com/storytold/photocraft/releases/download/v${version}/photocraft-${version}-linux-x86_64.AppImage";
    hash = "sha256-9U2GOAcFO738/6DWJO9+SdP9QTEMe7Ht5IU29pkp0i8=";
  };
  contents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  # Desktop entries and icons are installed by Nix, not the AppImage launcher.
  profile = ''
    export PHOTOCRAFT_NO_DESKTOP_INTEGRATION=1
  '';

  extraInstallCommands = ''
    mkdir -p $out/share
    cp -r ${contents}/usr/share/. $out/share/
  '';

  meta = {
    description = "Image editor with layers and PSD support";
    homepage = "https://github.com/storytold/photocraft";
    license = with lib.licenses; [ mit asl20 ];
    mainProgram = pname;
    platforms = [ "x86_64-linux" ];
  };
}
