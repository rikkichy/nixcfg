{ config, inputs, pkgs, ... }:

let
  waydroidNvidia = inputs.waydroid-nvidia;
  waydroid = pkgs.callPackage ../../pkgs/waydroid.nix {
    waydroidNvidia = waydroidNvidia.packages.${pkgs.stdenv.hostPlatform.system};
  };
in

{
  programs.git.enable = true;

  environment.systemPackages = with pkgs; [
    google-chrome

    filen-cli


    yubioath-flutter
    age-plugin-yubikey
    yubikey-manager
    pam_u2f


    lm_sensors

    file-roller
    catfish

    swayimg
    mpv
    audacity
    qbittorrent
    obsidian
    bitwarden-desktop
    onlyoffice-desktopeditors

    discord
    telegram-desktop

    pavucontrol

    android-tools
    waydroid-pinch

    wl-clipboard nvtopPackages.nvidia yt-dlp

    glib

    hyprpicker
    adwaita-icon-theme
    qtengine

    playerctl
    xdg-user-dirs

    tg-ws-proxy
    trash-cli
  ];

  programs.localsend = {
    enable = true;
    openFirewall = false;
  };

  programs.obs-studio = {
    enable = true;
    package = pkgs.obs-studio.override { cudaSupport = true; };
    enableVirtualCamera = true;
  };

  services.gvfs.enable = true;

  services.ollama = {
    enable = true;
    # Keep the model blobs inside systemd's persistent DynamicUser state directory.
    modelsDir = config.services.ollama.home;
    environmentVariables.OLLAMA_NO_CLOUD = "1";
    # Inkling GGUF requires a newer llama.cpp runner than nixpkgs' Ollama 0.40.16.
    package = if pkgs.lib.versionAtLeast pkgs.ollama-cuda.version "0.40.18" then pkgs.ollama-cuda
      else (pkgs.ollama-cuda.override { cudaArches = [ "sm_86" ]; }).overrideAttrs (final: old: {
        version = "0.40.18";
        env = old.env // { CPATH = "${pkgs.cudaPackages.cuda_nvml_dev.include}/include"; };
        src = pkgs.fetchFromGitHub {
          owner = "ollama";
          repo = "ollama";
          tag = "v${final.version}";
          hash = "sha256-MO0AsCSNmrjf63NrdYzBDBL/xEftrHAacsf4gSXZf8g=";
        };
        passthru = old.passthru // {
          llamaCppVersion = "b12651";
          llamaCppSrc = pkgs.fetchFromGitHub {
            owner = "ggml-org";
            repo = "llama.cpp";
            tag = final.passthru.llamaCppVersion;
            hash = "sha256-GNdA6CFxrkFNSocjHhZT2ML53WkdvTSQBMieitPR1ts=";
          };
        };
      });
  };

  environment.etc."ollama/Inkling.Modelfile".text = ''
    FROM ~/Downloads/Inkling-2-Mini-abliterated-Mix-16G.gguf
    RENDERER inkling2
    PARSER inkling2
    PARAMETER num_ctx 131072
  '';

  programs.thunar = {
    enable = true;
    plugins = with pkgs; [
      thunar-volman
      thunar-archive-plugin
      thunar-vcs-plugin
    ];
  };

  services.tumbler.enable = true;

  programs.chromium = {
    enable = true;
    defaultSearchProviderEnabled = true;
    defaultSearchProviderSearchURL = "https://www.google.com/search?q={searchTerms}";
    extraOpts = {
      TranslateEnabled = false;
      PasswordManagerEnabled = false;
      # Address autofill also gates Autocomplete (previously typed field values).
      AutofillAddressEnabled = false;
      AutofillCreditCardEnabled = false;
      SavingBrowserHistoryDisabled = true;
      SearchSuggestEnabled = false;
      DefaultSearchProviderName = "Google";
      # Infostealers read cookies through the DevTools protocol port.
      RemoteDebuggingAllowed = false;
      # 2 = block. Web Wootility configures the Wooting keyboard over WebHID.
      DefaultWebUsbGuardSetting = 2;
      DefaultSerialGuardSetting = 2;
      DefaultWebHidGuardSetting = 2;
      DefaultWebBluetoothGuardSetting = 2;
      WebHidAskForUrls = [ "https://wootility.io" ];
      ExtensionSettings = {
        # Only the extensions below may be installed; others are disabled.
        "*".installation_mode = "blocked";
        # uBlock Origin Lite: installed (user may disable, not remove) and configured
        # through its managed storage schema.
        ddkjiahejlhfcafbddmgiahcphecmpfh = {
          installation_mode = "normal_installed";
          update_url = "https://clients2.google.com/service/update2/crx";
        };
        # Bitwarden: allowed, user-installed.
        nngceckbapebfimnlniiiahkandclblb.installation_mode = "allowed";
      };
      "3rdparty".extensions.ddkjiahejlhfcafbddmgiahcphecmpfh = {
        defaultFiltering = "complete";
        disableFirstRunPage = true;
        rulesets = [
          "+annoyances-cookies"
          "+annoyances-overlays"
          "+annoyances-social"
          "+annoyances-widgets"
          "+annoyances-notifications"
          "+annoyances-others"
          "+annoyances-ai"
          "+rus-0"
          "+rus-1"
        ];
      };
      NewTabPageLocation = "file://${pkgs.writeText "chromium-new-tab.html" ''
        <!doctype html>
        <html lang="en">
        <meta charset="utf-8">
        <meta name="color-scheme" content="dark">
        <title>New Tab</title>
        <style>html { background: #000; }</style>
        <body></body>
        </html>
      ''}";
    };
  };

  virtualisation.docker = {
    enable = true;
    enableOnBoot = false;
    autoPrune.enable = true;
  };

  virtualisation.waydroid = {
    enable = true;
    package = waydroid;
  };

  # waydroid-nvidia's container drop-in, restated because NixOS owns the unit directory:
  # start after the NVIDIA render node exists and refuse an ungated vendor image.
  systemd.services.waydroid-container = {
    wants = [ "sys-subsystem-waydroid_nvidia-render.device" ];
    after = [ "sys-subsystem-waydroid_nvidia-render.device" ];
    path = waydroid.runtimePath ++ [ config.system.path ];
    preStart = "${waydroid}/lib/waydroid-nvidia/native/dev/driver-mode verify-active";
  };
  services.udev.packages = [
    (pkgs.writeTextDir "lib/udev/rules.d/70-waydroid-nvidia-gpu.rules" (
      builtins.readFile "${waydroidNvidia.inputs.wnv-src}/packaging/aur/waydroid-nvidia-bin/waydroid-nvidia-gpu.rules"
    ))
  ];

}
