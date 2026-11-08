{ pkgs, lib, ... }:

let
  discord = pkgs.discord.overrideAttrs (old: {
    # Discord's legacy updater honors both skip settings and the staged modules.
    postInstall = (old.postInstall or "") + ''
      substituteInPlace "$out/Applications/Discord.app/Contents/Resources/build_info.json" \
        --replace-fail '"version":' '"disableUpdater": true, "version":'
    '';
  });
  disableUpdates = discord.disableBreakingUpdates.overrideAttrs {
    skipModuleUpdate = "true";
  };
in
{
  home.packages = [ discord ];

  # Finder bypasses the CLI wrapper. Prepare its pinned modules at activation
  # without renaming or re-signing the native app executable.
  home.activation.discord = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${lib.getExe disableUpdates}
    run ${discord.stageModules} "${discord}/share/discord/modules"
  '';
}
