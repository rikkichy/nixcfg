{ writeShellApplication, openssl, openssh, curl, nix, hysteria, jq, coreutils }:

writeShellApplication {
  name = "nixcfg-hysteria-setup";
  runtimeInputs = [ openssl openssh curl nix hysteria jq coreutils ];
  text = ''
    export NIXCFG_HYSTERIA_SERVER_TEMPLATE=${./hosts/nixos-server/dotfiles/hysteria/server.example.yaml}
    export NIXCFG_HYSTERIA_CLIENT_TEMPLATE=${./common/dotfiles/hysteria/client.example.yaml}
  '' + builtins.readFile ./scripts/hysteria-setup.sh;
}
