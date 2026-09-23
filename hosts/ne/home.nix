{ config, pkgs, ... }:

let
  matugenConfig = (pkgs.formats.toml { }).generate "matugen-config.toml" {
    config.source_color_index = 0;
    templates.ghostty = {
      input_path = pkgs.writeText "ghostty-template" (
        builtins.replaceStrings
          ([ "foreground=" "background=" "cursor=" "selection=" ]
            ++ builtins.genList (i: "color${toString i}=") 19)
          ([ "foreground=#" "background=#" "cursor-color=#" "selection-background=#" ]
            ++ builtins.genList (i: "palette=${toString i}=#") 19)
          (builtins.readFile ../../dotfiles/matugen/templates/terminal-colors.conf)
      );
      output_path = "${config.xdg.configHome}/ghostty/themes/Matugen";
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
  imports = [ ../../modules/home/common/shell.nix ];

  home.stateVersion = "26.05";

  programs.fish.shellInit = ''
    /opt/homebrew/bin/brew shellenv fish | source
    fish_add_path --global --path /opt/homebrew/opt/rustup/bin /opt/homebrew/opt/openjdk@21/bin
    set -gx JAVA_HOME /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
    set -gx BUN_INSTALL "$HOME/.bun"
    fish_add_path --global --path "$BUN_INSTALL/bin"
  '';

  programs.ghostty = {
    enable = true;
    package = null; # Keep the existing macOS application.
    settings = {
      theme = "Matugen";
      command = "/run/current-system/sw/bin/fish";
      background-opacity = 0.6;
      background-blur-radius = 20;
      font-size = 18;
      cursor-style = "block";
      cursor-style-blink = false;
      font-thicken = true;
      adjust-cell-height = 2;
      window-padding-balance = true;
      resize-overlay = "never";
      scrollback-limit = 10000;
      custom-shader = [
        "${config.xdg.configHome}/ghostty/shaders/cursor_sweep.glsl"
        "${config.xdg.configHome}/ghostty/shaders/in-game-crt-cursor.glsl"
      ];
      custom-shader-animation = "always";
    };
  };

  xdg.configFile."matugen/config.toml".source = matugenConfig;
  home.file.".local/bin/wallpaper-theme".source = "${wallpaperTheme}/bin/wallpaper-theme";

  home.packages = with pkgs; [
    starship
    zoxide
    eza
    lazygit
    git
    fastfetch
    matugen
    wallpaperTheme
  ];
}
