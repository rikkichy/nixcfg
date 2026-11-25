{ inputs }:

final: prev: {
  # Disabled for stock binary-cache reuse; retain the Quickshell workaround.
  /*
  quickshell = prev.quickshell.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace src/wayland/hyprland/ipc/connection.cpp \
        --replace-fail 'delete requestSocket;' 'requestSocket->deleteLater();'
    '';
  });
  */

  vpn = final.callPackage ../../../common/pkgs/vpn.nix { };

  tg-ws-proxy = final.callPackage ../../../common/pkgs/tg-ws-proxy.nix {
    src = inputs.tg-ws-proxy;
  };

  waydroid-pinch = final.callPackage ./waydroid-pinch { };
  mosu = final.callPackage ./mosu.nix { };

  google-sans-rounded =
    final.callPackage ./ricing/google-sans-rounded.nix { };
  mignon-icon-theme =
    final.callPackage ./ricing/mignon-icon-theme.nix { };
}
