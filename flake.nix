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

    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
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
    vts-opendeck = {
      url = "github:rikkichy/vts-opendeck";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    omp = {
      url = "github:rikkichy/oh-my-pi-flake";
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
    { self, nixpkgs, home-manager, ... }@inputs:
    let
      nixcfgPath = "/etc/nixos";
      system = "x86_64-linux";

      commonOverlay = import ./common/pkgs/overlay.nix { inherit inputs; };
      overlay = import ./hosts/nix/pkgs/overlay.nix { inherit inputs; };
      # Reuse the host's final package set, including both overlays and policy.
      desktopPkgs = self.nixosConfigurations.nix.pkgs;
      desktopHome = self.nixosConfigurations.nix.config.home-manager.users.ri;
      cacheTargets = {
        inherit (desktopPkgs)
          filen-desktop fuzzel quickshell hyprland tg-ws-proxy photocraft filmcraft
          bibata-material-cursor google-sans-rounded vpn omp;
        spicetify-cli = desktopHome.programs.spicetify.spicetifyPackage;
        vhelper = inputs.vhelper.packages.${system}.default;
        openwave = inputs.openwave.packages.${system}.default;
      };
    in
    {
      # Publicly redistributable roots only; never publish the whole host closure.
      cacheTargets.${system} = cacheTargets;
      packages.${system} = cacheTargets // {
        attic-client = nixpkgs.legacyPackages.${system}.attic-client;
        install = nixpkgs.legacyPackages.${system}.callPackage ./install.nix { };
        hysteria-setup = nixpkgs.legacyPackages.${system}.callPackage ./hysteria-setup.nix { };
        attic-setup = nixpkgs.legacyPackages.${system}.callPackage ./attic-setup.nix { };
        vts-opendeck = inputs.vts-opendeck.packages.${system}.default;
      };
      apps.${system}.install = {
        type = "app";
        program = "${nixpkgs.legacyPackages.${system}.callPackage ./install.nix { }}/bin/nixcfg-install";
      };
      packages.aarch64-darwin.hysteria-setup =
        nixpkgs.legacyPackages.aarch64-darwin.callPackage ./hysteria-setup.nix { };

      nixosConfigurations.nixos-server = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit nixcfgPath; };
        modules = [
          ./hosts/nixos-server
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
            home-manager.extraSpecialArgs = { inherit inputs nixcfgPath; };
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
          { nix.extraOptions = "!include /etc/nix/attic.conf"; }

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
