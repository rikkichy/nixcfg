{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:

stdenvNoCC.mkDerivation {
  pname = "google-sans-rounded";
  version = "0-unstable-2026-03-30";

  # Pinned to a commit rather than a branch: upstream ships the TTFs straight
  # on main with no tags or releases, so a bump means moving the rev and the
  # hash together by hand.
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

  # The family is "Google Sans Flex", not "Google Sans Rounded" -- the roundness
  # lives in the style ("Rounded", "Bold Rounded", "Light Rounded"), so the
  # regular weight is family "Google Sans Flex" style "Rounded". Configuring
  # anything by the name on the archive matches nothing and falls back to the
  # default sans without saying so.
  meta = {
    description = "Rounded cut of Google Sans Flex, roundness pushed to 100";
    homepage = "https://github.com/tiwa244/Google-Sans-Rounded";
    license = lib.licenses.ofl;
    platforms = lib.platforms.all;
  };
}
