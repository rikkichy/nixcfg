{ lib, pkgs, ... }:

let
  dataDir = "/var/lib/minecraft";
  defaultLives = 3;
  # Offline UUIDs use UUID.nameUUIDFromBytes(("OfflinePlayer:" + exactName).getBytes(UTF_8)).
  # These approved names/UUIDs are public; AuthMe credentials stay in /var/lib/minecraft.
  whitelistSeed = {
    Rikkichy = "0af73b47-8167-37f3-9cdf-603b71c44efe";
    ekhosmerti = "c17f9db3-2f54-309f-97e7-abc962386de4";
    Denay39 = "c8370c8e-da88-3adb-bc8d-da394e793703";
  };
  serverProperties = {
    server-ip = "";
    server-port = 25565;
    max-players = 20;
    online-mode = false;
    white-list = true;
    enforce-whitelist = true;
    enforce-secure-profile = false;
    enable-rcon = false;
    enable-query = false;
    enable-jmx-monitoring = false;
    management-server-enabled = false;
    hide-online-players = true;
    view-distance = 8;
    simulation-distance = 6;
    motd = "WhatsApp Miku SMP";
  };
  propertiesFile = pkgs.writeText "server.properties" (
    lib.concatStringsSep "\n" (lib.mapAttrsToList
      (name: value: "${name}=${if builtins.isBool value then lib.boolToString value else toString value}")
      serverProperties) + "\n"
  );
  whitelistSeedFile = pkgs.writeText "whitelist-seed.json" (builtins.toJSON (
    lib.mapAttrsToList (name: uuid: { inherit name uuid; }) whitelistSeed
  ));
  operatorsFile = pkgs.writeText "ops.json" (builtins.toJSON [
    {
      name = "Rikkichy";
      uuid = whitelistSeed.Rikkichy;
      level = 4;
      bypassesPlayerLimit = false;
    }
  ]);
  eulaFile = pkgs.writeText "eula.txt" "eula=true\n";
  miniMOTD = pkgs.fetchurl {
    url = "https://cdn.modrinth.com/data/16vhQOQN/versions/Ch5nDFAs/minimotd-paper-2.2.5.jar";
    sha512 = "8516f9c92cb549984110d68270ebafee389fc25598a88431fb483677b675bf382f71f17bbef45f601f741a2333861472c96a3e8801a9c6c1dcb4e27af5923c19";
  };
  miniMOTDConfig = pkgs.writeText "minimotd-main.conf" ''
    motd-enabled=true
    # Use Minecraft's server-icon.png, not MiniMOTD's random icon pool.
    icon-enabled=false
    motds=[
      ${lib.concatMapStringsSep "\n" (subtitle: ''
        {
          line1="<bold><gradient:#25D366:#39FF14:#00D4C4>WhatsApp Miku SMP</gradient></bold>"
          line2=${builtins.toJSON "<gray>${subtitle}"}
        }
      '') [
        "хочу пельменей"
        "здарова чувырло"
        "алмазов нет, но вы держитесь"
        "заходи, суп остывает"
        "связь."
        "а можно сбер спасибо"
        "это ашибация"
        "руслан ебень"
        "лит энержи"
        "алексей сковородка"
        "колобок: новые сусеки 2027"
        "сквазимабзабза"
        "читать | продолжение.."
        "большая токмачка"
      ]}
    ]
    player-count-settings {
      max-players-enabled=false
      disable-player-list-hover=true
      hide-player-count=false
      fake-players { fake-players-enabled=false }
      just-x-more-settings { just-x-more-enabled=false }
    }
  '';
  authMe = pkgs.fetchurl {
    url = "https://github.com/AuthMe/AuthMeReloaded/releases/download/6.0.1/AuthMe-6.0.1-Paper.jar";
    sha256 = "7704335e9e73a634d9d926344f77897f4c74f78f82453a59f5aa0f8d2722450a";
  };
  authMeConfig = pkgs.writeText "authme-config.yml" ''
    DataSource:
      backend: SQLITE
    settings:
      serverName: WhatsApp Miku SMP
      logLevel: INFO
      useAsyncTasks: true
      useWelcomeMessage: false
      sessions:
        enabled: false
      restrictions:
        allowChat: false
        hideChat: true
        allowCommands:
          - /login
          - /log
          - /l
          - /register
          - /reg
          - /2fa
          - /totp
        ForceSingleSession: true
        kickNonRegistered: false
        kickOnWrongPassword: true
        allowMovement: false
        loginTimeout: 60
        registerTimeout: 60
        allowedNicknameCharacters: '[a-zA-Z0-9_]*'
      unrestrictions:
        UnrestrictedName: []
        UnrestrictedInventories: []
      security:
        minPasswordLength: 12
        passwordMaxLength: 64
        passwordHash: ARGON2ID
        legacyHashes: []
      registration:
        # Whitelisted newcomers register before entering the world.
        enabled: true
        force: true
        type: PASSWORD
        secondArg: CONFIRMATION
        dialog:
          showForgotPasswordButton: false
          preJoin:
            enable: true
            registerCancelKicks: true
            loginCancelKicks: true
          postJoin:
            enable: false
      preventOtherCase: true
      enablePremium: false
    Hooks:
      bungeecord: false
      proxySharedSecret: ""
    Security:
      SQLProblem:
        stopServer: true
      tempban:
        enableTempban: true
        maxLoginTries: 5
        tempbanLength: 15
        minutesBeforeCounterReset: 15
    BackupSystem:
      ActivateBackup: false
  '';
  skinsRestorer = pkgs.fetchurl {
    url = "https://github.com/SkinsRestorer/SkinsRestorer/releases/download/15.12.6/SkinsRestorer.jar";
    sha256 = "a85b4a370f988741c9a38f4d0498262edacbf3220314790ac1c127461996359c";
  };
  skinsRestorerConfig = pkgs.writeText "skinsrestorer-config.yml" ''
    login:
      noSkinIfLoginCanceled: true
      alwaysApplyPremium: false
    commands:
      forceDefaultPermissions: true
  '';
  socialUpstream = pkgs.fetchurl {
    url = "https://cdn.modrinth.com/data/SHhNKiri/versions/PacU9kWI/social-paper-0.7.2.jar";
    sha512 = "55716cc9bed4c6e245921194505492588f4adda6a7dd9ac507825c2de37870779a04c2aaaafbbcc0b3836df3977f9b2b9d8ea68372339004fe7bb13dc6422665";
  };
  gestalt = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/myth-MC/gestalt/cbfc61912897d0661f1f392db50fb05ce6fa1c10/gestalt-bukkit.jar";
    hash = "sha256-pNE5sLB9la/+p5ie0BH6vhN/7U5An4jK7xryCM6k8pg=";
  };
  # MD5 is the upstream loader's comparison format; fetchurl verifies SHA-256.
  gestaltChecksum = pkgs.runCommand "gestalt-0.3.2.md5" { } ''
    md5sum ${gestalt} | cut -d ' ' -f 1 > "$out"
  '';
  socialGestaltProperties = pkgs.writeText "social-gestalt.properties" ''
    checksum.1=file://${gestaltChecksum}
    server.1=file://${gestalt}
  '';
  social = pkgs.runCommand "social-paper-0.7.2.jar" {
    nativeBuildInputs = [ pkgs.zip ];
  } ''
    cp ${socialUpstream} "$out"
    chmod u+w "$out"
    zip -q -d "$out" gestalt.properties
    cp ${socialGestaltProperties} gestalt.properties
    touch -t 198001010000 gestalt.properties
    # Store this resource uncompressed so Nix retains both referenced files in
    # the image closure. The loader performs no network requests for Gestalt.
    zip -q -0 -X "$out" gestalt.properties
  '';
  socialChatConfig = pkgs.writeText "social-chat.yml" ''
    enabled: true
    defaultChannel: global
    groups:
      enabled: false
    channels:
      - name: global
        alias: null
        inherit: null
        color: "#FFFF55"
        permission: null
        commands: []
        icon: ""
        showHoverText: false
        hoverText: []
        nicknameColor: "#D3D3D3"
        textDivider: "<gray>:raw_divider:</gray>"
        textColor: "#FFFFFF"
        joinByDefault: true
  '';
  socialMotdConfig = pkgs.writeText "social-motd.yml" ''
    enabled: true
    message:
      - '<bold><gradient:#25D366:#39FF14:#00D4C4>WhatsApp Miku SMP</gradient></bold>'
      - '<gray>здарова, <green>$(nickname)</green></gray>'
      - ""
      - '<green>/lives</green><gray> — сколько осталось</gray>'
      - '<green>/lives give 1 \<ник></green><gray> — спасти друга</gray>'
      - '<gray>по понедельникам в <green>06:00 МСК</green> всем снова по <green>${toString defaultLives}</green> жизни</gray>'
  '';
  limitedLives = pkgs.fetchurl {
    url = "https://cdn.modrinth.com/data/LvTKDASD/versions/g6fmkYed/LimitedLives-4.2.2.jar";
    sha512 = "6c7490caa5dcb6f87def429ac7d896d34e99823fa83100461f259bdee92eb4178badf8b61c123d0aefe653cbee285ecffb0f08ae2dff45b40cd96d459a2f16df";
  };
  limitedLivesConfig = pkgs.writeText "limitedlives-config.yml" ''
    lives:
      default: ${toString defaultLives}
      max: 4
      min: 0
    death-causes: []
    worlds-blacklist:
      list: []
      act-as-whitelist: false
    keep-inventory:
      enabled: false
    grace-period:
      enabled: false
      duration: 60
      triggers: [FIRST_JOIN, REVIVE]
      bypass-causes: []
      disabled-damage-causes: []
    commands:
      punishment:
        death:
          - "minecraft:ban %player% Out of lives! Ask a friend to donate a life."
        respawn: []
      revive:
        - "minecraft:pardon %player%"
    obtaining:
      stealing: true
      crafting:
        enabled: false
  '';
  playerPermissionsFile = pkgs.writeText "permissions.yml" ''
    miku.lives.player:
      description: View and donate your own LimitedLives lives
      default: true
      children:
        limitedlives.get.self: true
        limitedlives.give: true
  '';
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
  # Real files, not store symlinks: only this directory is mounted into the image.
  managedConfig = pkgs.runCommand "minecraft-config" { } ''
    mkdir -p "$out"
    install -m 0444 ${eulaFile} "$out/eula.txt"
    install -m 0444 ${whitelistSeedFile} "$out/whitelist-seed.json"
    install -m 0444 ${operatorsFile} "$out/ops.json"
    install -m 0444 ${playerPermissionsFile} "$out/permissions.yml"
    install -m 0444 ${propertiesFile} "$out/server.properties"
    install -m 0444 ${../../dotfiles/minecraft/server-icon.png} "$out/server-icon.png"
    install -m 0444 ${miniMOTDConfig} "$out/minimotd.conf"
    install -m 0444 ${authMeConfig} "$out/authme.yml"
    install -m 0444 ${skinsRestorerConfig} "$out/skinsrestorer.yml"
    install -m 0444 ${limitedLivesConfig} "$out/limitedlives.yml"
    install -m 0444 ${socialChatConfig} "$out/social-chat.yml"
    install -m 0444 ${socialMotdConfig} "$out/social-motd.yml"
  '';
  entrypoint = pkgs.writeShellScript "minecraft-container-start" ''
    set -euo pipefail
    export PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.diffutils ]}
    umask 0077
    installPlugin() {
      if ! cmp -s -- "$1" "$2"; then
        install -m 0644 -- "$1" "$2"
      fi
    }
    if [[ ! -e .declarative ]]; then
      for file in eula.txt whitelist.json server.properties ops.json permissions.yml; do
        if [[ -e "$file" || -L "$file" ]]; then
          cp -P --backup=numbered -- "$file" "$file.stateful"
        fi
      done
    fi
    ln -sfn /etc/minecraft/eula.txt eula.txt
    # Preserve the current list when converting a store symlink to runtime state.
    if [[ -L whitelist.json || ! -e whitelist.json ]]; then
      whitelistSource=/etc/minecraft/whitelist-seed.json
      if [[ -L whitelist.json && -e whitelist.json ]]; then
        whitelistSource=whitelist.json
      elif [[ -L whitelist.json ]]; then
        # Old image closures are not mounted in the new container. The legacy
        # declarative list is immutable; seed it when its store target is absent.
        [[ "$(readlink -- whitelist.json)" = /nix/store/*-whitelist.json ]] || {
          echo "Refusing to replace an unknown dangling whitelist symlink" >&2
          exit 1
        }
      fi
      whitelistTmp=$(mktemp .whitelist.XXXXXXXX)
      trap 'rm -f -- "$whitelistTmp"' EXIT
      install -m 0600 -- "$whitelistSource" "$whitelistTmp"
      mv -T -- "$whitelistTmp" whitelist.json
      trap - EXIT
    fi
    chmod 0600 whitelist.json
    rm -f ops.json
    install -m 0600 /etc/minecraft/ops.json ops.json
    rm -f permissions.yml
    install -m 0600 /etc/minecraft/permissions.yml permissions.yml
    # Properties must be writable: Minecraft regenerates them during startup.
    rm -f server.properties
    cp /etc/minecraft/server.properties server.properties
    chmod 0600 server.properties
    install -m 0644 /etc/minecraft/server-icon.png server-icon.png
    mkdir -p plugins/MiniMOTD plugins/AuthMe plugins/SkinsRestorer plugins/LimitedLives plugins/social/settings
    installPlugin ${miniMOTD} plugins/MiniMOTD.jar
    # MiniMOTD saves normalized config on load, so this must be a writable copy.
    rm -f plugins/MiniMOTD/main.conf
    install -m 0600 /etc/minecraft/minimotd.conf plugins/MiniMOTD/main.conf
    installPlugin ${authMe} plugins/AuthMe.jar
    installPlugin ${skinsRestorer} plugins/SkinsRestorer.jar
    # Only public policy is replaced. Account databases and skin caches persist.
    rm -f plugins/AuthMe/config.yml plugins/SkinsRestorer/config.yml
    install -m 0600 /etc/minecraft/authme.yml plugins/AuthMe/config.yml
    install -m 0600 /etc/minecraft/skinsrestorer.yml plugins/SkinsRestorer/config.yml
    installPlugin ${limitedLives} plugins/LimitedLives.jar
    # Life counts and storage settings are runtime state; replace only gameplay policy.
    rm -f plugins/LimitedLives/config.yml
    install -m 0600 /etc/minecraft/limitedlives.yml plugins/LimitedLives/config.yml
    installPlugin ${social} plugins/social.jar
    # Legacy settings.yml takes precedence over settings/chat.yml; fail closed.
    if [[ -e plugins/social/settings.yml || -L plugins/social/settings.yml ]]; then
      echo "Remove social's legacy settings.yml after migrating it to settings/ before startup" >&2
      exit 1
    fi
    # Only chat and welcome policy are managed; social's database and other settings persist.
    rm -f plugins/social/settings/chat.yml plugins/social/settings/motd.yml
    install -m 0600 /etc/minecraft/social-chat.yml plugins/social/settings/chat.yml
    install -m 0600 /etc/minecraft/social-motd.yml plugins/social/settings/motd.yml
    touch .declarative
    mkfifo -m 0600 /tmp/minecraft.stdin
    exec 3<> /tmp/minecraft.stdin
    exec ${leaf}/bin/minecraft-server -Xms2G -Xmx8G <&3
  '';
  image = pkgs.dockerTools.buildLayeredImage {
    name = "leaf-minecraft-server";
    contents = [ pkgs.bash pkgs.coreutils pkgs.dockerTools.caCertificates ];
    config = {
      Entrypoint = [ entrypoint ];
      WorkingDir = "/data";
      User = "25565:25565";
      Env = [ "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt" ];
    };
  };
  imageRef = "${image.imageName}:${image.imageTag}";
  # Inspect exposes different IDs with Docker's classic and containerd stores.
  # Compare runnable content instead: platform, config and ordered layer hashes.
  # Extract once at build time; cache-hit starts never decompress the archive.
  imageIdentity = pkgs.runCommand "minecraft-image-identity.json" {
    nativeBuildInputs = [ pkgs.gnutar pkgs.gzip pkgs.jq ];
  } ''
    config=$(tar -xOf ${image} manifest.json | jq -er '.[0].Config')
    tar -xOf ${image} "$config" |
      jq -cS '{os, architecture, config, rootfs}' > "$out"
  '';
  ensureImage = pkgs.writeShellScript "minecraft-ensure-image" ''
    set -euo pipefail
    export PATH=${lib.makeBinPath [ pkgs.docker pkgs.coreutils pkgs.jq ]}
    expected=$(cat ${imageIdentity})
    inspectIdentity() {
      timeout 5s docker image inspect --format '{{json .}}' ${imageRef} |
        jq -cS '{os: .Os, architecture: .Architecture, config: .Config,
          rootfs: {type: .RootFS.Type, diff_ids: .RootFS.Layers}}'
    }
    actual=$(inspectIdentity 2>/dev/null) || actual=
    if [[ "$actual" != "$expected" ]]; then
      echo "Loading Minecraft image ${imageRef}"
      timeout 5m docker load --input ${image}
      actual=$(inspectIdentity)
      [[ "$actual" = "$expected" ]] || {
        echo "Minecraft image runtime content does not match the built archive" >&2
        exit 1
      }
    fi
  '';
  minecraftReady = pkgs.writeShellScript "minecraft-ready" ''
    set -euo pipefail
    export PATH=${lib.makeBinPath [ pkgs.docker pkgs.coreutils pkgs.gnugrep ]}
    attempts=''${1:-300}
    for ((attempt=0; attempt<attempts; attempt++)); do
      # ExecStartPost can run before docker run has created/started the container.
      if state=$(timeout 5s docker inspect --format '{{.State.Status}} {{.State.StartedAt}}' minecraft); then
        read -r status started <<< "$state"
        case "$status" in
          running)
            logs=$(timeout 5s docker logs --since "$started" minecraft 2>&1)
            if grep -F ' INFO]: Done (' <<< "$logs" > /dev/null &&
               grep -E '\[AuthMe\] AuthMe .* successfully enabled!' <<< "$logs" > /dev/null &&
               ! grep -F '[AuthMe] Disabling AuthMe' <<< "$logs" > /dev/null; then
              echo "Minecraft startup complete; AuthMe enabled"
              exit 0
            fi
            ;;
          created) ;;
          *)
            echo "Minecraft container entered $status before readiness" >&2
            exit 1
            ;;
        esac
      fi
      if ((attempt + 1 < attempts)); then
        sleep 1
      fi
    done
    echo "Minecraft is not ready: require completed Leaf startup and enabled AuthMe" >&2
    exit 1
  '';
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
      image = imageRef;
      imageFile = image;
      pull = "never";
      autoRemoveOnStop = false;
      volumes = [
        "${dataDir}:/data"
        "${managedConfig}:/etc/minecraft:ro"
      ];
      ports = [ "0.0.0.0:25565:25565/tcp" ];
      extraOptions = [
        "--read-only"
        "--cap-drop=ALL"
        "--security-opt=no-new-privileges:true"
        "--memory=12g"
        "--memory-swap=12g"
        "--stop-timeout=300"
        # SQLite JDBC, JNA and Netty load extracted native libraries from /tmp.
        "--tmpfs=/tmp:rw,exec,nosuid,nodev,size=1g,mode=1777"
      ];
    };
  };
  networking.firewall.allowedTCPPorts = [ 25565 ];

  # Unlike activationScripts, preSwitchChecks run before the old units stop.
  # Staging for boot and dry activation must not mutate the Docker image cache.
  system.preSwitchChecks.minecraftImage = ''
    case "$2" in
      switch|test)
        if ${pkgs.systemd}/bin/systemctl is-active --quiet docker.service; then
          ${ensureImage}
        else
          echo "Docker is not active; Minecraft will load its image at service start"
        fi
        ;;
    esac
  '';

  systemd.services.minecraft-server = {
    requires = [ "docker.service" ];
    # Pre-switch checks warm the image cache; this also covers boot, pruning,
    # and manual restarts without reimporting an already-loaded image.
    postStart = "${minecraftReady}";
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
      ExecStartPre = lib.mkForce [
        (pkgs.writeShellScript "minecraft-pre-start" ''
          set -euo pipefail
          ${ensureImage}
          docker rm -f minecraft || true
        '')
      ];
      TimeoutStartSec = lib.mkForce "6min";
      TimeoutStopSec = lib.mkForce "5min";
      Restart = lib.mkForce "always";
      RestartSec = "10s";
    };
  };

  systemd.timers.minecraft-lives-reset = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Mon *-*-* 06:00:00 Europe/Moscow";
      Persistent = true;
    };
  };
  systemd.services.minecraft-lives-reset = {
    description = "Weekly Minecraft life reset for online and offline players";
    requires = [ "minecraft-server.service" ];
    after = [ "minecraft-server.service" "minecraft-backup.service" ];
    path = [ pkgs.docker pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "6min";
      UMask = "0077";
    };
    script = ''
      set -euo pipefail
      # Requires/After waits for the server's postStart readiness gate.
      # Recheck once so a stopped or disabled AuthMe cannot receive reset commands.
      ${minecraftReady} 1
      # AnnoyingAPI's !all_players includes offline players, unlike vanilla @a.
      # LimitedLives runs its revive/pardon hook for each zero-to-positive change.
      timeout 5s docker exec minecraft ${pkgs.bash}/bin/bash -c \
        'printf "%s\n" "limitedlives:lives set ${toString defaultLives} !all_players" > /tmp/minecraft.stdin'
      echo "Submitted weekly reset to ${toString defaultLives} lives for all known players"
    '';
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
      # Cleanup waits for the server's six-minute start/readiness budget.
      TimeoutStopSec = "7min";
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
