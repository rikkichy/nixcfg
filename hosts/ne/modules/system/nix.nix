{
  pkgs,
  ...
}:

{
  nix.package = pkgs.lix.overrideAttrs (old: {
    # Darwin's Mach-O linker rejects the upstream ELF-only stack flag.
    env = old.env // {
      NIX_LDFLAGS = "";
    };
  });
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
