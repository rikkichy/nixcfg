{ pkgs, ... }:

{
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

  networking.firewall.interfaces =
    let
      lan = {
        allowedTCPPorts = [ 27036 27037 27040 53317 ];
        allowedUDPPorts = [ 10400 10401 27036 53317 ];
        allowedUDPPortRanges = [ { from = 27031; to = 27035; } ];
      };
    in
    {
      enp11s0 = lan;
      wlp8s0 = lan;
    };

  networking.firewall.checkReversePath = "loose";

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };
}
