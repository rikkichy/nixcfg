{ lib, ... }:

{
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
      NSGlobalDomain.NSFileViewer = "org.yanex.marta";
      "org.yanex.marta"."core.launchedBefore" = true; # Skip the first-launch tutorial.
    };
  };

  # nix-darwin has no per-power-source energy policy options.
  system.activationScripts.power.text = lib.mkAfter ''
    /usr/bin/pmset -b displaysleep 3 sleep 1 disksleep 10 powermode 0
    /usr/bin/pmset -c displaysleep 3 sleep 1 disksleep 10 powermode 2
  '';
}
