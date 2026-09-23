{
  imports = [
    ../../common/modules/shell.nix
    ../../common/modules/zed.nix
    ./modules/home.nix
  ];

  home.stateVersion = "26.05";
}
