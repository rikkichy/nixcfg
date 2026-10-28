{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    prismlauncher
    labymod-launcher
    wineWow64Packages.stable
    mangohud

    heroic
    protonplus
    osu-lazer-bin

    (writeTextDir "share/mime/packages/osu.xml" ''
      <?xml version="1.0" encoding="UTF-8"?>
      <mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
        <mime-type type="application/x-osu-beatmap">
          <comment>osu! beatmap</comment>
          <glob pattern="*.osu"/>
          <sub-class-of type="text/plain"/>
          <magic priority="60">
            <match type="string" offset="0" value="osu file format v"/>
          </magic>
          <icon name="osu"/>
        </mime-type>
        <mime-type type="application/x-osu-storyboard">
          <comment>osu! storyboard</comment>
          <glob pattern="*.osb"/>
          <sub-class-of type="text/plain"/>
          <icon name="osu"/>
        </mime-type>
        <mime-type type="application/x-osu-skin-archive">
          <comment>osu! skin archive</comment>
          <glob pattern="*.osk"/>
          <sub-class-of type="application/zip"/>
          <icon name="osu"/>
        </mime-type>
        <mime-type type="application/x-osu-beatmap-archive">
          <comment>osu! beatmap archive</comment>
          <glob pattern="*.osz"/>
          <glob pattern="*.osz2"/>
          <sub-class-of type="application/zip"/>
          <icon name="osu"/>
        </mime-type>
        <mime-type type="application/x-osu-replay">
          <comment>osu! replay</comment>
          <glob pattern="*.osr"/>
          <sub-class-of type="application/octet-stream"/>
          <icon name="osu"/>
        </mime-type>
      </mime-info>
    '')
  ];

  services.ananicy = {
    enable = true;
    package = pkgs.ananicy-cpp;
    rulesProvider = pkgs.ananicy-rules-cachyos;
  };

  # Native NT synchronization for Wine/Proton versions that support it.
  boot.kernelModules = [ "ntsync" ];

  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;

    remotePlay.openFirewall = false;
    localNetworkGameTransfers.openFirewall = false;

    extraCompatPackages = [ pkgs.proton-ge-bin ];
  };

  programs.gamemode = {
    enable = true;
    # Keep amd-pstate-epp dynamic rather than pinning every core's minimum clock.
    settings.general.desiredgov = "powersave";
  };
}
