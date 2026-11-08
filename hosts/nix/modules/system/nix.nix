{ lib, ... }:

{
  nix.settings = {
    # Egress always leaves through the selected Mihomo node, so the Russian mirror gives no locality here.
    substituters = lib.mkForce [
      "https://cache.nixos.org/?priority=10"
      "https://mirror.yandex.ru/nixos/?priority=40"
    ];
    max-jobs = 2;
    cores = 8;
    # Mihomo TUN accepts connections locally, so stalled upstreams only fail here.
    stalled-download-timeout = 20;

    auto-optimise-store = false;

    fsync-store-paths = true;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
}
