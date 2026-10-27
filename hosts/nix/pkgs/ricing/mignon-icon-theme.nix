{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  gtk3,
}:

stdenvNoCC.mkDerivation {
  pname = "mignon-icon-theme";
  version = "0-unstable-2026-08-22";

  src = fetchFromGitHub {
    owner = "igorfmoraes";
    repo = "Mignon-icon-theme";
    rev = "7a7ea5768f2826ca7e54eedf2aefa72092ab6fba";
    hash = "sha256-AKFRZngtjZ23/75j9TMIdPerp5J8JL7NQyDE/DwBMLM=";
  };

  nativeBuildInputs = [ gtk3 ];
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    export HOME="$TMPDIR"
    bash install.sh --dark
    mkdir -p "$out/share"
    mv "$HOME/.local/share/icons" "$out/share/icons"
    # Upstream includes aliases for Tela assets that Mignon does not ship.
    find "$out/share/icons" -xtype l -delete
    runHook postInstall
  '';

  meta = {
    description = "Flat pastel icons for Linux desktops";
    homepage = "https://github.com/igorfmoraes/Mignon-icon-theme";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
  };
}
