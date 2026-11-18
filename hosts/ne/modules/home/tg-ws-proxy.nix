{ inputs, lib, pkgs, ... }:

let
  tg-ws-proxy = pkgs.callPackage ../../../../common/pkgs/tg-ws-proxy.nix {
    src = inputs.tg-ws-proxy;
  };
in
{
  # Loopback-only proxy; the secret is intentionally public and fixed so Telegram's saved entry stays valid.
  launchd.agents.tg-ws-proxy = {
    enable = true;
    config = {
      ProgramArguments = [
        (lib.getExe tg-ws-proxy)
        "--host"
        "127.0.0.1"
        "--port"
        "1443"
        "--secret"
        "cc9604c59c09cf22a6ab0e02c4b729e1"
      ];
      RunAtLoad = true;
      KeepAlive = true;
    };
  };
}
