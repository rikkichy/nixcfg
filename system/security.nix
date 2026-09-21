{
  security.polkit.extraConfig = ''
    polkit.addRule(function (action, subject) {
      if (subject.user == "ri" && (
            action.id == "org.freedesktop.login1.power-off" ||
            action.id == "org.freedesktop.login1.power-off-multiple-sessions" ||
            action.id == "org.freedesktop.login1.reboot" ||
            action.id == "org.freedesktop.login1.reboot-multiple-sessions" ||
            action.id == "org.freedesktop.login1.suspend" ||
            action.id == "org.freedesktop.login1.suspend-multiple-sessions" ||
            action.id == "org.debian.pcsc-lite.access_pcsc" ||
            action.id == "org.debian.pcsc-lite.access_card")) {
        return polkit.Result.YES;
      }
    });
  '';

  security.protectKernelImage = true;

  security.sudo-rs = {
    enable = true;
    wheelNeedsPassword = true;
  };
  security.pam.u2f.settings = {
    authfile = "/etc/u2f-mappings";
    origin = "pam://nix";
    appid = "pam://nix";
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

  environment.memoryAllocator.provider = "graphene-hardened-light";

  services.pcscd.enable = true;
}
