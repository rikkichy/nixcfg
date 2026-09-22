{ pkgs, nixcfgPath, ... }:

let
  scrubFailure = message: {
    User = "root";
    Group = "root";
    SupplementaryGroups = [ "" ];
    ExecStart = [
      ""
      "${pkgs.systemd}/bin/systemd-cat --identifier=xfs-scrub --priority=err ${pkgs.coreutils}/bin/echo ${message}"
    ];
  };
in
{
  systemd.tmpfiles.rules = [
    "Z ${nixcfgPath} - ri users - -"

    "d /var/lib/xfsprogs 0700 root root - -"

    "d /games 0755 ri users - -"
    "d /data  0755 ri users - -"
  ];

  fileSystems."/games" = {
    device = "/dev/disk/by-uuid/3a42fc06-c2d0-46fa-8a30-2ba6992ed35c";
    fsType = "xfs";
    options = [
      "defaults" "noatime" "nofail" "x-systemd.device-timeout=10s"
      "x-gvfs-show" "x-gvfs-name=Games"
    ];
  };

  fileSystems."/data" = {
    device = "/dev/disk/by-uuid/20685cc5-abf8-47e5-ada2-6519305369e7";
    fsType = "xfs";
    options = [
      "defaults" "noatime" "nofail" "x-systemd.device-timeout=10s"
      "x-gvfs-show" "x-gvfs-name=Data"
    ];
  };

  fileSystems."/".options = [ "x-gvfs-show" "x-gvfs-name=NixOS" ];

  systemd.timers.xfs_scrub_all.wantedBy = [ "timers.target" ];

  systemd.services = {
    xfs_scrub_all_fail.serviceConfig = scrubFailure
      "XFS scrub-all failed -- inspect journalctl -u xfs_scrub_all.service";

    "xfs_scrub_fail@" = {
      overrideStrategy = "asDropin";
      serviceConfig = scrubFailure
        "XFS metadata scrub failed for %f -- inspect journalctl -u xfs_scrub@%i.service";
    };

    "xfs_scrub_media_fail@" = {
      overrideStrategy = "asDropin";
      serviceConfig = scrubFailure
        "XFS media scrub failed for %f -- inspect journalctl -u xfs_scrub_media@%i.service";
    };
  };

  services.fstrim.enable = true;
}
