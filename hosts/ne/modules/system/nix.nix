{
  pkgs,
  ...
}:

{
  nix.package = pkgs.lix;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.settings.substituters = [
    "https://mirror.yandex.ru/nixos/?priority=10"
    "https://cache.nixos.org/"
  ];
  nix.channel.enable = false;
}
