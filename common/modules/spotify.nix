{ config, pkgs, lib, inputs, ... }:

let
  cfg = config.programs.spicetify;
  moduleScripts = ''<script defer="defer" src="/xpui-modules.js"></script><script defer="defer" src="/xpui-snapshot.js"></script>'';
  bootstrap = "<script>Spicetify.Config=${builtins.toJSON {
    version = cfg.spicetifyPackage.version;
    current_theme = cfg.theme.name;
    color_scheme = cfg.colorScheme;
    extensions = [];
    custom_apps = [];
    check_spicetify_update = false;
  }};</script>";
  spotifyPalette = "${config.xdg.configHome}/spicetify/colors.css";
  resources = if pkgs.stdenv.hostPlatform.isDarwin then
    "Applications/Spotify.app/Contents/Resources"
  else
    "share/spotify";
in
{
  imports = [ inputs.spicetify-nix.homeManagerModules.spicetify ];

  _module.args.spotifyPalette = spotifyPalette;
  _module.args.spotifyPaletteTemplate = {
    input_path = ../dotfiles/matugen/templates/spotify-palette.css;
    output_path = spotifyPalette;
  };

  programs.spicetify = {
    enable = true;
    theme = {
      name = "Wallpaper";
      src = pkgs.writeTextDir "color.ini" "[Wallpaper]\n";
      replaceColors = true;
      injectCss = false;
      injectThemeJs = false;
      homeConfig = false;
      overwriteAssets = false;
      # Load rewritten JS with the matching CSS, without enabling any add-ons.
      patches = {
        "index.html_find_1" = ''<script defer="defer" src="/xpui-snapshot\.js"></script>'';
        "index.html_repl_1" = moduleScripts;
        "index.html_find_2" = "<!-- spicetify helpers -->";
        "index.html_repl_2" = "<!-- spicetify helpers -->${bootstrap}";
      };
    };
    colorScheme = "Wallpaper";
    # Keep native RTL layout; the upstream module otherwise strips those rules.
    updateXpui = xpui: lib.recursiveUpdate xpui { Preprocesses.remove_rtl_rule = false; };
    spotifyPackage = pkgs.spotify.overrideAttrs (old: {
      postFixup = (old.postFixup or "") + ''
        # Spicetify's native patch command does not fail on unmatched patterns.
        index="$out/${resources}/Apps/xpui/index.html"
        grep -Fq ${lib.escapeShellArg moduleScripts} "$index"
        grep -Fq ${lib.escapeShellArg bootstrap} "$index"
        test "$(grep -oF 'src="/xpui-modules.js"' "$index" | wc -l)" -eq 1
        test "$(grep -oF 'Spicetify.Config=' "$index" | wc -l)" -eq 1
        mkdir -p "$out/share/spicetify"
        cp "$out/${resources}/Apps/xpui/colors.css" "$out/share/spicetify/colors.css"
      '' + lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
        rm "$out/${resources}/Apps/xpui/colors.css"
        ln -s ${lib.escapeShellArg spotifyPalette} "$out/${resources}/Apps/xpui/colors.css"
      '';
    });
  };

  # Until Matugen runs, use Spicetify's native Spotify colors. Never overwrite
  # a generated palette. Darwin links it after Home Manager copies the app.
  home.activation.spotifyPalette = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    palette=${lib.escapeShellArg spotifyPalette}
    if [ ! -e "$palette" ]; then
      run mkdir -p "$(dirname "$palette")"
      run cp ${config.programs.spicetify.spicedSpotify}/share/spicetify/colors.css "$palette"
      run chmod u+w "$palette"
    fi
  '';
}
