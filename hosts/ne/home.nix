{ pkgs, ... }:

{
  imports = [ ../../modules/home/common/shell.nix ];

  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    starship
    zoxide
    eza
    lazygit
    git
    fastfetch
  ];
}
