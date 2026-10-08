{ lib, appimageTools, fetchurl }:

let
  pname = "filmcraft";
  version = "0.4.0";
  src = fetchurl {
    url = "https://github.com/storytold/filmcraft/releases/download/v${version}/filmcraft-${version}-linux-x86_64.AppImage";
    hash = "sha256-2EEN6nsrBk7eHq2H3YlLyjU3pN/aGkQpcViEn1a6LUw=";
  };
  contents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    mkdir -p $out/share
    cp -r ${contents}/usr/share/. $out/share/
  '';

  meta = {
    description = "Video editor with color grading and audio mixing";
    homepage = "https://github.com/storytold/filmcraft";
    license = with lib.licenses; [ mit asl20 ];
    mainProgram = pname;
    platforms = [ "x86_64-linux" ];
  };
}
