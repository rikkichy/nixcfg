{
  description = "9950X3D / RTX 3090 / LUKS / Hyprland + Caelestia";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # First-party nix support; follows-pattern matches the NixOS wiki.
    # quickshell + caelestia-cli follow through to your nixpkgs.
    caelestia-shell = {
      url = "github:caelestia-dots/shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Your own projects. Both repos now carry a flake.nix at their root
    # (renamed from <name>-flake.nix on 2026-08-05), so these inputs resolve.
    # Edit the derivations THERE, not here -- this repo keeps no copy.
    vhelper = {
      url = "github:rikkichy/vhelper";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    openwave = {
      url = "github:rikkichy/openwave";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, home-manager, ... }@inputs:
    {
      nixosConfigurations.nix = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          ./hardware-configuration.nix
          ./configuration.nix

          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs; };
            home-manager.users.ri = import ./home.nix;
          }
        ];
      };
    };
}
