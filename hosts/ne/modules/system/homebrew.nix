{
  homebrew = {
    enable = true;
    taps = [
      "can1357/tap"
      "facebook/fb"
      "hudochenkov/sshpass"
      "serpentiel/tools"
    ];
    brews = [
      "ast-grep"
      {
        name = "betterglobekey";
        start_service = true;
      }
      "cabextract"
      "can1357/tap/omp"
      "cmake"
      "facebook/fb/idb-companion"
      "fd"
      "ffmpeg"
      "git-filter-repo"
      "imagemagick"
      "innoextract"
      "libpq"
      "maigret"
      "openssh"
      "pipx"
      "pngquant"
      "poppler"
      "potrace"
      "railway"
      "rustup"
      "sevenzip"
      "tmux"
      "unar"
      "uv"
      "yt-dlp"
    ];
    casks = [
      "gcloud-cli"
      "helium-browser"
      "kotlin-lsp"
      "marta"
      "prismlauncher"
      "wallspace"
      "wireshark-app"
    ];
    onActivation = {
      cleanup = "none";
      autoUpdate = false;
      upgrade = false;
    };
  };
}
