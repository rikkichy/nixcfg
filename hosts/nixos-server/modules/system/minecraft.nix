{ config, lib, pkgs, ... }:

let
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
in
{
  services.minecraft-server = {
    enable = true;
    eula = true;
    package = leaf;
    declarative = true;
    dataDir = "/var/lib/minecraft";
    openFirewall = false;
    jvmOpts = "-Xms2G -Xmx8G";
    # Verified account names and UUIDs are public repository/store data.
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
  };
  networking.firewall.allowedTCPPorts = [ 25565 ];

  systemd.services.minecraft-server.serviceConfig = {
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ReadWritePaths = [ config.services.minecraft-server.dataDir ];
    MemoryMax = "12G";
    TimeoutStopSec = "5min";
    RestartSec = "10s";
  };

  systemd.tmpfiles.rules = [ "d /var/backup/minecraft 0700 root root -" ];
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
      data=${lib.escapeShellArg config.services.minecraft-server.dataDir}
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
