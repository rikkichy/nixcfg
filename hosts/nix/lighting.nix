{ config, pkgs, lib, ... }:

let
  stateDirectory = "/var/lib/openrgb-off";
  settings = pkgs.writeText "openrgb-off.json" (builtins.toJSON {
    Detectors.detectors = lib.genAttrs [
      "Elgato Light Strip"
      "Elgato Stream Deck MK.2"
      "ElgatoKeyLight"
      "Wooting 60HE"
      "Wooting 60HE (ARM)"
      "Wooting 60HE+"
      "Wooting 60HEv2"
      "Wooting 80HE"
      "Wooting One"
      "Wooting One (Legacy)"
      "Wooting Two"
      "Wooting Two (Legacy)"
      "Wooting Two HE"
      "Wooting Two HE (ARM)"
      "Wooting Two Lekker Edition"
      "Wooting UwU RGB"
    ] (_: false);
  });
in
{
  boot.kernelModules = [ "i2c-dev" "i2c-piix4" ];

  systemd.services.openrgb-off = {
    description = "Turn off RAM, GPU and motherboard RGB lighting";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" "systemd-udev-trigger.service" ];
    environment = {
      HOME = stateDirectory;
      XDG_CONFIG_HOME = stateDirectory;
      QT_QPA_PLATFORM = "offscreen";
    };
    preStart = ''
      ${pkgs.coreutils}/bin/install -m 0600 ${settings} ${stateDirectory}/OpenRGB.json
    '';
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "openrgb-off";
      StateDirectoryMode = "0700";
      TimeoutStartSec = "60s";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      BindReadOnlyPaths = lib.optional (config.environment.memoryAllocator.provider != "libc")
        "${pkgs.emptyFile}:${config.environment.etc."ld-nix.so.preload".source}";
      ExecStart = lib.escapeShellArgs [
        "${pkgs.openrgb}/bin/openrgb"
        "--config" stateDirectory
        "--noautoconnect"
        "--device" "ENE DRAM" "--mode" "Off"
        "--device" "Gainward GeForce RTX 3090 Phoenix" "--mode" "Off"
        "--device" "MSI MYSTIC LIGHT" "--mode" "Direct" "--color" "000000"
      ];
    };
  };
}
