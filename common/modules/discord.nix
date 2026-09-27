{ config, pkgs, lib, ... }:

let
  equicordDataDir =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "${config.home.homeDirectory}/Library/Application Support/Equicord"
    else
      "${config.xdg.configHome}/Equicord";
in
{
  _module.args.equicordDataDir = equicordDataDir;

  home.file."${equicordDataDir}/themes/wallpaper.theme.css" = {
    source = ../dotfiles/discord/theme.css;
    force = true;
  };

  home.activation.equicordSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    settings=${lib.escapeShellArg "${equicordDataDir}/settings/settings.json"}
    if [ ! -e "$settings" ]; then
      run mkdir -p "$(dirname "$settings")"
      run cp ${
        pkgs.writeText "equicord-settings.json" (
          builtins.toJSON {
            enabledThemes = [ "wallpaper.theme.css" ];
            useQuickCss = true;
          }
        )
      } "$settings"
      run chmod u+w "$settings"
    fi
    run ${lib.getExe (pkgs.writeShellApplication {
      name = "sync-equicord-settings";
      runtimeInputs = [ pkgs.coreutils pkgs.jq ];
      text = builtins.readFile ../dotfiles/discord/sync-settings.sh;
    })} ${
      pkgs.writeText "equicord-plugins.json" (
        builtins.toJSON (import ../dotfiles/discord/plugins.nix)
      )
    } "$settings"
  '';
}
