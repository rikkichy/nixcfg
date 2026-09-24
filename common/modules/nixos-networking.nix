{ ... }:

{
  networking.enableIPv6 = false;
  networking.networkmanager.enable = true;

  systemd.services.NetworkManager-wait-online.enable = false;

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };
}
