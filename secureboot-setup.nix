{ writeShellApplication, rustPlatform, sbctl, efitools, e2fsprogs, nh, nix
, openssl, pesign, tpm2-tools, coreutils
}:
let
  helper = rustPlatform.buildRustPackage {
    pname = "nixcfg-secureboot-setup";
    version = "1.0.0";
    src = ./scripts/secureboot-setup;
    cargoLock.lockFile = ./scripts/secureboot-setup/Cargo.lock;
  };
in
writeShellApplication {
  name = "nixcfg-secureboot-setup";
  runtimeInputs = [ sbctl efitools e2fsprogs nh nix openssl pesign tpm2-tools coreutils ];
  text = ''
    case "''${1:-}" in
      -h|--help) ;;
      *)
        if (( EUID != 0 )); then
          exec /run/wrappers/bin/sudo -- "$(readlink -f -- "$0")" "$@"
        fi
        ;;
    esac
    exec ${helper}/bin/nixcfg-secureboot-setup "$@"
  '';
}
