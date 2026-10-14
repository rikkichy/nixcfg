{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
    "ca-derivations"
  ];
  nix.settings.substituters = [
    "https://mirror.yandex.ru/nixos/?priority=10"
    "https://cache.nixos.org/"
  ];
  nix.channel.enable = false;
}
