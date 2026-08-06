# FlClashX -- a fork of FlClash (Mihomo/ClashMeta proxy client).
#
# Built from the upstream AppImage's contents, but deliberately *not* with
# appimageTools.wrapType2. That wraps the app in bubblewrap, and bwrap sets
# PR_SET_NO_NEW_PRIVS, which disables setuid entirely:
#
#   sudo: The "no new privileges" flag is set, which prevents sudo from
#   running as root.
#
# FlClashX escalates for TUN mode by running `sudo -S` and writing the
# password to its stdin, so under bwrap sudo exits before reading and the app
# reports `SocketException: Write failed (OS Error: Broken pipe, errno = 32)`.
# Patching the ELFs and running unsandboxed is what nixpkgs' own `flclash`
# does, and it keeps sudo working.
#
# nixpkgs has `flclash` (the parent project, built from source) if you ever
# want the non-fork.
{
  lib,
  stdenv,
  appimageTools,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  wrapGAppsHook3,
  gtk3,
  glib,
  libepoxy,
  libayatana-appindicator,
  libayatana-indicator,
  ayatana-ido,
  libdbusmenu,
  libdbusmenu-gtk3,
  keybinder3,
  mesa,
  libglvnd,
}:

let
  pname = "flclashx";
  version = "0.4.2";

  src = fetchurl {
    url = "https://github.com/pluralplay/FlClashX/releases/download/v${version}/FlClashX-linux-amd64.AppImage";
    # Matches the SHA256 upstream publishes next to the asset.
    hash = "sha256-jKqfL1kradD06uCrXxdpeJDRTvL65IF7S9A0I1CzA8I=";
  };

  contents = appimageTools.extractType2 { inherit pname version src; };
in
stdenv.mkDerivation {
  inherit pname version;

  src = contents;
  dontUnpack = true;

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook3
  ];

  buildInputs = [
    gtk3
    glib
    libepoxy
    libayatana-appindicator
    libayatana-indicator
    ayatana-ido
    libdbusmenu
    libdbusmenu-gtk3
    keybinder3
    mesa
    libglvnd
  ];

  installPhase = ''
    runHook preInstall

    # Flutter's GTK embedder resolves both the assets and the AOT blob from
    # the executable's own directory -- <exe dir>/data and <exe dir>/lib. The
    # AppImage splits those across usr/bin and usr/lib, which is why running it
    # as shipped gives "FlutterEngineCreateAOTData ... Invalid ELF path
    # specified" and a blank window. Lay it out the way the engine expects.
    mkdir -p $out/share/${pname}
    cp -r $src/usr/bin/. $out/share/${pname}/
    cp -r $src/usr/lib   $out/share/${pname}/lib

    test -e $out/share/${pname}/lib/libapp.so   # fail if upstream moves it
    test -d $out/share/${pname}/data            # ... or renames the assets

    chmod -R u+w $out/share/${pname}

    install -Dm444 $src/com.follow.clashx.desktop \
      $out/share/applications/com.follow.clashx.desktop
    substituteInPlace $out/share/applications/com.follow.clashx.desktop \
      --replace-fail 'Exec=FlClashX' "Exec=${pname}"

    install -Dm444 $src/FlClashX.png \
      $out/share/icons/hicolor/512x512/apps/FlClashX.png

    runHook postInstall
  '';

  # The helper FlClashX elevates is a sibling of the main binary, so both need
  # to be on PATH-adjacent paths it can find; it looks beside itself.
  postFixup = ''
    makeWrapper $out/share/${pname}/FlClashX $out/bin/${pname} \
      "''${gappsWrapperArgs[@]}"

    ln -s $out/share/${pname}/FlClashCore $out/bin/FlClashCore
  '';

  meta = {
    description = "Fork of FlClash, a multi-platform Mihomo-based proxy client";
    homepage = "https://github.com/pluralplay/FlClashX";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
  };
}
