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
  nix.channel.enable = false;
}
