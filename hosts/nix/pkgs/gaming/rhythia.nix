{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
  makeWrapper,
  makeDesktopItem,
  copyDesktopItems,
  steam-run,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "rhythia";
  version = "0.1.2";

  src = fetchurl {
    url = "https://github.com/Rhythia/Client/releases/download/${finalAttrs.version}/Linux.zip";
    hash = "sha256-hSxkGxTBeHTFtHWObVNDXPHM8mhSO92rq/bnzzaztXg=";
  };

  icon = fetchurl {
    url = "https://raw.githubusercontent.com/Rhythia/Client/${finalAttrs.version}/textures/RhythiaSquircle.png";
    hash = "sha256-gLztNxDmNUI5VVbpK1/d3+tyi4+EfQDVw4vGiChP0ck=";
  };

  nativeBuildInputs = [ unzip makeWrapper copyDesktopItems ];
  dontBuild = true;
  # Godot embeds the game pack in the executable; preserve the upstream binary.
  dontFixup = true;

  desktopItems = [
    (makeDesktopItem {
      name = "rhythia";
      desktopName = "Rhythia";
      comment = "Aim-based rhythm game — Rhythia/Client";
      exec = "rhythia -- %F";
      icon = "rhythia";
      categories = [ "Game" ];
      startupWMClass = "Rhythia";
      mimeTypes = [
        "application/x-rhythia-sspm"
        "application/x-rhythia-map"
        "application/x-rhythia-replay"
      ];
    })
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/rhythia" "$out/bin"
    cp -r . "$out/lib/rhythia/"
    chmod +x "$out/lib/rhythia/Rhythia.x86_64"
    cp ${./rhythia-open.gd} "$out/lib/rhythia/rhythia-open.gd"
    cat > "$out/lib/rhythia/override.cfg" <<EOF
    [autoload]
    XdgOpen="*$out/lib/rhythia/rhythia-open.gd"
    EOF
    makeWrapper ${lib.getExe steam-run} "$out/bin/rhythia" \
      --chdir "$out/lib/rhythia" \
      --add-flags "$out/lib/rhythia/Rhythia.x86_64" \
      --prefix LD_LIBRARY_PATH : "$out/lib/rhythia"
    install -Dm644 "$icon" "$out/share/icons/hicolor/1000x1000/apps/rhythia.png"
    install -Dm644 ${./rhythia-mime.xml} "$out/share/mime/packages/rhythia.xml"
    runHook postInstall
  '';

  meta = {
    description = "Aim-based rhythm game from Rhythia/Client";
    homepage = "https://github.com/Rhythia/Client";
    license = lib.licenses.agpl3Only;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "rhythia";
  };
})
