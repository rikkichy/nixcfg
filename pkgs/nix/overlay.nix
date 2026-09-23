{ inputs }:

final: prev: {
  omp = inputs.omp.packages.${final.stdenv.hostPlatform.system}.omp.override (args: {
    bun = args.bun.overrideAttrs {
      nativeBuildInputs = [ final.unzip ] ++ final.lib.optionals final.stdenv.hostPlatform.isLinux [ final.autoPatchelfHook ];
      buildInputs = final.lib.optionals final.stdenv.hostPlatform.isLinux [ final.stdenv.cc.cc.lib final.zlib ];
    };
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
  rhythia = final.callPackage ./gaming/rhythia.nix { };

  bibata-material-cursor = final.callPackage ./ricing/bibata-material-cursor.nix {
    src = inputs.bibata-cursor;
  };

  kotlin-lsp = final.callPackage ./kotlin-lsp.nix { };

  google-sans-rounded =
    final.callPackage ./ricing/google-sans-rounded.nix { };

  midnight-discord =
    final.callPackage ./ricing/midnight-discord.nix { };

  ananicy-cpp = prev.ananicy-cpp.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      find src -name "*.cpp" -exec sed -i "1i #include <cstring>\n#include <cstdint>" {} +
    '';
  });

  vpn = final.callPackage ./bypasses/vpn.nix { };
}
