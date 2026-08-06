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

    # FlClashX enables TUN by making its core setuid root -- it shells out to
    # `chown root:root "$1" && chmod +sx "$1"` under sudo, once, and thereafter
    # runs it directly. On NixOS the store is immutable, so that chmod can
    # never stick: the app re-asks for the password on every launch, the bit
    # never appears, and it refuses to bring TUN up at all.
    #
    # Capabilities do not help. The app gates on the setuid bit *before* it
    # will try, so a cap_net_admin core is simply never exercised -- measured:
    # the capability core ran, and no tun device or route was ever created.
    #
    # So point the name the app looks for at security.wrappers' setuid copy.
    # stat() through the symlink sees the bit and the check passes; exec runs
    # the wrapper, which is root and execs the real binary below.
    #
    # This drops the non-NixOS fallback the previous dispatcher had. A setuid
    # binary cannot live in the store, and a shell script cannot be setuid, so
    # there is no form that satisfies the check and still works standalone.
    mv $out/share/${pname}/FlClashCore $out/share/${pname}/FlClashCore.real
    ln -s /run/wrappers/bin/flclash-core $out/share/${pname}/FlClashCore

    install -Dm444 $src/com.follow.clashx.desktop \
      $out/share/applications/com.follow.clashx.desktop
    substituteInPlace $out/share/applications/com.follow.clashx.desktop \
      --replace-fail 'Exec=FlClashX' "Exec=${pname}"

    install -Dm444 $src/FlClashX.png \
      $out/share/icons/hicolor/512x512/apps/FlClashX.png

    runHook postInstall
  '';

  # No bin/FlClashCore symlink: share/flclashx/FlClashCore now points at
  # /run/wrappers/bin, so a second hop through it is dangling inside $out and
  # noBrokenSymlinks fails the build. Nothing needs the core on PATH -- the app
  # execs it by its own sibling path.
  postFixup = ''
    makeWrapper $out/share/${pname}/FlClashX $out/bin/${pname} \
      "''${gappsWrapperArgs[@]}"
  '';

  # security.wrappers points at this; exposed so configuration.nix does not
  # have to hardcode the layout.
  passthru.corePath = "share/${pname}/FlClashCore.real";

  meta = {
    description = "Fork of FlClash, a multi-platform Mihomo-based proxy client";
    homepage = "https://github.com/pluralplay/FlClashX";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
  };
}
