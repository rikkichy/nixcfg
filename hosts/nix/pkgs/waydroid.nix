{ fetchzip, runCommand, waydroidNvidia }:

let
  # Android 13 payload used by waydroid_script; keep in step with the Android image.
  source = fetchzip {
    url = "https://github.com/supremegamers/vendor_google_proprietary_ndk_translation-prebuilt/archive/68734c52556d3d7a6db34c603dd9276915c29f2f.tar.gz";
    hash = "sha256-hYpCOuyL/XkjONU7KfE6CU+14jbSzp9JBc8NmET6jXw=";
  };
  armTranslation = runCommand "waydroid-arm-translation-android13" { } ''
    mkdir -p "$out/system"
    cp -a ${source}/prebuilts/. "$out/system/"
  '';
  properties = [
    "ro.product.cpu.abilist=x86_64,x86,arm64-v8a,armeabi-v7a,armeabi"
    "ro.product.cpu.abilist32=x86,armeabi-v7a,armeabi"
    "ro.product.cpu.abilist64=x86_64,arm64-v8a"
    "ro.dalvik.vm.native.bridge=libndk_translation.so"
    "ro.enable.native.bridge.exec=1"
    "ro.vendor.enable.native.bridge.exec=1"
    "ro.vendor.enable.native.bridge.exec64=1"
    "ro.ndk_translation.version=0.2.3"
    "ro.dalvik.vm.isa.arm=x86"
    "ro.dalvik.vm.isa.arm64=x86_64"
  ];
in
waydroidNvidia.waydroid-nvidia-full.override {
  waydroid-nvidia = waydroidNvidia.waydroid-nvidia.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace tools/helpers/images.py \
        --replace-fail 'helpers.mount.mount_overlay(args, [tools.config.defaults["overlay"],' \
          'helpers.mount.mount_overlay(args, ["${armTranslation}", tools.config.defaults["overlay"],' \
        --replace-fail '        for prop in props:' \
          '        for prop in props + ${builtins.toJSON properties}:'
    '';
  });
}
