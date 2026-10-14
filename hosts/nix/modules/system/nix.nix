{
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    substituters = [
      "https://mirror.yandex.ru/nixos/?priority=10"
      "https://cache.nixos.org/"
    ];
    max-jobs = 2;
    cores = 8;

    auto-optimise-store = false;

    fsync-store-paths = true;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
}
