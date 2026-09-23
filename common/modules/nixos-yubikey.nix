{ config, ... }:

{
  boot.initrd.systemd.enable = true;
  boot.initrd.systemd.fido2.enable = true;
  boot.initrd.luks.devices.cryptroot.crypttabExtraOpts = [
    "fido2-device=auto"
    "token-timeout=10s"
  ];

  security.sudo-rs = {
    enable = true;
    wheelNeedsPassword = true;
  };
  security.pam.u2f.settings = {
    authfile = "/etc/u2f-mappings";
    origin = "pam://${config.networking.hostName}";
    appid = "pam://${config.networking.hostName}";
    userpresence = 1;
    pinverification = 0;
    userverification = 0;
    cue = true;
  };
  security.pam.services.sudo.u2f = {
    enable = true;
    control = "sufficient";
  };
  security.pam.services.sudo-i.u2f = {
    enable = true;
    control = "sufficient";
  };
}
