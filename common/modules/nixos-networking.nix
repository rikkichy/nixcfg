{ pkgs, ... }:

{
  environment.systemPackages = [ pkgs.vpn ];

  networking.enableIPv6 = false;
  networking.networkmanager.enable = true;

  services.mihomo = {
    enable = true;
    tunMode = true;
    webui = pkgs.metacubexd;
  };

  systemd.services.mihomo = {
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  systemd.services.NetworkManager-wait-online.enable = false;

  networking.networkmanager.unmanaged = [ "interface-name:mihomo" ];
  networking.firewall.trustedInterfaces = [ "mihomo" ];

  networking.firewall.checkReversePath = "loose";

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };
}
