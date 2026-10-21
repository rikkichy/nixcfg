{ writeShellApplication, python3, sbctl, efitools, e2fsprogs, nh, nix
, openssl, pesign, tpm2-tools, coreutils
}:
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
    exec ${python3.withPackages (ps: [ ps.pyyaml ])}/bin/python3 ${./scripts/secureboot-setup.py} "$@"
  '';
}
