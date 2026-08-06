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

  # Where flclashx-install stages a writable copy. Must be on a filesystem that
  # is neither read-only nor nosuid -- the whole point is that the app can make
  # its core setuid there and have it stay that way.
  stagedDir = "/var/lib/flclashx";

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

    # Nothing clever here on purpose -- see the launcher below. The core stays
    # a plain file next to FlClashX, which is where the app looks for it:
    #
    #   String get corePath => join(executableDirPath, "FlClashCore...")
    #
    # and it makes that file setuid itself, via sudo, on first run.

    install -Dm444 $src/com.follow.clashx.desktop \
      $out/share/applications/com.follow.clashx.desktop
    substituteInPlace $out/share/applications/com.follow.clashx.desktop \
      --replace-fail 'Exec=FlClashX' "Exec=${pname}"

    install -Dm444 $src/FlClashX.png \
      $out/share/icons/hicolor/512x512/apps/FlClashX.png

    runHook postInstall
  '';

  # Launch from a writable copy, not from the store.
  #
  # FlClashX enables TUN by making its own core setuid -- `sudo sh -c 'chown
  # root:root "$1" && chmod +sx "$1"'` -- once, then running it directly.
  # checkIsAdmin() re-tests that with `stat -c '%U:%G %A'`, requiring the mode
  # to contain "rws". The store is read-only *and* mounted nosuid, so the chmod
  # can never stick and setuid would be ignored even if it did: the app asks
  # for the password on every single launch, forever.
  #
  # Neither indirection works either. A symlink to a setuid wrapper fails
  # because GNU stat does not dereference by default, so checkIsAdmin sees
  # "lrwxrwxrwx". Capabilities fail because the check runs before the core is
  # ever tried, so a cap_net_admin core is never exercised.
  #
  # macOS has the same design and solves it by copying the core somewhere
  # writable on launch. Do the same: flclashx-install stages this tree into
  # /var/lib/flclashx, and the app then does exactly what upstream intends --
  # prompt once, chmod, never again. RPATHs are absolute into the store, so the
  # copy still resolves its libraries; data/ and lib/libapp.so resolve relative
  # to the executable and are part of the copy.
  # Wraps a launcher rather than ${stagedDir}/FlClashX directly: makeWrapper
  # refuses a target that does not exist at build time, and the staged copy is
  # created at boot. The wrapper still sets the GTK/GI environment, then hands
  # over to the copy.
  postFixup = ''
    cat > $out/share/${pname}/launch <<EOF
    #!/bin/sh
    exec ${stagedDir}/FlClashX "\$@"
    EOF
    sed -i 's/^    //' $out/share/${pname}/launch
    chmod 555 $out/share/${pname}/launch

    makeWrapper $out/share/${pname}/launch $out/bin/${pname} \
      "''${gappsWrapperArgs[@]}"
  '';

  # Consumed by the staging service in configuration.nix.
  passthru.stagedDir = stagedDir;

  meta = {
    description = "Fork of FlClash, a multi-platform Mihomo-based proxy client";
    homepage = "https://github.com/pluralplay/FlClashX";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
  };
}
