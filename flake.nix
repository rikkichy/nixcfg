{
  description = "NixOS desktop, server and macOS hosts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
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

    helium = {
      url = "github:oxcl/nix-flake-helium-browser";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    omp = {
      url = "github:can1357/oh-my-pi";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    unsloth = {
      url = "github:Trantorian1/unsloth-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    tg-ws-proxy = {
      url = "github:Flowseal/tg-ws-proxy";
      flake = false;
    };

    bibata-cursor = {
      url = "github:rtgiskard/bibata_cursor";
      flake = false;
    };
  };

  outputs =
    { nixpkgs, home-manager, ... }@inputs:
    let
      nixcfgPath = "/etc/nixos";
      system = "x86_64-linux";

      commonOverlay = import ./common/pkgs/overlay.nix { inherit inputs; };
      overlay = import ./hosts/nix/pkgs/overlay.nix { inherit inputs; };

      devPkgs = import nixpkgs {
        inherit system;
        overlays = [ commonOverlay overlay ];
        config = {
          allowUnfree = true;
        };
      };
    in
    {
      packages.${system} = {
        rhythia = devPkgs.rhythia;
        install = nixpkgs.legacyPackages.${system}.callPackage ./install.nix { };
      };
      apps.${system}.install = {
        type = "app";
        program = "${nixpkgs.legacyPackages.${system}.callPackage ./install.nix { }}/bin/nixcfg-install";
      };

      nixosConfigurations.nixos-server = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit nixcfgPath; };
        modules = [
          ./hosts/nixos-server
          inputs.sops-nix.nixosModules.sops
          ./.secrets/nixos-server/sops.nix
          { nixpkgs.overlays = [ commonOverlay ]; }
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit nixcfgPath; };
            home-manager.backupFileExtension = "before-home-manager";
            home-manager.users.ri = import ./hosts/nixos-server/home.nix;
          }
        ];
      };

      darwinConfigurations.ne = inputs.nix-darwin.lib.darwinSystem {
        specialArgs = { inherit nixcfgPath; };
        modules = [
          ./hosts/ne
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit nixcfgPath; };
            home-manager.backupFileExtension = "before-nix-darwin";
            home-manager.users.rii = import ./hosts/ne/home.nix;
          }
        ];
      };

      nixosConfigurations.nix = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs nixcfgPath; };
        modules = [
          ./hosts/nix
          inputs.sops-nix.nixosModules.sops
          ./.secrets/nix/sops.nix

          { nixpkgs.overlays = [ commonOverlay overlay ]; }

          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs nixcfgPath; };
            home-manager.users.ri = import ./hosts/nix/home.nix;
          }
        ];
      };
    };
}
