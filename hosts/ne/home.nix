{
  config,
  pkgs,
  lib,
  ...
}:

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
          (builtins.readFile ../../dotfiles/matugen/templates/terminal-colors.conf)
      );
      output_path = "${config.xdg.configHome}/ghostty/themes/Matugen";
    };
    templates.btop = {
      input_path = ../../dotfiles/matugen/templates/btop.theme;
      output_path = "${config.xdg.configHome}/btop/themes/wallpaper.theme";
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
  zedFileAssociations =
    pkgs.runCommandCC "zed-file-associations"
      {
        nativeBuildInputs = [ pkgs.swift ];
      }
      ''
        mkdir -p "$out/bin"
        swiftc ${pkgs.writeText "zed-file-associations.swift" ''
          import AppKit
          import UniformTypeIdentifiers

          Task { @MainActor in
              guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "dev.zed.Zed") else {
                  fputs("Zed must be installed before setting file associations.\n", stderr)
                  exit(1)
              }
              do {
                  for ext in CommandLine.arguments.dropFirst() {
                      guard let type = UTType(filenameExtension: ext) else {
                          fputs("No content type for .\(ext)\n", stderr)
                          exit(1)
                      }
                      if NSWorkspace.shared.urlForApplication(toOpen: type) == app { continue }
                      try await NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type)
                      print(".\(ext) → Zed")
                  }
                  exit(0)
              } catch {
                  fputs("Could not set Zed file associations: \(error)\n", stderr)
                  exit(1)
              }
          }
          RunLoop.main.run()
        ''} -o "$out/bin/zed-file-associations"
      '';
in
{
  imports = [
    ../../modules/home/common/shell.nix
    ../../modules/home/common/zed.nix
  ];

  home.stateVersion = "26.05";

  # Launch Services defaults, scoped to text/source files rather than all data.
  home.activation.zedFileAssociations = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${zedFileAssociations}/bin/zed-file-associations \
      json jsonc yaml yml toml nix \
      go rs py js jsx mjs cjs ts tsx kt kts lua qml \
      md markdown txt conf cfg ini \
      sh bash zsh fish
  '';

  programs.fish.shellInit = ''
    /opt/homebrew/bin/brew shellenv fish | source
    fish_add_path --global --path /opt/homebrew/opt/rustup/bin
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
      font-family = "DepartureMono Nerd Font";
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
      custom-shader-animation = false;
    };
  };

  xdg.configFile = {
    "matugen/config.toml".source = matugenConfig;
    "ghostty/shaders/cursor_sweep.glsl".source = ../../dotfiles/ghostty/shaders/cursor_sweep.glsl;
    "ghostty/shaders/in-game-crt-cursor.glsl".source =
      ../../dotfiles/ghostty/shaders/in-game-crt-cursor.glsl;
  };
  home.file.".betterglobekey.yaml".source = ../../dotfiles/betterglobekey.yaml;
  home.file.".local/bin/wallpaper-theme".source = "${wallpaperTheme}/bin/wallpaper-theme";

  home.packages = with pkgs; [
    matugen
    wallpaperTheme
  ];
}
