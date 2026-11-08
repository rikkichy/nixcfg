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
      "steam"
      "wallspace"
      "yubico-authenticator"
    ];
    # Signed App Store build keeps Touch ID and browser biometric unlock.
    masApps.Bitwarden = 1352778147;
    onActivation = {
      cleanup = "none";
      autoUpdate = false;
      upgrade = false;
    };
  };
}
