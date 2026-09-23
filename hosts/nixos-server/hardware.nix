{ lib, modulesPath, ... }:

{
  # The installer replaces this label-based layout with detected hardware and UUIDs.
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];
  boot.initrd.availableKernelModules = [
    "xhci_pci" "thunderbolt" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod"
  ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.initrd.luks.devices.cryptroot.device = "/dev/disk/by-partlabel/cryptroot";
  fileSystems."/" = {
    device = "/dev/mapper/cryptroot";
    fsType = "xfs";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/BOOT";
    fsType = "vfat";
    options = [ "fmask=0022" "dmask=0022" ];
  };
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = true;
}
