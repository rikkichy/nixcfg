{ pkgs, ... }:

let
  martaLauncher = pkgs.writeShellScriptBin "marta" ''
    exec /Applications/Marta.app/Contents/Resources/Launcher "$@"
  '';
in
{
  home.packages = [ martaLauncher ];
}
