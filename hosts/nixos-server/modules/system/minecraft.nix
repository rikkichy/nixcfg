{ lib, pkgs, ... }:

let
  dataDir = "/var/lib/minecraft";
  # Verified account names and canonical UUIDs are public repository/store data.
  whitelist = { };
  serverProperties = {
    server-ip = "";
    server-port = 25565;
    max-players = 20;
    online-mode = true;
    white-list = true;
    enforce-whitelist = true;
    enforce-secure-profile = true;
    enable-rcon = false;
    enable-query = false;
    enable-jmx-monitoring = false;
    management-server-enabled = false;
    hide-online-players = true;
    view-distance = 8;
    simulation-distance = 6;
    motd = "rii.cat — friends server";
  };
  propertiesFile = pkgs.writeText "server.properties" (
    lib.concatStringsSep "\n" (lib.mapAttrsToList
      (name: value: "${name}=${if builtins.isBool value then lib.boolToString value else toString value}")
      serverProperties) + "\n"
  );
  whitelistFile = pkgs.writeText "whitelist.json" (builtins.toJSON (
    lib.mapAttrsToList (name: uuid: { inherit name uuid; }) whitelist
  ));
  eulaFile = pkgs.writeText "eula.txt" "eula=true\n";
  leaf = pkgs.stdenvNoCC.mkDerivation {
    pname = "leaf-minecraft-server";
    version = "1.21.11-179";
    src = pkgs.fetchurl {
      url = "https://github.com/Winds-Studio/Leaf/releases/download/ver-1.21.11/leaf-1.21.11-179.jar";
      sha256 = "5da79782215c1a25edcd7c73b3523b7ecb7f4b86dc8a5846a176ed69bc2cd020";
    };
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.makeWrapper ];
    installPhase = ''
      runHook preInstall
      install -Dm644 "$src" "$out/lib/minecraft/server.jar"
      makeWrapper ${pkgs.jdk21_headless}/bin/java "$out/bin/minecraft-server" \
        --append-flags "-jar $out/lib/minecraft/server.jar nogui" \
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ pkgs.udev ]}
      runHook postInstall
    '';
    meta.mainProgram = "minecraft-server";
  };
  entrypoint = pkgs.writeShellScript "minecraft-container-start" ''
    set -euo pipefail
    export PATH=${lib.makeBinPath [ pkgs.coreutils ]}
    umask 0077
    if [[ ! -e .declarative ]]; then
      for file in eula.txt whitelist.json server.properties; do
        if [[ -e "$file" || -L "$file" ]]; then
          cp -P --backup=numbered -- "$file" "$file.stateful"
        fi
      done
    fi
    ln -sfn ${eulaFile} eula.txt
    ln -sfn ${whitelistFile} whitelist.json
    # Properties must be writable: Minecraft regenerates them during startup.
    rm -f server.properties
    cp ${propertiesFile} server.properties
    chmod 0600 server.properties
    touch .declarative
    mkfifo -m 0600 /tmp/minecraft.stdin
    exec 3<> /tmp/minecraft.stdin
    exec ${leaf}/bin/minecraft-server -Xms2G -Xmx8G <&3
  '';
  image = pkgs.dockerTools.buildLayeredImage {
    name = "leaf-minecraft-server";
    tag = leaf.version;
    contents = [ pkgs.bash pkgs.coreutils pkgs.dockerTools.caCertificates ];
    config = {
      Entrypoint = [ entrypoint ];
      WorkingDir = "/data";
      User = "25565:25565";
      Env = [ "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt" ];
    };
  };
