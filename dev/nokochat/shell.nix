{ pkgs }:

let
  jdk = pkgs.jdk25;

  # Pins mirror nokochat's setup.sh / ci/self-hosted/Dockerfile: platform
  # android-37.0 + build-tools 37.0.0, and the emulator image the /simandroid
  # skill boots (google_apis_ps16k -- API 37 ships 16KB-page images only).
  # 36.0.0 is AGP 9.3's own default, which it fetches into the SDK on a writable
  # install and cannot fetch into a store one.
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

  # Skiko ships its native library through Maven, so `:composeApp:run` dlopen's
  # libraries that no Nix derivation knows it needs. Same list the packaged
  # AppImage carries in pkgs/nokochat.nix.
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

  # avdmanager writes to ~/.android; only the SDK itself is read-only.
  mkAvd = pkgs.writeShellScriptBin "noko-avd" ''
    set -euo pipefail
    img="system-images;android-37.0;google_apis_ps16k;x86_64"
    cfg="$HOME/.android/avd/noko.avd/config.ini"

    if ${sdk}/emulator/emulator -list-avds 2>/dev/null | grep -qx noko; then
      echo "AVD 'noko' already exists — $cfg"
      exit 0
    fi

    # pixel_10_pro is what setup.sh creates; fall back if this SDK's
    # devices.xml does not carry it yet.
    device=pixel_10_pro
    if ! ${sdk}/cmdline-tools/*/bin/avdmanager list device 2>/dev/null | grep -q "id: .*$device"; then
      echo "device $device unknown to this SDK — falling back to pixel_9_pro" >&2
      device=pixel_9_pro
    fi

    echo no | ${sdk}/cmdline-tools/*/bin/avdmanager create avd -n noko -k "$img" -d "$device"

    # CLI-created AVDs default to hw.keyboard=no, which silently blocks typing
    # from the host keyboard (documented /simandroid gotcha).
    # Anchored on the full key: hw.keyboard.charmap and hw.keyboard.lid sit
    # next to it and an unescaped dot rewrites those too.
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
      # app
      jdk
      android.androidsdk
      android-tools
      kotlin-lsp

      # server
      go
      golangci-lint
      gopls
      openssl

      # landing
      bun

      # repo tooling: the commit-msg secrets gate fails closed without
      # gitleaks, and CLAUDE.md standardises on fd/rg/jq.
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

  # AGP downloads aapt2 from Maven as a prebuilt FHS binary that cannot run
  # here; the override points it at the patched one from the Nix SDK. The
  # toolchain flags stop Gradle from provisioning a JDK the same way.
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
