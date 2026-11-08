{ lib, pkgs, ... }:

{
  imports = [
    ../../common/modules/spotify.nix
    ./modules/home/spotify.nix
    ./modules/home/discord.nix
    ../../common/modules/shell.nix
    ../../common/modules/ssh.nix
    ../../common/modules/neovim.nix
    ./modules/home/shell.nix
    ./modules/home/ghostty.nix
    ./modules/home/marta.nix
    ./modules/home/matugen.nix
    ./modules/home/keyboard.nix
  ];

  home.stateVersion = "26.05";
  home.packages = with pkgs; [
    ast-grep
    cabextract
    cmake
    fd
    ffmpeg
    filen-desktop
    git-filter-repo
    google-chrome
    idb-companion
    imagemagick
    innoextract
    libpq
    localsend
    obsidian
    openssh
    pipx
    pngquant
    poppler
    potrace
    prismlauncher
    qbittorrent
    railway
    # Keep the pinned rust-analyzer ahead of rustup's proxy.
    (lib.lowPrio rustup)
    _7zz
    tmux
    unar
    uv
    yt-dlp
  ];
}
