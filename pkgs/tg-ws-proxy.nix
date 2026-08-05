{
  lib,
  src,
  python3Packages,
}:

python3Packages.buildPythonApplication {
  pname = "tg-ws-proxy";
  version = "1.9.1-unstable-${builtins.substring 0 8 (src.rev or "00000000")}";
  inherit src;

  pyproject = true;

  build-system = [ python3Packages.hatchling ];

  dependencies = with python3Packages; [
    cryptography
    pyperclip
    psutil
    pillow
    customtkinter
    pystray
    tkinter
  ];

  pythonRelaxDeps = true;

  pythonImportsCheck = [ "proxy" ];

  doCheck = false;

  postInstall = ''
    rm -f $out/bin/tg-ws-proxy-tray-win $out/bin/tg-ws-proxy-tray-macos
  '';

  meta = {
    description = "Local MTProto proxy server for partial bypassing of Telegram loading";
    homepage = "https://github.com/Flowseal/tg-ws-proxy";
    license = lib.licenses.mit;
    mainProgram = "tg-ws-proxy";
    platforms = lib.platforms.linux;
  };
}
