{ inputs, lib, pkgs, ... }:

let
  seccompProfile = pkgs.writeText "openbot-seccomp.json"
    (builtins.readFile "${inputs.openbot}/docker/seccomp.json");
in
{
  virtualisation.oci-containers = {
    backend = "docker";
    containers.openbot = {
      image = "ghcr.io/nightly-labs/openbot:0.49.0@sha256:82359ce7029a03084c67ff4fd7c54a5f70053a74c5911837c1e89a02d983766a";
      autoStart = true;
      volumes = [ "openbot-data:/data" ];
      extraOptions = [
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
