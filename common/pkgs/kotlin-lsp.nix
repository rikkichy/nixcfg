{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  unzip,
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
let
  isDarwin = stdenv.hostPlatform.isDarwin;
in

stdenv.mkDerivation (finalAttrs: {
  pname = "kotlin-lsp";
  version = "263.6379.0";

  src = fetchurl {
    # JetBrains' Darwin .sit download is a ZIP archive.
    name = "kotlin-server-${finalAttrs.version}.${if isDarwin then "zip" else "tar.gz"}";
    url = "https://download.jetbrains.com/language-server/kotlin-server/${finalAttrs.version}/kotlin-server-${finalAttrs.version}${if isDarwin then "-aarch64.sit" else ".tar.gz"}";
    hash =
      if isDarwin then
        "sha256-6+8uE81K3E7J4ECEuEgACj7HqdKRfGTyaVdM4u/p7K0="
      else
        "sha256-q4ykRV3C/F/hok2yvMxGwQQlTSxGUVXEJR7mXfjz98w=";
  };

  nativeBuildInputs = [ makeWrapper ]
    ++ lib.optionals isDarwin [ unzip ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
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
  dontStrip = true;
  # Keep the native Darwin launcher and bundled JBR code signatures intact.
  dontFixup = isDarwin;

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
    platforms = [ "x86_64-linux" "aarch64-darwin" ];
  };
})
