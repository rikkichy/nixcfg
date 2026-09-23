{ lib, pkgs, nixcfgPath, ... }:

{
  nixpkgs.hostPlatform = "aarch64-darwin";

  nix.package = pkgs.lix;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.channel.enable = false;

  environment.systemPackages = [ pkgs.nh ];
  environment.variables.NH_FLAKE = nixcfgPath;

  programs.fish.enable = true;

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

  networking.hostName = "ne";
  system.primaryUser = "rii";
  users.users.rii.home = "/Users/rii";
  users.users.rii.shell = pkgs.fish;

  system.defaults = {
    hitoolbox.AppleFnUsageType = "Do Nothing";
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      NSAutomaticWindowAnimationsEnabled = false;
      NSWindowResizeTime = 0.001;
      NSScrollAnimationEnabled = false;
      NSUseAnimatedFocusRing = false;
    };
    dock = {
      autohide = true;
      autohide-delay = 0.0;
      autohide-time-modifier = 0.0;
      expose-animation-duration = 0.0;
      mineffect = "scale";
      show-recents = false;
      launchanim = false;
    };
    universalaccess.reduceMotion = true;
    finder.FXPreferredViewStyle = "Nlsv";
    WindowManager.EnableTiledWindowMargins = false;
    trackpad = {
      Clicking = false;
      Dragging = false;
      TrackpadThreeFingerDrag = false;
    };
    CustomUserPreferences = {
      "com.apple.finder".DisableAllAnimations = true;
      NSGlobalDomain.QLPanelAnimationDuration = 0.0;
      "org.yanex.marta"."core.launchedBefore" = true; # Skip the first-launch tutorial.
    };
  };

  # nix-darwin has no per-power-source energy policy options.
  system.activationScripts.power.text = lib.mkAfter ''
    /usr/bin/pmset -b displaysleep 3 sleep 1 disksleep 10 powermode 0
    /usr/bin/pmset -c displaysleep 3 sleep 1 disksleep 10 powermode 2
  '';

  # Keep the initial compatibility version when upgrading nix-darwin.
  system.stateVersion = 6;
}
