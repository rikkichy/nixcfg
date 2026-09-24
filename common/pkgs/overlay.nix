{ inputs }:

final: prev: {
  omp = inputs.omp.packages.${final.stdenv.hostPlatform.system}.omp.override (args: {
    bun = args.bun.overrideAttrs {
      nativeBuildInputs = [ final.unzip ] ++ final.lib.optionals final.stdenv.hostPlatform.isLinux [ final.autoPatchelfHook ];
      buildInputs = final.lib.optionals final.stdenv.hostPlatform.isLinux [ final.stdenv.cc.cc.lib final.zlib ];
    };
  });

  vpn = final.callPackage ./vpn.nix { };
}
