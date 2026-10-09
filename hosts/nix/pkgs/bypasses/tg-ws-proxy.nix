{
  lib,
  src,
  python3Packages,
}:

python3Packages.buildPythonApplication {
  pname = "tg-ws-proxy";
  version = "1.11.1-unstable-${builtins.substring 0 8 (src.rev or "00000000")}";
  inherit src;

  pyproject = true;

  build-system = [ python3Packages.hatchling ];

  dependencies = with python3Packages; [
    certifi
    cryptography
    httpx
    h2
  ];

  pythonRelaxDeps = true;
  pythonRemoveDeps = [
    "pyperclip"
    "psutil"
    "pillow"
    "customtkinter"
    "pystray"
    "pyobjc-framework-cocoa"
  ];

  pythonImportsCheck = [
    "proxy"
    "proxy.tg_ws_proxy"
    "utils.logging_setup"
  ];

  doCheck = false;

  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'tg-ws-proxy-tray-win = "windows:main"' "" \
      --replace-fail 'tg-ws-proxy-tray-macos = "macos:main"' "" \
      --replace-fail 'tg-ws-proxy-tray-linux = "linux:main"' "" \
      --replace-fail 'packages = ["proxy", "ui", "utils"]' 'packages = ["proxy", "utils"]' \
      --replace-fail '[tool.hatch.build.force-include]
    "windows.py" = "windows.py"
    "macos.py" = "macos.py"
    "linux.py" = "linux.py"' ""

    rm -r ui windows.py macos.py linux.py \
      utils/default_config.py utils/diagnostics.py utils/tray_common.py \
      utils/update_check.py utils/win32_theme.py

    # The server only needs logging_setup, not the package's tray updater exports.
    truncate -s 0 utils/__init__.py
  '';

  meta = {
    description = "Local MTProto proxy server for partial bypassing of Telegram loading";
    homepage = "https://github.com/Flowseal/tg-ws-proxy";
    license = lib.licenses.mit;
    mainProgram = "tg-ws-proxy";
    platforms = lib.platforms.linux;
  };
}
