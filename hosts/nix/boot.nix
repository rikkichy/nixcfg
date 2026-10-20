{ config, lib, pkgs, ... }:

# Local signing policy disabled so the stock kernel can use binary caches.
# let
#   signedKernel = import ./pkgs/lockdown-kernel.nix {
#     inherit (pkgs) lib applyPatches linuxPackages_latest;
#   };
# in

let
  expressivePlymouth = pkgs.callPackage ./pkgs/ricing/plymouth { };
in
{
  imports = [ ../../common/modules/nixos-limine.nix ];

  boot.loader.timeout = 0;
  boot.loader.limine.secureBoot = {
    enable = true;
    autoGenerateKeys = false;
    autoEnrollKeys.enable = false;
  };
  boot.loader.limine.extraInstallCommands = ''
    ${pkgs.python3}/bin/python3 ${./pkgs/verify-limine-secureboot.py} \
      ${lib.escapeShellArg "${config.boot.loader.efi.efiSysMountPoint}/limine/limine.conf"} \
      ${lib.escapeShellArg "${config.boot.loader.efi.efiSysMountPoint}/efi/${if config.boot.loader.limine.efiInstallAsRemovable then "boot" else "limine"}/BOOTX64.EFI"} \
      /var/lib/sbctl/keys/db/db.pem ${pkgs.sbsigntool}/bin/sbverify
  '';
  environment.systemPackages = [ config.boot.loader.limine.secureBoot.sbctl ];
  boot.loader.limine.extraConfig = ''
    measured_boot: yes
  '';

  boot.plymouth = {
    enable = true;
    # Keep the original loop speed while allowing 240 Hz animation updates.
    package = (pkgs.plymouth.override {
      systemd = config.boot.initrd.systemd.package;
    }).overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        ./pkgs/ricing/plymouth/unlock-success.patch
        ./pkgs/ricing/plymouth/material-entry.patch
      ];
      postPatch = (old.postPatch or "") + ''
        substituteInPlace src/libply-splash-graphics/ply-throbber.c \
          --replace-fail '#define FRAMES_PER_SECOND 30' '#define FRAMES_PER_SECOND 240' \
          --replace-fail '0.005);' '0.001);'
      '';
      env = old.env // {
        NIX_CFLAGS_COMPILE = (old.env.NIX_CFLAGS_COMPILE or "")
          + " -DTHROBBER_DURATION=4.55";
      };
    });
    theme = "expressive";
    themePackages = [ expressivePlymouth ];
    font = expressivePlymouth.font;
  };
  fonts.packages = [ expressivePlymouth ];
  boot.consoleLogLevel = 3;
  boot.initrd.verbose = false;
  boot.initrd.kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_drm" ];

  boot.initrd.luks.devices."cryptroot" = {
    allowDiscards = true;
  };
  boot.initrd.systemd.services."systemd-cryptsetup@cryptroot" = {
    overrideStrategy = "asDropin";
    # Cosmetic notification: never fail or hold up unlock for an unresponsive splash.
    serviceConfig.ExecStartPost = "-${pkgs.writeShellScript "cryptroot-unlocked" ''
      set -e
      mkdir -p /run/plymouth
      : > /run/plymouth/cryptroot-unlocked
      ${config.boot.plymouth.package}/bin/plymouth update --status=cryptroot-unlocked &
    ''}";
  };
  boot.kernelPackages = pkgs.linuxPackages_latest;
  hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.stable;

  # nix.settings.experimental-features = [ "ca-derivations" ];
  # boot.kernelPackages = (pkgs.linuxPackagesFor signedKernel).extend (self: _: {
  #   nct6687d = self.kernel;
  #   v4l2loopback = self.kernel;
  # });
  # hardware.nvidia.package = pkgs.linuxPackages_latest.nvidiaPackages.stable.overrideAttrs (old: {
  #   passthru = old.passthru // { open = config.boot.kernelPackages.kernel; };
  # });
  #
  # assertions = [
  #   {
  #     assertion = config.hardware.nvidia.open;
  #     message = "The lockdown kernel includes NVIDIA's open modules; keep hardware.nvidia.open enabled.";
  #   }
  #   {
  #     assertion = lib.all
  #       (package: toString package == toString config.boot.kernelPackages.kernel)
  #       config.boot.extraModulePackages;
  #     message = "Lockdown requires external modules to be included in the joint kernel signing build.";
  #   }
  # ];

  boot.kernelParams = [
    "quiet"
    "rd.udev.log_level=3"
    "rd.systemd.show_status=auto"
    # "lockdown=integrity"
    "amd_iommu=force_isolation"
    "iommu.passthrough=0"
    "amd_pstate=active"
    "split_lock_detect=off"
    "vsyscall=none"
    "slab_nomerge"
    "page_alloc.shuffle=1"
  ];

  systemd.settings.Manager = {
    RuntimeWatchdogSec = "30s";
    RebootWatchdogSec = "3min";
  };

  services.journald.settings.Journal.SyncIntervalSec = "30s";

  boot.extraModulePackages = [
    config.boot.kernelPackages.nct6687d
  ];
  boot.kernelModules = [ "nct6687" ];
  boot.blacklistedKernelModules = [ "nct6683" ];
  boot.extraModprobeConfig = ''
    options nct6687 force=true msi_fan_brute_force=true
  '';

  boot.kernel.sysctl = {
    "vm.max_map_count" = 2147483642;
    "vm.swappiness" = 180;
    "vm.page-cluster" = 0;

    "kernel.dmesg_restrict" = 1;

    "kernel.unprivileged_bpf_disabled" = 2;
    "net.core.bpf_jit_harden" = 1;

    "kernel.yama.ptrace_scope" = 1;
  };

  zramSwap.enable = true;
}
