{ pkgs, ... }:

{
  programs.git.enable = true;

  environment.systemPackages = with pkgs; [
    sops
    age
    btop git gh wget
    trash-cli
    starship zoxide eza fzf bat ripgrep lazygit jq fastfetch micro
    file
    unzip
  ];
}
