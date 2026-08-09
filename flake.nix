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

                nokochat = final.callPackage ./pkgs/nokochat.nix { };

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
