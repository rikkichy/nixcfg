{ pkgs, ... }:

let
  martaLauncher = pkgs.writeShellScriptBin "marta" ''
    exec /Applications/Marta.app/Contents/Resources/Launcher "$@"
  '';
in
{
  home.packages = [ martaLauncher ];

  home.file."Library/Application Support/org.yanex.marta/conf.marco".text = ''
    behavior {
        theme "Matugen"
        layout {
            showActionBar false
        }
    }
  '';
}
