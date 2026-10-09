{ inputs }:

final: prev: {
  filen-desktop = prev.filen-desktop.overrideAttrs (old: {
    # Defer native rebuilds until canvas's installed headers can be patched.
    npmRebuildFlags = (old.npmRebuildFlags or [ ]) ++ [ "--ignore-scripts" ];
    preBuild = (old.preBuild or "") + ''
      substituteInPlace node_modules/canvas/src/{CharData,FontParser}.h \
        --replace-fail '#pragma once' $'#pragma once\n#include <cstdint>'
      npm rebuild
      patchShebangs node_modules
    '';
  });

  fuzzel = prev.fuzzel.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      # Wheel selection must not be reset to the row under a stationary cursor.
      substituteInPlace wayland.c \
        --replace-fail 'select_hovered_match(seat, true);' 'wayl_refresh(wayl);'
    '';
  });

  quickshell = prev.quickshell.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace src/wayland/hyprland/ipc/connection.cpp \
        --replace-fail 'delete requestSocket;' 'requestSocket->deleteLater();'
    '';
  });

  hyprland = prev.hyprland.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./ricing/hyprland-refresh-cursor.patch ];
  });

  tg-ws-proxy = final.callPackage ./bypasses/tg-ws-proxy.nix {
    src = inputs.tg-ws-proxy;
  };

  nokochat = final.callPackage ./nokochat.nix { };
  photocraft = final.callPackage ./photocraft.nix { };
  filmcraft = final.callPackage ./filmcraft.nix { };

  bibata-material-cursor = final.callPackage ./ricing/bibata-material-cursor.nix {
    src = inputs.bibata-cursor;
  };

  kotlin-lsp = final.callPackage ./kotlin-lsp.nix { };

  google-sans-rounded =
    final.callPackage ./ricing/google-sans-rounded.nix { };
}
