{ config, lib, pkgs, ... }:

let
  home = config.home.homeDirectory;
  syncPairs = pkgs.writeText "filen-sync-pairs.json" (builtins.toJSON [
    {
      local = "${home}/Pictures/Wallpapers";
      remote = "/Sync/Pictures/Wallpapers";
      syncMode = "twoWay";
      excludeDotFiles = true;
    }
    {
      local = "${home}/Movies/Animated Wallpapers";
      remote = "/Sync/Videos/AnimatedWallpapers";
      syncMode = "twoWay";
      excludeDotFiles = true;
    }
  ]);
in

{
  home.packages = [ pkgs.filen-cli ];

  # The saved login's key lives in the login Keychain, unlocked by the GUI session.
  launchd.agents.filen-sync = {
    enable = true;
    config = {
      ProgramArguments = [
        (lib.getExe pkgs.filen-cli)
        "--skip-update"
        "--quiet"
        "sync"
        "${syncPairs}"
        "--continuous"
      ];
      # Without saved credentials the CLI blocks on an interactive login prompt,
      # so run only while the keep-me-logged-in file exists.
      KeepAlive.PathState."${home}/Library/Application Support/filen-cli/.filen-cli-keep-me-logged-in" = true;
      ThrottleInterval = 30;
      ProcessType = "Background";
      StandardOutPath = "${home}/Library/Logs/filen-sync.log";
      StandardErrorPath = "${home}/Library/Logs/filen-sync.log";
    };
  };
}
