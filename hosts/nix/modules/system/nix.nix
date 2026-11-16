{ ... }:

{
  nix.settings = {
    # Yandex mirrors cache.nixos.org (official signatures); priority 39 queries it first.
    # Lantian publishes the prebuilt CachyOS kernels selected in boot.nix.
    substituters = [ "https://mirror.yandex.ru/nixos?priority=39" "https://cache.lantian.pub/lantian" ];
    trusted-public-keys = [ "lantian:WVGO7vsRMSEN+h7Lp7kv6SAmrkEXgUGbbXm7jMDjBuQ=" ];
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
