{ config, inputs, lib, pkgs, utils, ... }:

let
  requiredMounts = inInitrd:
    map
      (entry: "${utils.escapeSystemdPath "${lib.optionalString inInitrd "/sysroot"}${entry.directory}"}.mount")
      (lib.filter
        (entry: entry.inInitrd == inInitrd && entry.how == "bindmount")
        config.preservation.preserveAt."/persist".directories);
in

{
  imports = [ inputs.preservation.nixosModules.preservation ];

  fileSystems = {
    "/" = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [ "mode=0755" "size=4G" ];
    };
    "/persist".neededForBoot = true;
    "/nix" = {
      device = "/persist/nix";
      fsType = "none";
      options = [ "bind" "x-gvfs-hide" "X-fstrim.notrim" ];
      neededForBoot = true;
    };
    "/home" = {
      device = "/persist/home";
      fsType = "none";
      options = [ "bind" "x-gvfs-hide" "X-fstrim.notrim" ];
      neededForBoot = true;
    };
  };

  preservation = {
    enable = true;
    preserveAt."/persist" = {
      commonMountOptions = [ "x-gvfs-hide" ];
      directories = [
        # Attic writes a regular file inside /etc/nix and rejects symlinks.
        { directory = "/etc/nix"; user = "root"; group = "root"; mode = "0755"; inInitrd = true; }
        { directory = "/var/lib/nixos"; user = "root"; group = "root"; mode = "0755"; inInitrd = true; }
        { directory = "/var/lib/userborn"; user = "root"; group = "root"; mode = "0755"; inInitrd = true; }
        { directory = "/var/lib/systemd"; user = "root"; group = "root"; mode = "0755"; inInitrd = true; }
        { directory = "/root"; user = "root"; group = "root"; mode = "0700"; }
        { directory = "/etc/nixos"; user = "ri"; group = "users"; mode = "0755"; }
        { directory = "/etc/mihomo"; user = "root"; group = "root"; mode = "0700"; }
        { directory = "/etc/NetworkManager/system-connections"; user = "root"; group = "root"; mode = "0700"; }
        { directory = "/var/lib/NetworkManager"; user = "-"; group = "-"; mode = "-"; }
        { directory = "/var/lib/bluetooth"; user = "root"; group = "root"; mode = "0700"; }
        { directory = "/var/lib/sbctl"; user = "root"; group = "root"; mode = "0700"; }
        # Systemd owns Mihomo's dynamic-user state and /var/lib/mihomo symlink.
        { directory = "/var/lib/private"; user = "root"; group = "root"; mode = "0700"; }
        { directory = "/var/lib/docker"; user = "-"; group = "-"; mode = "-"; }
        { directory = "/var/lib/waydroid"; user = "-"; group = "-"; mode = "-"; }
        { directory = "/var/lib/fwupd"; user = "-"; group = "-"; mode = "-"; }
        { directory = "/var/etc/fwupd"; user = "-"; group = "-"; mode = "-"; }
        { directory = "/var/lib/xfsprogs"; user = "root"; group = "root"; mode = "0700"; }
        { directory = "/var/log"; user = "-"; group = "-"; mode = "-"; }
      ];
      files = [
        {
          file = "/etc/machine-id";
          how = "symlink";
          inInitrd = true;
          configureParent = true;
        }
        {
          file = "/etc/u2f-mappings";
          how = "symlink";
        }
      ];
    };
  };

  # Initialize only a missing ID; systemd commits its transient ID to XFS.
  boot.initrd.systemd.tmpfiles.settings.preservation."/sysroot/persist/etc/machine-id".f = {
    user = "root";
    group = "root";
    mode = "0444";
    argument = "uninitialized";
  };
  systemd.services.systemd-machine-id-commit = {
    unitConfig.ConditionPathIsMountPoint = [ "" "/persist/etc/machine-id" ];
    serviceConfig.ExecStart = [
      ""
      "${pkgs.systemd}/bin/systemd-machine-id-setup --commit --root /persist"
    ];
  };

  users.mutableUsers = true;
  services.userborn = {
    enable = true;
    passwordFilesLocation = "/persist/etc";
    importLegacyState = true;
  };
  # Preservation creates the directory before the native legacy import runs.
  systemd.services.userborn-import-legacy.unitConfig.ConditionPathExists = lib.mkForce [
    "/var/lib/nixos/uid-map"
    "!/var/lib/userborn/previous-userborn.json"
  ];

  # Failed state mounts must block boot, not expose empty volatile substitutes.
  boot.initrd.systemd.targets.initrd-preservation = {
    requiredBy = [ "initrd.target" ];
    requires = requiredMounts true;
  };
  systemd.targets.preservation = {
    requiredBy = [ "sysinit.target" ];
    requires = requiredMounts false;
  };
}
