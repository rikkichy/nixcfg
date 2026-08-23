{
  lib,
  buildFHSEnv,
  fetchurl,
  runCommand,
  symlinkJoin,
  writeShellScript,
  writeShellScriptBin,
  cacert,
  cudaPackages_13,
  curl,
  gcc,
  git,
  numactl,
  python312,
  uv,
  zlib,
}:

let
  pname = "freetoken";
  version = "0.1.2";

  # The runtime resolves from PyPI, but the kernel-cache wheel is published only
  # as a GitHub release asset -- PyPI answers 404 for the name -- so it is
  # pinned by URL and hash the way nokochat is. Its version has to track the
  # runtime's -- a mismatched cache drops the kernels it covers back to JIT.
  kernelCacheName = "freetoken_kernel_cache-${version}+cu130-py3-none-linux_x86_64.whl";

  # Given a wheel by path, uv parses its basename for the distribution, and a
  # store path prepends a hash to that -- one component too many, which it
  # rejects rather than ignores. So the wheel is placed in a directory of its
  # own under its published name.
  kernelCache =
    runCommand "freetoken-kernel-cache-${version}"
      {
        wheel = fetchurl {
          url = "https://github.com/FlashML-org/FreeToken/releases/download/v${version}/freetoken_kernel_cache-${version}%2Bcu130-py3-none-linux_x86_64.whl";
          hash = "sha256-pAHo0PuAQF6Z4SDyDEOyB2YhELK6ejuTyE4EiHwSCk8=";
        };
      }
      ''
        install -Dm444 "$wheel" "$out/${kernelCacheName}"
      '';

  cuda = cudaPackages_13.cudatoolkit;

  # Shared preamble. CUDA_HOME is what torch's and apache-tvm-ffi's JIT paths
  # read to find nvcc and the headers beside it; PATH inside the sandbox
  # already carries the toolkit, but neither looks there.
  preamble = ''
    set -euo pipefail
    FT_HOME="''${FREETOKEN_HOME:-$HOME/.freetoken}"
    VENV="$FT_HOME/venv"
    export CUDA_HOME=${cuda}
  '';

  setup = writeShellScript "freetoken-setup-inner" ''
    ${preamble}
    mkdir -p "$FT_HOME"

    # --clear rather than reuse: a venv left over from an earlier CUDA channel
    # keeps its torch, and the wheels below then link against the wrong
    # libtorch instead of being resolved afresh.
    uv venv "$VENV" --python ${python312}/bin/python3.12 --clear

    # Only flashinfer needs an index of its own: flashinfer-jit-cache is
    # published nowhere else, and it and flashinfer-cubin carry that project's
    # kernels prebuilt for every architecture -- ~2 GiB once, against a
    # multi-minute nvcc run at the first inference otherwise. torch 2.11.0 and
    # sglang-kernel 0.4.5 are on PyPI as the same cu130 builds their own
    # indexes serve, so those two are left out; `docs.sglang.io/whl/cu130/`
    # answers 308 to itself, and a resolver pointed at it hangs until its
    # retries run out rather than failing on the loop.
    #
    # unsafe-best-match because the flashinfer index carries versions of
    # packages PyPI also has, and uv's default first-index strategy would take
    # whichever it saw first rather than the best match across both.
    uv pip install --python "$VENV" \
      --index-strategy unsafe-best-match \
      --extra-index-url https://flashinfer.ai/whl \
      --extra-index-url https://flashinfer.ai/whl/cu130 \
      "freetoken[accel]==${version}" \
      flashinfer-cubin \
      flashinfer-jit-cache \
      "${kernelCache}/${kernelCacheName}"
  '';

  ft = writeShellScript "ft-inner" ''
    ${preamble}
    [ -x "$VENV/bin/ft" ] || ${setup}
    exec "$VENV/bin/ft" "$@"
  '';

  # The wheels are manylinux builds that resolve libstdc++, libgomp and
  # libcuda.so.1 through the loader's ordinary search rather than an RPATH, so
  # they need an FHS root. buildFHSEnv's generated ld cache carries
  # /run/opengl-driver/lib, which is the only place the driver's libcuda lives
  # and is named by neither /etc/ld.so.conf nor LD_LIBRARY_PATH inside the
  # sandbox.
  fhs = buildFHSEnv {
    name = "freetoken-env";

    targetPkgs = pkgs: [
      python312
      uv
      cuda
      # nvcc drives a host compiler for the parts of a kernel it does not
      # compile itself, and 13.2 accepts this gcc.
      gcc
      cacert
      curl
      git
      numactl
      zlib
    ];

    runScript = writeShellScript "freetoken-exec" ''exec "$@"'';
  };
in
symlinkJoin {
  name = "${pname}-${version}";

  paths = [
    (writeShellScriptBin "ft" ''exec ${fhs}/bin/freetoken-env ${ft} "$@"'')
    (writeShellScriptBin "freetoken-setup" ''exec ${fhs}/bin/freetoken-env ${setup}'')
  ];

  meta = {
    description = "Edge-native MoE serving engine for local frontier models";
    homepage = "https://github.com/FlashML-org/FreeToken";
    license = lib.licenses.asl20;
    mainProgram = "ft";
    platforms = [ "x86_64-linux" ];
  };
}
