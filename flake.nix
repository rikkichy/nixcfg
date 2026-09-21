{
  description = "9950X3D / RTX 3090 / LUKS / Hyprland + Quickshell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

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
      nixcfgPath = "/home/ri/nixcfg";
      system = "x86_64-linux";

      overlay = final: prev: {
        quickshell = prev.quickshell.overrideAttrs (old: {
          postPatch = (old.postPatch or "") + ''
            # QLocalSocket emits channelReadyRead after readyRead; do not destroy its sender.
            substituteInPlace src/wayland/hyprland/ipc/connection.cpp \
              --replace-fail 'delete requestSocket;' 'requestSocket->deleteLater();'
          '';
        });

        tg-ws-proxy = final.callPackage ./pkgs/tg-ws-proxy.nix {
          src = inputs.tg-ws-proxy;
        };

        nokochat = final.callPackage ./pkgs/nokochat.nix { };

        bibata-material-cursor = final.callPackage ./pkgs/bibata-material-cursor.nix {
          src = inputs.bibata-cursor;
        };

        kotlin-lsp = final.callPackage ./pkgs/kotlin-lsp.nix { };

        google-sans-rounded =
          final.callPackage ./pkgs/google-sans-rounded.nix { };

        midnight-discord =
          final.callPackage ./pkgs/midnight-discord.nix { };

        ananicy-cpp = prev.ananicy-cpp.overrideAttrs (old: {
          postPatch = (old.postPatch or "") + ''
            find src -name "*.cpp" -exec sed -i "1i #include <cstring>\n#include <cstdint>" {} +
          '';
        });
      };

      devPkgs = import nixpkgs {
        inherit system;
        overlays = [ overlay ];
        config = {
          allowUnfree = true;
          android_sdk.accept_license = true;
        };
      };

      nokochatShell = import ./dev/nokochat/shell.nix { pkgs = devPkgs; };
    in
    {
      devShells.${system} = {
        nokochat = nokochatShell;
        default = nokochatShell;
      };

      nixosConfigurations.nix = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs nixcfgPath; };
        modules = [
          ./hardware-configuration.nix
          ./configuration.nix
          inputs.sops-nix.nixosModules.sops
          ./.secrets/sops.nix

          { nixpkgs.overlays = [ overlay ]; }

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
