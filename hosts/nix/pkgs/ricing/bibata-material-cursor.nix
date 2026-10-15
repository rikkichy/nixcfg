{
  lib,
  fetchurl,
  fetchzip,
  stdenvNoCC,
  writeShellApplication,
  python3,
}:

let
  version = "1.5.0";
  helpers = fetchzip {
    url = "https://github.com/SakibShahariar/material-bibata-cursor/archive/refs/tags/v${version}.tar.gz";
    hash = "sha256-2BTYH3T+EVOoQHkQnGNA8vuGkrLwmqcUZYfS3yFssHc=";
  };
  themes = stdenvNoCC.mkDerivation {
    pname = "bibata-material-themes";
    inherit version;
    src = fetchurl {
      url = "https://github.com/SakibShahariar/material-bibata-cursor/releases/download/v${version}/bibata-material-dark-v${version}.tar.gz";
      hash = "sha256-igz93WB4fGWgeM5JS1cIwdaPPldhGP3gcBlJ7bQMugQ=";
    };
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/share/icons" "$out/share/doc/bibata-material-cursor"
      for theme in Bibata-Material-*; do
        [ "$theme" != Bibata-Material-Classic ] || continue
        test -s "$theme/manifest.hl"
        test -s "$theme/index.theme"
        test -d "$theme/hyprcursors"
        test -d "$theme/cursors"
        test -d "$theme/cursors_scalable"
        cp -r "$theme" "$out/share/icons/"
      done
      cp INSTALL.txt ${helpers}/LICENSE "$out/share/doc/bibata-material-cursor/"
      runHook postInstall
    '';
    meta = {
      description = "Prebuilt dark Material Bibata cursor palettes";
      homepage = "https://github.com/SakibShahariar/material-bibata-cursor";
      license = with lib.licenses; [ mit gpl3Plus ];
      platforms = lib.platforms.unix;
    };
  };
in
writeShellApplication {
  name = "bibata-material-select";
  runtimeInputs = [ python3 ];
  text = ''
    export PYTHONPATH=${helpers}/scripts
    exec python3 ${./bibata-material-select.py} \
      ${themes}/share/icons ${helpers}/themes.json "$@"
  '';
  meta = {
    description = "Select a prebuilt Material Bibata cursor palette from a wallpaper accent";
    homepage = "https://github.com/SakibShahariar/material-bibata-cursor";
    license = with lib.licenses; [ mit gpl3Plus ];
    mainProgram = "bibata-material-select";
    platforms = lib.platforms.unix;
  };
}
