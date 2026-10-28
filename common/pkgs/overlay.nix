final: prev:
let
  version = "1.4.4";
  source = target: hash: final.fetchurl {
    url = "https://github.com/oven-sh/bun/releases/download/bun-v${version}/bun-${target}.zip";
    inherit hash;
  };
in
{
  bun = prev.bun.overrideAttrs (finalAttrs: old: {
    inherit version;
    src = finalAttrs.passthru.sources.${prev.stdenv.hostPlatform.system};
    passthru = old.passthru // {
      sources = {
        "aarch64-darwin" = source "darwin-aarch64" "sha256-wkDX8My5DCY6hJ/NsJt+5iYw2SE0jtaq/ahrnVd7xRA=";
        "aarch64-linux" = source "linux-aarch64" "sha256-uqa7NvUdblhWHgK76oJQOKnfRU9nPW13bou/hvjHhQ4=";
        "x86_64-linux" = source "linux-x64-baseline" "sha256-4ERutVmVdy65iUvrrppr42jZhai5Jx7hJEhvmUbu3XY=";
      };
    };
  });

  vpn = final.callPackage ./vpn.nix { };
}
