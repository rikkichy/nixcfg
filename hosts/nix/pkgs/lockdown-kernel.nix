{ lib, applyPatches, linuxPackages_latest }:

let
  base = linuxPackages_latest;
  sources = {
    nvidia = base.nvidiaPackages.stable.open;
    nct6687 = base.nct6687d;
    v4l2loopback = base.v4l2loopback;
  };
  patchedSources = lib.mapAttrs (name: package: applyPatches {
    name = "${name}-kernel-source";
    inherit (package) src;
    patches = package.patches or [ ];
  }) sources;
  kernel = base.kernel.override {
    structuredExtraConfig = with lib.kernel; {
      MODULE_SIG = lib.mkForce yes;
      MODULE_SIG_ALL = yes;
      MODULE_SIG_FORCE = yes;
      MODULE_SIG_SHA512 = yes;
      MODULE_SIG_KEY_TYPE_RSA = yes;
      MODULE_SIG_KEY = freeform "certs/signing_key.pem";
      SECURITY_LOCKDOWN_LSM = lib.mkForce yes;
      SECURITY_LOCKDOWN_LSM_EARLY = yes;
      LOCK_DOWN_KERNEL_FORCE_INTEGRITY = yes;
    };
  };
in
kernel.overrideAttrs (old: {
  # A fresh build generates a fresh private key. Content addressing also changes
  # downstream initrd identities, so cached modules cannot outlive their signer.
  __contentAddressed = true;
  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
  preferLocalBuild = true;
  allowSubstitutes = false;

  # Keep the kernel and its complete signed module set together.
  outputs = [ "out" "dev" ];
  installFlags = map (flag:
    if lib.hasPrefix "INSTALL_MOD_PATH=" flag then
      "INSTALL_MOD_PATH=${builtins.placeholder "out"}"
    else flag
  ) old.installFlags;
  stripExclude = (old.stripExclude or [ ]) ++ [ "*.ko" ];

  preConfigure = (old.preConfigure or "") + ''
    export modules="$out"
  '';

  postBuild = (old.postBuild or "") + ''
    externalRoot="$NIX_BUILD_TOP/external-modules"
    mkdir -p "$externalRoot"
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: source: ''
      cp -R ${source} "$externalRoot/${name}"
    '') patchedSources)}
    chmod -R u+w "$externalRoot"
    patchShebangs "$externalRoot"

    externalFlags=(
      ${lib.escapeShellArgs base.kernel.commonMakeFlags}
      "--eval=undefine modules"
      "KBUILD_OUTPUT=$buildRoot"
    )
    nvidiaFlags=(
      "''${externalFlags[@]}"
      "SYSSRC=$(dirname "$buildRoot")" "SYSOUT=$buildRoot"
      "IGNORE_PREEMPT_RT_PRESENCE=1" "DATE=" "TARGET_ARCH=x86_64"
    )
    make -C "$externalRoot/nvidia" -j"$NIX_BUILD_CORES" "''${nvidiaFlags[@]}" modules
    for module in nct6687 v4l2loopback; do
      make -C "$buildRoot" -j"$NIX_BUILD_CORES" "''${externalFlags[@]}" \
        "M=$externalRoot/$module" modules
    done
  '';

  postInstall = (old.postInstall or "") + ''
    # Native modules_install removes the kernel/ directory; external installation
    # must follow it. Sign explicitly because Kbuild ignores external sign errors.
    moduleDir="$out/lib/modules/${kernel.modDirVersion}"
    externalInstallFlags=(
      "INSTALL_MOD_PATH=$out" "MODLIB=$moduleDir" "INSTALL_MOD_DIR=updates"
      "INSTALL_MOD_STRIP=1" "CONFIG_MODULE_SIG_ALL=" "CONFIG_MODULE_COMPRESS_ALL="
    )
    make -C "$externalRoot/nvidia" "''${nvidiaFlags[@]}" \
      "''${externalInstallFlags[@]}" modules_install
    for module in nct6687 v4l2loopback; do
      make -C "$buildRoot" "''${externalFlags[@]}" "M=$externalRoot/$module" \
        "''${externalInstallFlags[@]}" modules_install
    done
    for module in "$moduleDir"/updates/*.ko; do
      "$buildRoot/scripts/sign-file" sha512 \
        "$buildRoot/certs/signing_key.pem" "$buildRoot/certs/signing_key.x509" "$module"
      xz --check=crc32 --lzma2=dict=1MiB "$module"
    done
    depmod -b "$out" -a ${kernel.modDirVersion}
    install -m 0444 "$buildRoot/certs/signing_key.x509" "$out/module-signing.x509"
    rm "$buildRoot/certs/signing_key.pem"
    test ! -e "$dev/lib/modules/${kernel.modDirVersion}/build/certs/signing_key.pem"
    test ! -e "$dev/lib/modules/${kernel.modDirVersion}/source/certs/signing_key.pem"
  '';
})
