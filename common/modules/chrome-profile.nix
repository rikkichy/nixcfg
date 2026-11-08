{
  config,
  lib,
  pkgs,
  ...
}:

let
  dataDir =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "${config.home.homeDirectory}/Library/Application Support/Google/Chrome"
    else
      "${config.xdg.configHome}/google-chrome";

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
    browser = {
      # Above any real milestone, so What's New never auto-opens.
      last_whats_new_version = 9999;
      # chrome://flags: one renderer process per origin instead of per site.
      enabled_labs_experiments = [
        "strict-origin-isolation@1"
        "origin-keyed-processes-by-default@1"
      ];
    };
    user_experience_metrics.reporting_enabled = false;
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
        geolocation = 2;
        sensors = 2;
        background_sync = 2;
        payment_handler = 2;
      };
      # 1 = block third-party cookies.
      cookie_controls_mode = 1;
    };
    enable_a_ping = false;
    media_router.enable_media_router = false;
    privacy_sandbox.m1 = {
      topics_enabled = false;
      fledge_enabled = false;
      ad_measurement_enabled = false;
    };
    # Hide local addresses from WebRTC without forcing calls through relays.
    webrtc.ip_handling_policy = "default_public_interface_only";
    # 3 = extended preloading.
    net.network_prediction_options = 3;
    vertical_tabs.enabled = true;
    browser = {
      # Past the restore-tabs infobar's show limit (3 in Chrome 157).
      session_restore_infobar_times_shown = 9999;
      enable_spellchecking = false;
    };
    # Google Password Manager off. WebAuthn with security keys, iCloud Keychain
    # and phones stays available; only creating passkeys in GPM is disabled.
    credentials_enable_service = false;
    credentials_enable_autosignin = false;
    translate.enabled = false;
    # Safe Browsing "No protection".
    safebrowsing = {
      enabled = false;
      enhanced = false;
    };
    # Always use secure connections: warn for public and private sites.
    https_only_mode_enabled = true;
    https_first_balanced_mode_enabled = false;
    # New Tab page: no shortcut tiles ("shortcust" is Chrome's own key) and no promo cards.
    ntp.shortcust_visible = false;
    in_product_help.ntp_promos.disabled = true;
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
