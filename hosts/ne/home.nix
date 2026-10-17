{ lib, pkgs, ... }:

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
  home.packages = [ (pkgs.callPackage ./pkgs/lan-mouse.nix { }) ] ++ (with pkgs; [
    ast-grep
    cabextract
    cmake
    fd
    ffmpeg
    git-filter-repo
    idb-companion
    imagemagick
    innoextract
    libpq
    openssh
    pipx
    pngquant
    poppler
    potrace
    prismlauncher
    railway
    # Keep the pinned rust-analyzer ahead of rustup's proxy.
    (lib.lowPrio rustup)
    _7zz
    tmux
    unar
    uv
    yt-dlp
  ]);
}
