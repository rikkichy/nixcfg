{
  lib,
  stdenv,
  pkg-config,
  wayland,
  wayland-protocols,
  wayland-scanner,
  wlr-protocols,
}:

let
  layerShell = "${wlr-protocols}/share/wlr-protocols/unstable/wlr-layer-shell-unstable-v1.xml";
  # Layer shell references xdg_popup.
  xdgShell = "${wayland-protocols}/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml";
in
stdenv.mkDerivation {
  pname = "waydroid-pinch";
  version = "1";
  src = ./main.c;
  dontUnpack = true;

  strictDeps = true;
  nativeBuildInputs = [ pkg-config wayland-scanner ];
  buildInputs = [ wayland ];

  buildPhase = ''
    runHook preBuild
    wayland-scanner client-header ${layerShell} wlr-layer-shell-unstable-v1-client-protocol.h
    wayland-scanner private-code ${layerShell} wlr-layer-shell-unstable-v1-protocol.c
    wayland-scanner private-code ${xdgShell} xdg-shell-protocol.c
    $CC -O2 -Wall -Wextra -Werror -I. -o waydroid-pinch $src \
      wlr-layer-shell-unstable-v1-protocol.c xdg-shell-protocol.c \
      $(pkg-config --cflags --libs wayland-client) -lm
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 waydroid-pinch $out/bin/waydroid-pinch
    runHook postInstall
  '';

  meta = {
    mainProgram = "waydroid-pinch";
    platforms = lib.platforms.linux;
  };
}
