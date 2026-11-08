{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Chrome on macOS, Chromium on Linux; both read the same Chromium pref names.
  dataDir =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "${config.home.homeDirectory}/Library/Application Support/Google/Chrome"
    else
      "${config.xdg.configHome}/chromium";

  localState = {
    profile.info_cache.Default = {
      name = "Default";
      is_using_default_name = false;
    };
    performance_tuning = {
      intervention_notification.enabled = false;
      high_efficiency_mode.state = 0;
      battery_saver_mode.state = 0;
    };
    optimization_guide.on_device_foundational_model_user_settings = false;
  };

  preferences = {
    profile = {
      name = "Default";
      using_default_name = false;
      # 2 = block; sites can still be allowed individually.
      default_content_setting_values = {
        notifications = 2;
        media_stream_mic = 2;
        media_stream_camera = 2;
      };
    };
    # 3 = extended preloading.
    net.network_prediction_options = 3;
  };

  seed = pkgs.runCommand "chrome-profile-seed" { } ''
    mkdir -p "$out/Default"
    cp ${pkgs.writeText "local-state.json" (builtins.toJSON localState)} "$out/Local State"
    cp ${pkgs.writeText "preferences.json" (builtins.toJSON preferences)} "$out/Default/Preferences"
    touch "$out/First Run"
  '';
in
{
  # Seed once; an existing data directory is browser-owned and never touched.
  home.activation.chromeProfile = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    dir=${lib.escapeShellArg dataDir}
    if [ ! -e "$dir" ]; then
      run rm -rf "$dir.nix-seed"
      run mkdir -p "$(dirname "$dir")"
      run cp -R ${seed} "$dir.nix-seed"
      run chmod -R u+w,go-rwx "$dir.nix-seed"
      run mv "$dir.nix-seed" "$dir"
    fi
  '';
}
