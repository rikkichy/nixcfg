{ writeShellApplication, openssl, openssh, curl, nix, attic-client, gh, jq
, coreutils, nh, systemd, util-linux
}:

writeShellApplication {
  name = "nixcfg-attic-setup";
  runtimeInputs = [
    openssl openssh curl nix attic-client gh jq coreutils nh systemd util-linux
  ];
  text = builtins.readFile ./scripts/attic-setup.sh;
}
