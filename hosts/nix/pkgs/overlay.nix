{ inputs }:

final: prev: {
  # Disabled for stock binary-cache reuse; keep both workarounds available.
  /*
  quickshell = prev.quickshell.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace src/wayland/hyprland/ipc/connection.cpp \
        --replace-fail 'delete requestSocket;' 'requestSocket->deleteLater();'
    '';
  });

  hyprland = prev.hyprland.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./ricing/hyprland-refresh-cursor.patch ];
  });
  */

  tg-ws-proxy = final.callPackage ./bypasses/tg-ws-proxy.nix {
    src = inputs.tg-ws-proxy;
  };

  nokochat = final.callPackage ./nokochat.nix { };
  photocraft = final.callPackage ./photocraft.nix { };
  filmcraft = final.callPackage ./filmcraft.nix { };

  bibata-material-cursor = final.callPackage ./ricing/bibata-material-cursor.nix { };

  kotlin-lsp = final.callPackage ./kotlin-lsp.nix { };

  google-sans-rounded =
    final.callPackage ./ricing/google-sans-rounded.nix { };
}
