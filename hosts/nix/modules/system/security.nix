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

  imports = [ ../../../../common/modules/nixos-yubikey.nix ];

  environment.memoryAllocator.provider = "graphene-hardened-light";

  services.pcscd.enable = true;
}
