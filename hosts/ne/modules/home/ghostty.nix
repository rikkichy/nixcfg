{ ... }:

{
  programs.ghostty = {
    enable = true;
    package = null; # Keep the existing macOS application.
    settings = {
      theme = "Matugen";
      command = "/run/current-system/sw/bin/fish";
      background-opacity = 0.6;
      background-blur-radius = 20;
      font-family = "DepartureMono Nerd Font";
      font-size = 18;
      cursor-style = "block";
      cursor-style-blink = false;
      font-thicken = true;
      adjust-cell-height = 2;
      window-padding-balance = true;
      resize-overlay = "never";
      scrollback-limit = 10000;
    };
  };
}
