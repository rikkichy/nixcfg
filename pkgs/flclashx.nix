# FlClashX -- a fork of FlClash (Mihomo/ClashMeta proxy client).
#
# Packaged from the upstream AppImage rather than built from source: it is a
# Flutter app with a Go core, so a source build means pinning both toolchains
# and vendoring two dependency sets for no gain over the binary upstream
# already publishes and signs.
#
# nixpkgs has `flclash` (the parent project) if you ever want the non-fork.
{
  lib,
  appimageTools,
  fetchurl,
}:

let
  pname = "flclashx";
  version = "0.4.2";

  src = fetchurl {
    url = "https://github.com/pluralplay/FlClashX/releases/download/v${version}/FlClashX-linux-amd64.AppImage";
    # Matches the SHA256 upstream publishes next to the asset.
    hash = "sha256-jKqfL1kradD06uCrXxdpeJDRTvL65IF7S9A0I1CzA8I=";
  };

  # Unpacked separately so the .desktop entry and icons can be lifted out --
  # wrapType2 only installs the binary itself.
  contents = appimageTools.extractType2 { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  # The AppImage does not bundle these. libayatana-appindicator is the tray
  # icon; without it the binary fails to start at all rather than degrading.
  extraPkgs = pkgs: with pkgs; [
    libepoxy
    libayatana-appindicator
    libayatana-indicator
    ayatana-ido
    libdbusmenu
    libdbusmenu-gtk3
  ];

  extraInstallCommands = ''
    # Upstream names the entry after the app id, not the binary, and its
    # Exec/Icon are bare names that only resolve inside the AppImage mount.
    install -Dm444 ${contents}/com.follow.clashx.desktop \
      $out/share/applications/com.follow.clashx.desktop

    substituteInPlace $out/share/applications/com.follow.clashx.desktop \
      --replace-fail 'Exec=FlClashX' "Exec=$out/bin/${pname}"

    # The icon sits at the AppImage root; put it where the icon theme spec
    # looks, keeping the name the desktop entry's Icon= already refers to.
    install -Dm444 ${contents}/FlClashX.png \
      $out/share/icons/hicolor/512x512/apps/FlClashX.png
  '';

  meta = {
    description = "Fork of FlClash, a multi-platform Mihomo-based proxy client";
    homepage = "https://github.com/pluralplay/FlClashX";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
  };
}
