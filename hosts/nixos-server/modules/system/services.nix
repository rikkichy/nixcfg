{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    omp
    yubikey-manager
    age-plugin-yubikey
  ];

  services.pcscd.enable = true;
  services.udev.packages = [ pkgs.yubikey-personalization ];
  security.polkit = {
    enable = true;
    extraConfig = ''
      polkit.addRule(function (action, subject) {
        if (subject.user == "ri" && (
              action.id == "org.debian.pcsc-lite.access_pcsc" ||
              action.id == "org.debian.pcsc-lite.access_card")) {
          return polkit.Result.YES;
        }
      });
    '';
  };

  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };
  users.users.ri.extraGroups = [ "docker" "networkmanager" ];

  time.timeZone = "Europe/Moscow";
}
