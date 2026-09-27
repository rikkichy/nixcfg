{ pkgs, lib, ... }:

let
  discord = pkgs.discord.override { withEquicord = true; };
in
{
  home.packages = [ discord ];

  # Finder bypasses the CLI wrapper. Prepare its pinned modules at activation
  # without renaming or re-signing the native app executable.
  home.activation.discord = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${lib.getExe discord.disableBreakingUpdates}
    run ${discord.stageModules} "${discord}/Applications/Discord.app/Contents/Resources/modules"
  '';
}
