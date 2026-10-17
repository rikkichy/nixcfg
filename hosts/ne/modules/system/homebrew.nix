{
  homebrew = {
    enable = true;
    taps = [
      "facebook/fb"
      "mmathys/tap"
    ];
    brews = [
      "ast-grep"
      {
        name = "betterglobekey";
        start_service = true;
      }
      "cabextract"
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
      {
        name = "mmathys/tap/noswoosh";
        trusted = true;
      }
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
