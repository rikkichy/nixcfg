{ inputs }:

final: prev: {
  quickshell = prev.quickshell.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      # QLocalSocket emits channelReadyRead after readyRead; do not destroy its sender.
      substituteInPlace src/wayland/hyprland/ipc/connection.cpp \
        --replace-fail 'delete requestSocket;' 'requestSocket->deleteLater();'
    '';
  });

  tg-ws-proxy = final.callPackage ./tg-ws-proxy.nix {
    src = inputs.tg-ws-proxy;
  };

  nokochat = final.callPackage ./nokochat.nix { };

  bibata-material-cursor = final.callPackage ./bibata-material-cursor.nix {
    src = inputs.bibata-cursor;
  };

  kotlin-lsp = final.callPackage ./kotlin-lsp.nix { };

  google-sans-rounded =
    final.callPackage ./google-sans-rounded.nix { };

  midnight-discord =
    final.callPackage ./midnight-discord.nix { };

  ananicy-cpp = prev.ananicy-cpp.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      find src -name "*.cpp" -exec sed -i "1i #include <cstring>\n#include <cstdint>" {} +
    '';
  });

  vpn = final.callPackage ./vpn.nix { };
}
