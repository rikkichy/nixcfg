{ config, pkgs, lib, ... }:

let
  stateDirectory = "/var/lib/openrgb-off";
  # Use the package's complete registry: omitted detector keys default to enabled.
  settings = pkgs.runCommand "openrgb-off.json" {
    nativeBuildInputs = [ pkgs.openrgb pkgs.jq ];
  } ''
    export HOME="$TMPDIR" XDG_CONFIG_HOME="$TMPDIR" QT_QPA_PLATFORM=offscreen
    mkdir "$TMPDIR/config"
    # The Nix build sandbox has neither host hardware nor network access.
    test ! -e /sys/bus/usb/devices
    openrgb --config "$TMPDIR/config" --noautoconnect --list-devices
    jq --argjson enabled '${builtins.toJSON [
      "ENE SMBus DRAM"
      "Gainward GeForce RTX 3090 Phoenix"
      "MSI Mystic Light X870"
    ]}' '
      .Detectors.detectors
      | if type == "object" and ($enabled - keys | length == 0)
        then with_entries(.value = (.key as $name | $enabled | index($name) != null))
        | {Detectors: {detectors: .}}
        else error("Required OpenRGB detectors missing from package registry")
        end
    ' "$TMPDIR/config/OpenRGB.json" > "$out"
  '';
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
      Type = "exec";
      StateDirectory = "openrgb-off";
      StateDirectoryMode = "0700";
      TimeoutStartSec = "60s";
      RuntimeMaxSec = "60s";
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
