{
  lib,
  appimageTools,
  fetchurl,
}:

let
  pname = "nokochat";
  version = "2.1.0";

  src = fetchurl {
    url = "https://dl.noko.chat/NokoChat-${version}-x86_64.AppImage";
    hash = "sha256-V7Vzg2K7E6JFtkky6/QNWGCrwzIkeDnqCuzgmAHhBAo=";
  };

  contents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraPkgs =
    pkgs: with pkgs; [
      libGL
      libx11
      libxext
      libxrender
      libxtst
      libxi
      libxrandr
      libxcursor
      fontconfig
      freetype
      libsecret
    ];

  extraInstallCommands = ''
    install -Dm444 ${contents}/chat.noko.NokoChat.desktop \
      $out/share/applications/chat.noko.NokoChat.desktop
    install -Dm444 ${contents}/nokochat.png \
      $out/share/icons/hicolor/512x512/apps/nokochat.png

    # The bundled entry launches `NokoChat`; wrapType2 names the wrapper after
    # pname, so the entry would otherwise point at a binary that is not on PATH.
    substituteInPlace $out/share/applications/chat.noko.NokoChat.desktop \
      --replace-fail 'Exec=NokoChat' 'Exec=${pname}'
  '';

  meta = {
    description = "Roleplay chat that hits different";
    homepage = "https://noko.chat";
    license = lib.licenses.unfree;
    mainProgram = pname;
    platforms = [ "x86_64-linux" ];
  };
}
