{ config, pkgs, ... }:

let
  matugenConfig = (pkgs.formats.toml { }).generate "matugen-config.toml" {
    config.source_color_index = 0;
    templates.ghostty = {
      input_path = pkgs.writeText "ghostty-template" (
        builtins.replaceStrings
          (
            [
              "foreground="
              "background="
              "cursor="
              "selection="
            ]
            ++ builtins.genList (i: "color${toString i}=") 19
          )
          (
            [
              "foreground=#"
              "background=#"
              "cursor-color=#"
              "selection-background=#"
            ]
            ++ builtins.genList (i: "palette=${toString i}=#") 19
          )
          (builtins.readFile ../../../../common/dotfiles/matugen/templates/terminal-colors.conf)
      );
      output_path = "${config.xdg.configHome}/ghostty/themes/Matugen";
    };
    templates.btop = {
      input_path = ../../../../common/dotfiles/matugen/templates/btop.theme;
      output_path = "${config.xdg.configHome}/btop/themes/wallpaper.theme";
    };
    templates.marta = {
      input_path = ../../dotfiles/marta/Matugen.theme;
      output_path = "${config.home.homeDirectory}/Library/Application Support/org.yanex.marta/Themes/Matugen.theme";
    };
  };
  wallpaperTheme = pkgs.writeShellApplication {
    name = "wallpaper-theme";
    runtimeInputs = [ pkgs.matugen ];
    text = ''
      wallpaper=$(/usr/bin/osascript -e 'tell application "System Events" to tell first desktop to get its picture')
      if [[ ! -f "$wallpaper" ]]; then
        printf 'Wallpaper image not found: %s\n' "$wallpaper" >&2
        exit 1
      fi
      matugen image "$wallpaper" --type scheme-content --mode "''${1:-dark}" --config ${matugenConfig}
    '';
  };
in
{
  xdg.configFile."matugen/config.toml".source = matugenConfig;
  home.file.".local/bin/wallpaper-theme".source = "${wallpaperTheme}/bin/wallpaper-theme";
  home.packages = [ wallpaperTheme ];
}
