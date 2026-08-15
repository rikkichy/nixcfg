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

    caelestia-cli = {
      url = "github:caelestia-dots/cli";
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
      system = "x86_64-linux";

      overlay = final: prev: {
        tg-ws-proxy = final.callPackage ./pkgs/tg-ws-proxy.nix {
          src = inputs.tg-ws-proxy;
        };

        nokochat = final.callPackage ./pkgs/nokochat.nix { };

        kotlin-lsp = final.callPackage ./pkgs/kotlin-lsp.nix { };

        google-sans-rounded =
          final.callPackage ./pkgs/google-sans-rounded.nix { };

        chromium = prev.chromium.override { enableWideVine = true; };

        # ananicy-cpp 1.2.0 leans on transitive <cstring>/<cstdint> that the
        # current libstdc++ no longer pulls in, so std::memset, std::strerror
        # and std::int32_t come up undeclared across several translation units.
        ananicy-cpp = prev.ananicy-cpp.overrideAttrs (old: {
          postPatch = (old.postPatch or "") + ''
            find src -name "*.cpp" -exec sed -i "1i #include <cstring>\n#include <cstdint>" {} +
          '';
        });
      };

      # Dev shells build their own pkgs: the Android SDK needs a license
      # acceptance that only belongs in a shell, not in the system closure.
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
