{ config, lib, pkgs, ... }:

let
  zedFileAssociations = pkgs.callPackage ../../pkgs/zed-file-associations.nix { };
  zedApp = "${config.home.homeDirectory}/${config.targets.darwin.copyApps.directory}/Zed.app";
in
{
  # Launch Services defaults, scoped to text/source files rather than all data.
  home.activation.zedFileAssociations = lib.hm.dag.entryAfter [ "copyApps" ] ''
    run ${zedFileAssociations}/bin/zed-file-associations ${lib.escapeShellArg zedApp} \
      json jsonc yaml yml toml nix \
      go rs py js jsx mjs cjs ts tsx kt kts lua qml \
      md markdown txt conf cfg ini \
      sh bash zsh fish
  '';
}
