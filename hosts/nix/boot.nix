{ config, pkgs, ... }:

let
  expressivePlymouth = pkgs.callPackage ./pkgs/ricing/plymouth {
    keymap = config.console.keyMap;
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
  environment.systemPackages = [ config.boot.loader.limine.secureBoot.sbctl ];
  boot.loader.limine.extraConfig = ''
    measured_boot: yes
  '';

  boot.plymouth = {
    enable = true;
    # Keep the stock derivation eligible for the NixOS binary cache.
    package = pkgs.plymouth;
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
      cp /etc/plymouth/themes/expressive/unlock-success.png /run/plymouth/cryptroot-unlocked.png.new
      mv /run/plymouth/cryptroot-unlocked.png.new /run/plymouth/cryptroot-unlocked.png
      ${config.boot.plymouth.package}/bin/plymouth update --status=cryptroot-unlocked &
    ''}";
  };
  boot.kernelPackages = pkgs.linuxPackages_latest;
  hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.stable;

  boot.kernelParams = [
    "quiet"
    "rd.udev.log_level=3"
    "rd.systemd.show_status=auto"
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
