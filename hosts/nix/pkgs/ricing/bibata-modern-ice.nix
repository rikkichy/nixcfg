{ lib, stdenvNoCC, fetchzip, bibata-cursors }:

stdenvNoCC.mkDerivation {
  pname = "bibata-modern-ice";
  inherit (bibata-cursors) version;
  src = fetchzip {
    url = "https://github.com/ful1e5/Bibata_Cursor/releases/download/v${bibata-cursors.version}/Bibata-Modern-Ice.tar.xz";
    hash = "sha256-SG/NQd3K9DHNr9o4m49LJH+UC/a1eROUjrAQDSn3TAU=";
  };
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/icons/Bibata-Modern-Ice"
    cp -a cursors cursor.theme index.theme "$out/share/icons/Bibata-Modern-Ice/"
    install -Dm444 ${bibata-cursors.src}/LICENSE "$out/share/licenses/bibata-modern-ice/LICENSE"
    runHook postInstall
  '';
  meta = {
    description = "Prebuilt white Bibata cursors with rounded edges";
    homepage = "https://github.com/ful1e5/Bibata_Cursor";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.unix;
  };
}
