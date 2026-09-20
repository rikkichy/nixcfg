{ pkgs }:

let
  jdk = pkgs.jdk25;

  android = pkgs.androidenv.composeAndroidPackages {
    platformVersions = [ "37.0" ];
    buildToolsVersions = [
      "36.0.0"
      "37.0.0"
    ];
    includeEmulator = true;
    includeSystemImages = true;
    systemImageTypes = [ "google_apis_ps16k" ];
    abiVersions = [ "x86_64" ];
    includeSources = false;
    includeNDK = false;
    includeCmake = false;
  };

  sdk = "${android.androidsdk}/libexec/android-sdk";

  desktopLibs = with pkgs; [
    fontconfig
    freetype
    libGL
    libsecret
    libx11
    libxcursor
    libxext
    libxi
    libxrandr
    libxrender
    libxtst
  ];

  mkAvd = pkgs.writeShellScriptBin "noko-avd" ''
    set -euo pipefail
    img="system-images;android-37.0;google_apis_ps16k;x86_64"
    cfg="$HOME/.android/avd/noko.avd/config.ini"

    if ${sdk}/emulator/emulator -list-avds 2>/dev/null | grep -qx noko; then
      echo "AVD 'noko' already exists — $cfg"
      exit 0
    fi

    device=pixel_10_pro
    if ! ${sdk}/cmdline-tools/*/bin/avdmanager list device 2>/dev/null | grep -q "id: .*$device"; then
      echo "device $device unknown to this SDK — falling back to pixel_9_pro" >&2
      device=pixel_9_pro
    fi

    echo no | ${sdk}/cmdline-tools/*/bin/avdmanager create avd -n noko -k "$img" -d "$device"

    if grep -q '^hw\.keyboard=' "$cfg"; then
      sed -i 's/^hw\.keyboard=.*/hw.keyboard=yes/' "$cfg"
    else
      echo 'hw.keyboard=yes' >> "$cfg"
    fi
    echo "AVD 'noko' created ($device, hw.keyboard=yes)"
  '';
in
pkgs.mkShell {
  name = "nokochat";

  packages =
    (with pkgs; [
      jdk
      android.androidsdk
      android-tools
      kotlin-lsp

      go
      golangci-lint
      gopls
      openssl

      bun

      gitleaks
      fd
      ripgrep
      jq
      railway
    ])
    ++ [ mkAvd ];

  JAVA_HOME = "${jdk}";
  ANDROID_HOME = sdk;
  ANDROID_SDK_ROOT = sdk;

  GRADLE_OPTS = builtins.concatStringsSep " " [
    "-Dorg.gradle.project.android.aapt2FromMavenOverride=${sdk}/build-tools/37.0.0/aapt2"
    "-Dorg.gradle.java.installations.auto-download=false"
    "-Dorg.gradle.java.installations.paths=${jdk}"
  ];

  LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath desktopLibs;

  shellHook = ''
    echo "nokochat dev shell — jdk $(java -version 2>&1 | head -1 | cut -d'"' -f2) · go $(go version | cut -d' ' -f3) · bun $(bun --version)"
    echo "  SDK   $ANDROID_HOME"
    echo "  AVD   noko-avd (create the /simandroid emulator, one-off)"
  '';
}
