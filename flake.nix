{
  description = "NixOS desktop, server and macOS hosts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Keep Darwin nh on an officially cached build of the same release.
    nixpkgs-nh.url = "github:NixOS/nixpkgs/b4fd65b198c599cbe814fcb9f42d25d021595ec9";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    preservation.url = "github:nix-community/preservation/00be7f7dd1a11ae0605386f2272288de7cf33abe";

    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    vts-opendeck = {
      url = "github:rikkichy/vts-opendeck";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    tg-ws-proxy = {
      url = "github:Flowseal/tg-ws-proxy";
      flake = false;
    };

    # Pinned Nix packaging of Shiro836/waydroid-nvidia v0.2.0 (hash-checked release assets).
    waydroid-nvidia = {
      url = "github:yigexuanmu/waydroid-nvidia-nix/28a092527b56f3ddba4592083bc7154d84599d79";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, home-manager, ... }@inputs:
    let
      nixcfgPath = "/etc/nixos";
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      homeManager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        extraSpecialArgs = { inherit inputs nixcfgPath; };
      };

      commonOverlay = import ./common/pkgs/overlay.nix;
      overlay = import ./hosts/nix/pkgs/overlay.nix { inherit inputs; };
      # Reuse the host's final package set, including both overlays and policy.
      desktopPkgs = self.nixosConfigurations.nix.pkgs;
      cacheTargets = {
        inherit (desktopPkgs) tg-ws-proxy google-sans-rounded vpn;
      };
    in
    {
      # Publicly redistributable roots only; never publish the whole host closure.
      cacheTargets.${system} = cacheTargets;
      packages.${system} = cacheTargets // {
        install = pkgs.callPackage ./install.nix { };
        hysteria-setup = pkgs.callPackage ./hysteria-setup.nix { };
        attic-setup = pkgs.callPackage ./attic-setup.nix { };
        secureboot-setup = pkgs.callPackage ./secureboot-setup.nix { };
        vts-opendeck = inputs.vts-opendeck.packages.${system}.default;
      };
      packages.aarch64-darwin.hysteria-setup =
        nixpkgs.legacyPackages.aarch64-darwin.callPackage ./hysteria-setup.nix { };

      nixosConfigurations.nixos-server = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs nixcfgPath; };
        modules = [
          ./hosts/nixos-server
          { nixpkgs.overlays = [ commonOverlay ]; }
          home-manager.nixosModules.home-manager
          {
            home-manager = homeManager // {
              backupFileExtension = "before-home-manager";
              users.ri = import ./hosts/nixos-server/home.nix;
            };
          }
        ];
      };

      darwinConfigurations.ne = inputs.nix-darwin.lib.darwinSystem {
        specialArgs = { inherit inputs nixcfgPath; };
        modules = [
          { nixpkgs.overlays = [ commonOverlay ]; }
          ./hosts/ne
          home-manager.darwinModules.home-manager
          {
            home-manager = homeManager // {
              backupFileExtension = "before-nix-darwin";
              users.rii = import ./hosts/ne/home.nix;
            };
          }
        ];
      };

      nixosConfigurations.nix = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs nixcfgPath; };
        modules = [
          ./hosts/nix
          ./common/modules/nixos-mihomo-secrets.nix

          { nixpkgs.overlays = [ commonOverlay overlay ]; }

          home-manager.nixosModules.home-manager
          { home-manager = homeManager // { users.ri = import ./hosts/nix/home.nix; }; }
        ];
      };
    };
}
