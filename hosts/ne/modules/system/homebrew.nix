{
  homebrew = {
    enable = true;
    taps = [
      "mmathys/tap"
    ];
    brews = [
      {
        name = "betterglobekey";
        start_service = true;
      }
      "maigret"
    ];
    casks = [
      "helium-browser"
      "marta"
      {
        name = "mmathys/tap/noswoosh";
        trusted = true;
      }
      "wallspace"
    ];
    onActivation = {
      cleanup = "none";
      autoUpdate = false;
      upgrade = false;
    };
  };
}
