{ config, lib, pkgs, ... }:

let
  signedKernel = import ./pkgs/lockdown-kernel.nix {
    inherit (pkgs) lib applyPatches linuxPackages_latest;
  };
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

  boot.initrd.luks.devices."cryptroot" = {
    allowDiscards = true;
  };
  nix.settings.experimental-features = [ "ca-derivations" ];
  boot.kernelPackages = (pkgs.linuxPackagesFor signedKernel).extend (self: _: {
    nct6687d = self.kernel;
    v4l2loopback = self.kernel;
  });
  hardware.nvidia.package = pkgs.linuxPackages_latest.nvidiaPackages.stable.overrideAttrs (old: {
    passthru = old.passthru // { open = config.boot.kernelPackages.kernel; };
  });
  system.build.lockdownTest = pkgs.callPackage ./pkgs/lockdown-test.nix {
    kernel = config.boot.kernelPackages.kernel;
  };
  system.build.secureBootTest = pkgs.callPackage ./pkgs/limine-secureboot-test.nix {
    limine = config.boot.loader.limine.package;
  };

  assertions = [
    {
      assertion = config.hardware.nvidia.open;
      message = "The lockdown kernel includes NVIDIA's open modules; keep hardware.nvidia.open enabled.";
    }
    {
      assertion = lib.all
        (package: toString package == toString config.boot.kernelPackages.kernel)
        config.boot.extraModulePackages;
      message = "Lockdown requires external modules to be included in the joint kernel signing build.";
    }
  ];

  boot.kernelParams = [
    "lockdown=integrity"
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
