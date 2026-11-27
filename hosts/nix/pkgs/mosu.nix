{
  appimageTools,
  fetchurl,
  lib,
}:

appimageTools.wrapType2 (finalAttrs: {
  pname = "mosu";
  version = "2026.1126.0";

  src = fetchurl {
    url = "https://github.com/morasooma/mosu/releases/download/v${finalAttrs.version}/mosu-${finalAttrs.version}-linux-x64.AppImage";
    hash = "sha256-RrYTvTKPbH5mrrNMQZLtsX5ZzHz1/8KH69p3HoXwqOw=";
  };

  extraPkgs = pkgs: [ pkgs.icu ];

  # Both clients use the same .NET named pipe by default.
  privateTmp = true;
  # A caller's working directory may be under the host /etc, which is not mounted.
  chdirToPwd = false;
  profile = ''
    export TMPDIR=/tmp
    export XDG_CONFIG_HOME="$HOME/.config/morasooma"
    export XDG_DATA_HOME="$HOME/.local/share/morasooma"
    export OSU_EXTERNAL_UPDATE_PROVIDER=1
  '';

  extraInstallCommands = ''
    install -Dm444 ${finalAttrs.contents}/mosu.ico "$out/share/pixmaps/mosu.ico"
  '';

  meta = {
    description = "Morasooma's osu!lazer client";
    homepage = "https://morasooma.net/";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
  };
})