in
{
  users.groups.minecraft.gid = 25565;
  users.users.minecraft = {
    uid = 25565;
    group = "minecraft";
    isSystemUser = true;
    home = dataDir;
  };

  virtualisation.oci-containers = {
    backend = "docker";
    containers.minecraft = {
      serviceName = "minecraft-server";
      image = "leaf-minecraft-server:${leaf.version}";
      imageFile = image;
      pull = "never";
      autoRemoveOnStop = false;
      volumes = [ "${dataDir}:/data" ];
      ports = [ "0.0.0.0:25565:25565/tcp" ];
      extraOptions = [
        "--read-only"
        "--cap-drop=ALL"
        "--security-opt=no-new-privileges:true"
        "--memory=12g"
        "--memory-swap=12g"
        "--stop-timeout=300"
        "--tmpfs=/tmp:rw,nosuid,nodev,size=1g,mode=1777"
      ];
    };
  };
  networking.firewall.allowedTCPPorts = [ 25565 ];

  systemd.services.minecraft-server = {
    requires = [ "docker.service" ];
    # A successful docker stop alone does not prove a clean save (SIGKILL may
    # have been needed). Send the console stop and require a clean Java exit.
    preStop = lib.mkForce ''
      set -euo pipefail
      ${pkgs.coreutils}/bin/timeout 5s docker exec minecraft \
        ${pkgs.bash}/bin/bash -c 'printf "stop\n" > /tmp/minecraft.stdin'
      code=$(docker wait minecraft)
      [[ "$code" = 0 ]]
      [[ "$(docker inspect --format '{{.State.OOMKilled}}' minecraft)" = false ]]
    '';
    postStop = lib.mkForce "docker rm -f minecraft";
    serviceConfig = {
      TimeoutStopSec = lib.mkForce "5min";
      Restart = lib.mkForce "always";
      RestartSec = "10s";
    };
  };

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0700 minecraft minecraft -"
    "d /var/backup/minecraft 0700 root root -"
  ];
  systemd.timers.minecraft-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 05:00:00 Europe/Moscow";
      Persistent = true;
    };
  };
  systemd.services.minecraft-backup = {
    description = "Offline Minecraft world backup";
    path = [ pkgs.systemd pkgs.coreutils pkgs.gnutar pkgs.gzip ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      UMask = "0077";
      RuntimeDirectory = "minecraft-backup";
      RuntimeDirectoryMode = "0700";
      TimeoutStartSec = "30min";
      TimeoutStopSec = "6min";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "/var/backup/minecraft" "/run/minecraft-backup" ];
    };
    script = ''
      set -euo pipefail
      export LC_ALL=C
      data=${lib.escapeShellArg dataDir}
      backup=/var/backup/minecraft
      runtime=/run/minecraft-backup
      unit=minecraft-server.service
      fail() { echo "$*" >&2; exit 1; }
      [[ -d "$data" && ! -L "$data" ]] || fail "Not a real Minecraft data directory"
      [[ "$(systemctl show "$unit" -p LoadState --value)" = loaded ]] ||
        fail "Minecraft unit is not loaded"
      active=$(systemctl show "$unit" -p ActiveState --value)
      sub=$(systemctl show "$unit" -p SubState --value)
      if [[ "$active/$sub" = inactive/dead ]]; then
        echo "Minecraft is stopped; skipping backup and retention"
        exit 0
      fi
      [[ "$active/$sub" = active/running ]] ||
        fail "Refusing backup of Minecraft in state $active/$sub"

      partial=$(mktemp "$backup/minecraft-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXXXX.partial")
      printf '%s\n' "$partial" > "$runtime/partial"
      touch "$runtime/restart-needed"
      systemctl stop "$unit"
      [[ "$(systemctl show "$unit" -p ActiveState --value)" = inactive &&
         "$(systemctl show "$unit" -p Result --value)" = success &&
         "$(systemctl show "$unit" -p MainPID --value)" = 0 ]] ||
        fail "Minecraft did not stop cleanly; refusing archive and retention"

      tar -C "$(dirname "$data")" -czf "$partial" "$(basename "$data")"
      mv -- "$partial" "''${partial%.partial}.tar.gz"
      echo "Published ''${partial%.partial}.tar.gz"
      # Bash glob order is lexical in the C locale; only our completed files count.
      shopt -s nullglob
      archives=()
      for archive in "$backup"/minecraft-*.tar.gz; do
        name=''${archive##*/}
        if [[ "$name" =~ ^minecraft-[0-9]{8}T[0-9]{6}Z-[a-zA-Z0-9]{8}\.tar\.gz$ &&
              -f "$archive" && ! -L "$archive" ]]; then
          archives+=("$archive")
        fi
      done
      for ((i=0; i<''${#archives[@]}-7; i++)); do
        rm -- "''${archives[i]}"
      done
    '';
    # ExecStopPost also runs on failed startup and timeout. Cleanup errors must
    # not short-circuit the independent attempt to return the game to service.
    postStop = ''
      set -uo pipefail
      runtime=/run/minecraft-backup
      status=0
      if [[ -f "$runtime/partial" ]]; then
        if IFS= read -r partial < "$runtime/partial" &&
           [[ "$partial" =~ ^/var/backup/minecraft/minecraft-[0-9]{8}T[0-9]{6}Z-[a-zA-Z0-9]{8}\.partial$ ]]; then
          rm -f -- "$partial" || status=1
        else
          echo "Invalid backup partial marker" >&2
          status=1
        fi
      fi
      if [[ -e "$runtime/restart-needed" ]]; then
        if manager=$(systemctl show -p SystemState --value); then
          if [[ "$manager" = stopping ]]; then
            echo "System is shutting down; leaving Minecraft stopped"
          elif systemctl start minecraft-server.service; then
            rm -- "$runtime/restart-needed" || status=1
          else
            echo "Minecraft restart failed after backup" >&2
            status=1
          fi
        else
          echo "Cannot query system manager state for Minecraft restart" >&2
          status=1
        fi
      fi
      exit "$status"
    '';
  };
}
