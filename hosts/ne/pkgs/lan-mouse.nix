{ lib, stdenvNoCC, fetchurl, unzip }:

stdenvNoCC.mkDerivation rec {
  pname = "lan-mouse-bin";
  version = "0.11.0";

  src = fetchurl {
    url = "https://github.com/feschber/lan-mouse/releases/download/v${version}/lan-mouse-macos-arm64.zip";
    hash = "sha256-X/mWXQW+fxJbHXW55yWdh07JiqCGzkABJSK8JUBlAKk=";
  };

  nativeBuildInputs = [ unzip ];
  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  # Preserve the upstream app bundle and its bundled library paths.
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications"
    cp -R "Lan Mouse.app" "$out/Applications/"
    runHook postInstall
  '';

  meta = {
    description = "Share a mouse and keyboard between computers over the network";
    homepage = "https://github.com/feschber/lan-mouse";
    license = lib.licenses.gpl3Only;
    platforms = [ "aarch64-darwin" ];
  };
}
