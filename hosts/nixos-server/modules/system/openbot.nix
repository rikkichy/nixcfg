{ lib, pkgs, ... }:

let
  seccompProfile = pkgs.fetchurl {
    name = "openbot-seccomp.json";
    url = "https://raw.githubusercontent.com/nightly-labs/openbot/4b39c9a497cfd4af7a718cfdeab52e2059ca6b91/docker/seccomp.json";
    hash = "sha256-ZlKJ5qHEEEX1UWbQsBmTySn3HfeOOjsmTzJSu44LPZ4=";
  };
in
{
  systemd.tmpfiles.rules = [
    "d /home/ri/vaults 0700 ri users -"
    "d /home/ri/vaults/Obsidian 0700 ri users -"
    "d /home/ri/vaults/Obsidian/OpenBot 0700 ri users -"
    "d /home/ri/vaults/Obsidian/Studies 0700 ri users -"
  ];

  virtualisation.oci-containers = {
    backend = "docker";
    containers.openbot = {
      image = "ghcr.io/nightly-labs/openbot:0.49.0@sha256:82359ce7029a03084c67ff4fd7c54a5f70053a74c5911837c1e89a02d983766a";
      autoStart = true;
      networks = [ "host" ];
      volumes = [ "openbot-data:/data" ];
      extraOptions = [
        "--mount=type=bind,source=/home/ri/vaults/Obsidian/OpenBot,target=/data/OpenBot/Shared/Obsidian"
        "--mount=type=bind,source=/home/ri/vaults/Obsidian/Studies,target=/data/OpenBot/Shared/Studies"
        "--security-opt=seccomp=${seccompProfile}"
        "--security-opt=no-new-privileges:true"
        "--shm-size=1g"
        "--stop-timeout=60"
      ];
    };
  };

  systemd.services.docker-openbot.serviceConfig = {
    Restart = lib.mkForce "always";
    RestartSec = "10s";
  };
}
