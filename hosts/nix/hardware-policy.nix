{ pkgs, inputs, lib, ... }:

{
  services.udev.extraRules = ''
    ACTION!="remove", SUBSYSTEM=="platform", DRIVER=="amd_x3d_vcache", \
      ATTR{amd_x3d_mode}="cache"

    ACTION!="remove", SUBSYSTEM=="cpu", \
      ATTR{cpufreq/energy_performance_preference}="performance"
  '';

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    open = true;
    nvidiaSettings = true;
    powerManagement.enable = true;
  };

  services.fwupd.enable = true;

  hardware.opentabletdriver = {
    enable = true;
    daemon.enable = false;
  };

  hardware.wooting.enable = true;

  services.udev.packages = [
    pkgs.yubikey-personalization

    inputs.openwave.packages.${pkgs.stdenv.hostPlatform.system}.default

    (pkgs.writeTextDir "lib/udev/rules.d/70-lc87.rules" ''
      KERNEL=="hidraw*", ATTRS{idVendor}=="056a", TAG+="uaccess"
      SUBSYSTEM=="usb", ATTR{idVendor}=="0ac3", TAG+="uaccess"
    '')

    (pkgs.writeTextDir "lib/udev/rules.d/40-streamdeck.rules"
      (lib.concatMapStrings (pid: ''
        SUBSYSTEM=="usb", ATTRS{idVendor}=="0fd9", ATTRS{idProduct}=="${pid}", MODE="0660", TAG+="uaccess"
        KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0fd9", ATTRS{idProduct}=="${pid}", MODE="0660", TAG+="uaccess"
      '') [ "0060" "0063" "006c" "006d" "0080" "0084" "0086" "008f" "0090" "00b3" "009a" "00a5" "00b8" "00b9" "00ba" "00c6" ]))
  ];

  hardware.bluetooth.enable = true;
}
