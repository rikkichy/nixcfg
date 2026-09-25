{
  imports = [
    ../../common/modules/shell.nix
    ../../common/modules/ssh.nix
    ../../common/modules/zed.nix
    ./modules/home/shell.nix
    ./modules/home/ghostty.nix
    ./modules/home/marta.nix
    ./modules/home/matugen.nix
    ./modules/home/file-associations.nix
    ./modules/home/keyboard.nix
  ];

  home.stateVersion = "26.05";
}
