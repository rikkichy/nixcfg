{
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
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
