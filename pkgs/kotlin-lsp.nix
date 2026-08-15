{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  alsa-lib,
  fontconfig,
  freetype,
  libGL,
  libx11,
  libxcrypt-legacy,
  libxext,
  libxi,
  libxkbcommon,
  libxrender,
  libxtst,
  wayland,
  zlib,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "kotlin-lsp";
  version = "262.9593.0";

  # JetBrains ships the standalone server only from its own CDN -- the GitHub
  # releases of Kotlin/kotlin-lsp carry no assets, just links to these URLs.
  src = fetchurl {
    url = "https://download-cdn.jetbrains.com/language-server/kotlin-server/${finalAttrs.version}/kotlin-server-${finalAttrs.version}.tar.gz";
    hash = "sha256-LZnY4Zj75KqPRIHjd5lyTOlIA7TqEqYLQWBA4/zXzF4=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  # The archive bundles its own JetBrains Runtime, so the JDK to patch against
  # is inside the tarball rather than a dependency of this derivation. Its AWT
  # backends are dead weight for a headless server, but autoPatchelf refuses to
  # leave any of them unresolved.
  buildInputs = [
    (lib.getLib stdenv.cc.cc)
    alsa-lib
    fontconfig
    freetype
    libGL
    libx11
    libxcrypt-legacy
    libxext
    libxi
    libxkbcommon
    libxrender
    libxtst
    wayland
    zlib
  ];

  dontConfigure = true;
  dontBuild = true;
  # Everything here is prebuilt; stripping only risks breaking the JBR.
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/kotlin-lsp
    cp -r . $out/share/kotlin-lsp

    makeWrapper $out/share/kotlin-lsp/bin/intellij-server $out/bin/kotlin-lsp

    runHook postInstall
  '';

  meta = {
    description = "JetBrains Kotlin Language Server (standalone LSP)";
    homepage = "https://github.com/Kotlin/kotlin-lsp";
    license = lib.licenses.unfree;
    mainProgram = "kotlin-lsp";
    platforms = [ "x86_64-linux" ];
  };
})
