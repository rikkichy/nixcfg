{
  description = "9950X3D / RTX 3090 / LUKS / Hyprland + Caelestia";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    caelestia-shell = {
      url = "github:caelestia-dots/shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    vhelper = {
      url = "github:rikkichy/vhelper";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    openwave = {
      url = "github:rikkichy/openwave";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    tg-ws-proxy = {
      url = "github:Flowseal/tg-ws-proxy";
      flake = false;
    };
  };

  outputs =
    { nixpkgs, home-manager, ... }@inputs:
    let
      # Where this repo lives on the installed system. It cannot be derived --
      # the flake is evaluated from wherever it happens to sit (/mnt/... during
      # install) while autoUpgrade, the Hyprland out-of-store symlink and the
      # ownership rule all need the final path. Defined once here rather than
      # repeated across modules.
      nixcfgPath = "/home/ri/nixcfg";
    in
    {
      nixosConfigurations.nix = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs nixcfgPath; };
        modules = [
          ./hardware-configuration.nix
          ./configuration.nix

          {
            nixpkgs.overlays = [
              (final: prev: {
                tg-ws-proxy = final.callPackage ./pkgs/tg-ws-proxy.nix {
                  src = inputs.tg-ws-proxy;
                };

                # Every streaming site here is DRM-gated: without the Widevine
                # CDM the Spotify web app loads, browses and searches normally
                # and then silently refuses to play a single track. Nothing in
                # the UI attributes this to a missing decryption module, so it
                # presents as "the audio is broken".
                #
                # This is not a source build. The wrapper's enableWideVine adds
                # one derivation that copies the already-compiled
                # chromium-unwrapped and drops WidevineCdm into libexec, so the
                # cost is a local copy plus a ~5 MiB fetch -- not the hours a
                # chromium rebuild would take. Overridden here rather than in
                # systemPackages so home.nix's web apps, which reference
                # pkgs.chromium directly, get the same binary.
                chromium = prev.chromium.override { enableWideVine = true; };
              })
            ];
          }

          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs nixcfgPath; };
            home-manager.users.ri = import ./home.nix;
          }
        ];
      };
    };
}
