{
  imports = [
    ../../common/modules/discord.nix
    ../../common/modules/spotify.nix
    ./modules/home/spotify.nix
    ./modules/home/discord.nix
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
