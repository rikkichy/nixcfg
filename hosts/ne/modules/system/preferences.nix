{ config, lib, ... }:

let
  home = config.users.users.rii.home;
in
{
  networking.applicationFirewall = {
    enable = true;
    enableStealthMode = true;
  };

  system.defaults = {
    hitoolbox.AppleFnUsageType = "Do Nothing";
    NSGlobalDomain = {
      AppleShowAllExtensions = true;
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
      mru-spaces = false;
    };
    universalaccess.reduceMotion = false;
    loginwindow.GuestEnabled = false;
    finder.FXPreferredViewStyle = "Nlsv";
    screencapture.location = "${home}/Pictures";
    WindowManager.EnableTiledWindowMargins = false;
    trackpad = {
      Clicking = false;
      Dragging = false;
      TrackpadThreeFingerDrag = false;
    };
    CustomUserPreferences = {
      "com.apple.finder".DisableAllAnimations = true;
      "com.apple.desktopservices" = {
        DSDontWriteNetworkStores = true;
        DSDontWriteUSBStores = true;
      };
      NSGlobalDomain.QLPanelAnimationDuration = 0.0;
      NSGlobalDomain.NSFileViewer = "org.yanex.marta";
      NSGlobalDomain.TSMLanguageIndicatorEnabled = false; # BetterGlobeKey owns input switching.
      NSGlobalDomain.AppleIconAppearanceTintColor = "Graphite";
      NSGlobalDomain.AppleAccentColor = 0;
      NSGlobalDomain.AppleMiniaturizeOnDoubleClick = false;
      "com.apple.loginwindow".TALLogoutSavesState = false;
      "com.apple.assistant.support"."Assistant Enabled" = false;
      "org.yanex.marta"."core.launchedBefore" = true; # Skip the first-launch tutorial.
    };
    CustomSystemPreferences."com.apple.SoftwareUpdate".CriticalUpdateInstall = true;
  };

  # nix-darwin has no per-power-source energy policy options.
  system.activationScripts.power.text = lib.mkAfter ''
    /usr/bin/pmset -b displaysleep 3 sleep 1 disksleep 10 powermode 0
    /usr/bin/pmset -c displaysleep 3 sleep 1 disksleep 10 powermode 2
  '';
}
