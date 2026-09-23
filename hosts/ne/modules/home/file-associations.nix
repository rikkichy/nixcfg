{ lib, pkgs, ... }:

let
  zedFileAssociations = pkgs.callPackage ../../pkgs/zed-file-associations.nix { };
in
{
  # Launch Services defaults, scoped to text/source files rather than all data.
  home.activation.zedFileAssociations = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${zedFileAssociations}/bin/zed-file-associations \
      json jsonc yaml yml toml nix \
      go rs py js jsx mjs cjs ts tsx kt kts lua qml \
      md markdown txt conf cfg ini \
      sh bash zsh fish
  '';
}
