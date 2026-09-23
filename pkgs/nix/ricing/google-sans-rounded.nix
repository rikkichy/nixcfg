{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:

stdenvNoCC.mkDerivation {
  pname = "google-sans-rounded";
  version = "0-unstable-2026-03-30";

  src = fetchFromGitHub {
    owner = "tiwa244";
    repo = "Google-Sans-Rounded";
    rev = "c6101c550b996381971c1e093be72fc4225bc77b";
    hash = "sha256-UUK5hdQsFIzLu/lLUJdzISL8aFKkgrV4mnRW0xvcnHc=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm444 -t $out/share/fonts/truetype *.ttf
    runHook postInstall
  '';

  meta = {
    description = "Rounded cut of Google Sans Flex, roundness pushed to 100";
    homepage = "https://github.com/tiwa244/Google-Sans-Rounded";
    license = lib.licenses.ofl;
    platforms = lib.platforms.all;
  };
}
