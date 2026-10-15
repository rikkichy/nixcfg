{ writeShellApplication, nix, nixos-install-tools, git, jq, util-linux, parted
, dosfstools, xfsprogs, cryptsetup, systemd, pam_u2f, coreutils, findutils, gnutar
}:
writeShellApplication {
  name = "nixcfg-install";
  runtimeInputs = [
    nix nixos-install-tools git jq util-linux parted dosfstools xfsprogs
    cryptsetup systemd pam_u2f coreutils findutils gnutar
  ];
  text = ''
    export NIXCFG_CRYPTSETUP_PLUGINS=${systemd}/lib/cryptsetup
  '' + builtins.readFile ./scripts/install.sh;
}
