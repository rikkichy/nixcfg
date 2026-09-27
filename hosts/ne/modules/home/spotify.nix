{ config, pkgs, lib, spotifyPalette, ... }:

let
  updateDirectory = "${config.home.homeDirectory}/Library/Application Support/Spotify/PersistentCache/Update";
  app = "${config.home.homeDirectory}/${config.targets.darwin.copyApps.directory}/Spotify.app";
  blockUpdates = pkgs.writeShellApplication {
    name = "spotify-block-updates";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ../../dotfiles/spotify/block-updates.sh;
  };
in
{
  # Finder launches the native binary. Block update staging without wrapping or
  # re-signing it; keep all existing profile and cache contents intact.
  home.activation.spotifyUpdates = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${lib.getExe blockUpdates} ${lib.escapeShellArg updateDirectory}
  '';

  # copyApps dereferences external symlinks, so link the deployed resource only
  # after copying. Spotify still loads its ordinary relative colors.css URL.
  home.activation.spotifyColors = lib.hm.dag.entryAfter [ "copyApps" "spotifyPalette" ] ''
    run ln -sfn ${lib.escapeShellArg spotifyPalette} ${lib.escapeShellArg "${app}/Contents/Resources/Apps/xpui/colors.css"}
  '';
}
