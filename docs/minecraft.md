# Minecraft operations

Related: [Server access](nixos-server.md#ssh-and-remote-sudo)

Recovery: [Inventory](#minecraft-inventory-recovery) ·
[Block and container history](#minecraft-block-and-container-history) ·
[Full backup restoration](#minecraft-backups-and-recovery)

## Contents

- [Deployment and access](#minecraft-deployment-and-access)
- [Network tuning](#minecraft-network-tuning)
- [Inventory recovery](#minecraft-inventory-recovery)
- [Block and container history](#minecraft-block-and-container-history)
- [Account provisioning](#minecraft-account-provisioning)
- [Social chat](#social-chat)
- [Backups and recovery](#minecraft-backups-and-recovery)

## Minecraft deployment and access

The server module builds a pinned Docker image containing Leaf **1.21.11 build
179** and Java 21. NixOS manages container `minecraft` through
`minecraft-server.service`; no Compose file or registry image is required.
The container has a **20-player ceiling**, `-Xms2G -Xmx8G`, and a 12 GiB Docker
memory limit with no additional swap allowance. Heap size is not total process
memory, and neither setting guarantees 20-player performance.
The server uses **offline mode** (`online-mode=false`, secure profiles disabled).
Pinned [AuthMeReloaded 6.0.1](https://github.com/AuthMe/AuthMeReloaded/releases/tag/6.0.1)
requires password authentication before entering the world; Mojang account
ownership is not verified. Sessions, premium auto-login and proxy login are
disabled. Whitelisted newcomers can register through the pre-join dialog;
existing accounts must log in. Passwords use Argon2id; five failed attempts trigger
a 15-minute IP ban. SQLite failure is configured to stop the server.
AuthMe's `welcome.txt` banner is disabled with `settings.useWelcomeMessage=false`;
authentication dialogs, prompts and error messages remain enabled.
The whitelist seed contains **Rikkichy**, **ekhosmerti** and **Denay39** with exact-case
offline UUIDs. The live whitelist is writable persistent server state.
**Rikkichy is the sole level-4 operator**, without a player-limit
bypass or AuthMe exemption. The module regenerates `ops.json` at startup:
runtime `/op` or `/deop` commands are not durable policy.
MiniMOTD owns the **WhatsApp Miku SMP** title, randomized subtitles and Miku icon.
Edit `miniMOTDConfig` and the icon source in `hosts/nixos-server/`, not generated
runtime files. See `hosts/nixos-server/modules/system/minecraft.nix` for pinned
plugins and presentation policy; changes require the approved deployment workflow.
Player names remain hidden in the server list.
Pinned [SkinsRestorer 15.12.6](https://github.com/SkinsRestorer/SkinsRestorer/releases/tag/15.12.6)
restores skins by name; authenticated players can use `/skin set <skinName>` and
`/skin clear`. Skin lookups are not account verification. Cancelled logins do not
trigger skin updates, and AuthMe's pre-login command list does not permit skin
commands. No RCON, query, JMX or management listener is provisioned.
MiniMOTD, AuthMe, SkinsRestorer, InventoryRollbackPlus, CoreProtect and social
are the provisioned plugins. All run as the game user and must be treated as
code. Managed public config templates are copied at startup; account databases,
skin caches, inventory snapshots, CoreProtect history and social user data persist.
There is no life limit, life-donation command or scheduled life reset. Startup
removes persisted LimitedLives JARs and its data directory when present, and
removes name bans with the exact reason
`Out of lives! Ask a friend to donate a life.` while preserving other bans.
The managed `permissions.yml` is cleared at startup; ordinary player access
uses the installed plugins' defaults. Existing backup archives are unchanged.
It runs as UID/GID **25565**, matching the host `minecraft` account, with all
capabilities dropped, no new privileges, a read-only image and a private `/tmp`
tmpfs with `exec,nosuid,nodev`: Java loads SQLite JDBC, JNA and Netty native
libraries extracted there. `/var/lib/minecraft` is bind-mounted at `/data`; deleting/recreating the
container does not delete the world. Backups and the Docker socket are not
mounted into the container. TCP 25565 is explicitly published on IPv4 only.
Docker-published ports bypass the ordinary NixOS input firewall, so removing an
`allowedTCPPorts` entry alone does not close this port; remove the publication
or stop the managed service instead.

Deployment, DNS and router changes require separate operator authorization:

1. On the server, inspect `free -h`, `df -h /var/lib /var/backup` and
   `ip -br -4 address`. If a directory is absent, inspect its nearest existing
   parent instead. Allow room for the 12 GiB service cap plus the OS and other
   workloads, and approximately eight compressed full backups plus the live
   world. A 16 GiB host is only a starting estimate, not verified capacity.
   Leave deployment pending on undersized hardware; do not silently reduce the
   selected capacity.
2. The module's `whitelistSeed` initializes a missing `whitelist.json`. An existing
   regular file is retained; a readable symlink is atomically converted to a
   writable copy of its contents. A legacy `/nix/store/*-whitelist.json` symlink
   whose target is absent from the container image is converted using the seed;
   other dangling symlinks stop startup rather than silently resetting membership.
   Seed changes never overwrite an existing writable list.
   After logging in as Rikkichy, manage membership with `/whitelist list`,
   `/whitelist add PlayerName` and `/whitelist remove PlayerName`. These commands
   persist under `/var/lib/minecraft/whitelist.json`, survive restarts/rebuilds
   and are included in backups; no deployment is needed for membership changes.
   Use exact-case names and coordinate AuthMe registration as described below.
   Offline UUIDs use Java
   `UUID.nameUUIDFromBytes(("OfflinePlayer:" + name).getBytes(UTF_8))`, not Mojang
   profile UUIDs; changing case changes identity. Seed names/UUIDs are public
   repository data, but passwords must never enter the repository or Nix store.
3. Back up any existing `/var/lib/minecraft` before starting this pinned version.
   Never open a newer-version world with an older server.
   Switching online/offline identity changes player UUIDs: inventory, ender chest,
   advancements, statistics and plugin ownership do not migrate automatically.
   If a world has online-mode players, leave deployment pending until a separately
   approved, backed-up migration maps each verified old UUID to the offline UUID.
   Do not blindly rename player files or assume Nix rollback restores identity.
   For an existing data tree, stop all writers and, after taking the backup, prepare ownership with
   `sudo chown -hR 25565:25565 /var/lib/minecraft` and
   `sudo chmod 0700 /var/lib/minecraft`. Ensure UID/GID 25565 are not assigned to
   an unrelated account; the module reserves them for `minecraft`. A fresh
   directory is created by NixOS. Evaluate/build the intended configuration
   through the approved deployment workflow, then obtain separate authorization
   to activate. From `/etc/nixos` on the server:

   ```sh
   nh os switch
   ```

   This uses the server's `NH_FLAKE=/etc/nixos` default. For an explicit
   checkout/host, use `nh os switch path:/etc/nixos --hostname nixos-server`.

   This deployment is required for startup-policy changes, not ordinary
   `/whitelist add` or `/whitelist remove` commands.
   Do not deploy or restart while a backup or restore is running.
   The underlying `nixos-rebuild switch` activation builds and fetches the
   system/image closure, then a pre-switch check imports the desired image while the old server is still
   running. The check runs for `switch` and `test` when Docker is already active;
   `boot`, `dry-activate` and standalone `check` do not import images. Import
   failure aborts before service stops, but the system profile may already point
   at the new generation; this is not an automatic profile rollback.
   If Docker is inactive, checks are bypassed, or the image was pruned, service
   startup loads it instead. This is a single-world stop/start deployment, not
   a rolling replacement with concurrent writers. Gestalt's bootstrap is local
   and pinned; other plugin loaders' first-start Maven downloads are not an
   offline closure.
4. Confirm local startup and working AuthMe login enforcement before publishing
   the endpoint. A running Leaf process does not prove that an authentication
   plugin loaded. If AuthMe fails to load or becomes disabled, stop the server;
   offline whitelist/OP identities alone provide no impersonation protection.
   Initial Leaf/plugin bootstrap may download runtime dependencies into the data
   directory; the pinned image is not an offline closure of first-start state.
   Preserve outbound DNS/HTTPS for bootstrap and skin services. Observe actual
   downloads rather than guessing a hostname allowlist.
5. Reserve the server's LAN IPv4 in router DHCP. Compare router WAN IPv4 with
   the public IPv4 reported by the ISP/router's external-address check. With
   public IPv4, forward WAN **TCP 25565** to server **TCP 25565**. For controllable
   double NAT, forward at both routers. A directly public server instead needs
   the equivalent provider firewall allowance. Do not enable DMZ/UPnP or forward
   SSH/RCON for Minecraft. Existing SSH, Hysteria and Avahi policy stays separate.
6. Create an **A** record named `mc` with the real public IPv4 and TTL 300 where
   supported. Leave the `rii.cat` apex and unrelated records unchanged; existing
   conflicting `mc` records require operator review. With Cloudflare, select
   DNS-only/grey cloud: ordinary HTTP proxying does not carry Minecraft.
   No SRV record is needed on the default port. Do not create AAAA: shared
   networking disables IPv6. No reverse HTTP proxy or extra TLS certificate
   is needed.
7. With private/CGNAT WAN IPv4 and no controllable upstream router, leave public
   deployment pending until the ISP supplies inbound-reachable IPv4. No VPN,
   tunnel or paid proxy is substituted. Update the A record when the address
   changes; automated DDNS is not provisioned.
8. Friends use **Minecraft Java 1.21.11 → Multiplayer → Add Server →
   `mc.rii.cat`**, using their exact whitelisted name and separate AuthMe password.
   Check access from outside the LAN; NAT hairpin behavior is not Internet reachability
   evidence. Public DNS reveals the server IP. Whitelisting, firewall rules and
   service isolation are not DDoS protection.

Administration over the existing SSH connection:

```sh
sudo docker logs -f minecraft
sudo journalctl -u minecraft-server -f
sudo systemctl status minecraft-server minecraft-backup.timer
sudo systemctl start minecraft-backup.service
sudo timeout 5s docker exec minecraft /bin/bash -c 'printf "list\n" > /tmp/minecraft.stdin'
```

Use FIFO console commands only while the container is running. Manage lifecycle
with `systemctl start|stop|restart minecraft-server`, not direct `docker stop`,
`docker restart` or `docker rm`: systemd owns restarts and backup coordination.
The stop hook sends console `stop` immediately, with no player warning or
countdown, including for backups and host shutdown. It waits for the server to
save and exit, requires exit code zero and rejects an OOM-killed container before
allowing backups. The stop-command budget is five minutes.
A hung stop fails the unit and prevents archive publication; subsequent systemd
termination and container cleanup can extend the total shutdown time.

The image has a Nix-derived tag. Preloading and service startup compare its OS,
architecture, complete runtime configuration and ordered filesystem-layer hashes
against the built archive. These fields verify runnable content independently of
Docker's backend-specific image-ID semantics. A matching image skips archive
import entirely; a missing or mismatched image is loaded and verified. Imports
have a five-minute timeout. A tag's presence alone is not accepted as proof.

Managed public templates and the icon are a separate immutable directory mounted
read-only at `/etc/minecraft`. Config-only changes change the mount's store path
and therefore restart the unit, without rebuilding the game image. The entrypoint
copies templates into writable runtime files where plugins require them; account
databases, the writable whitelist and game state remain in `/var/lib/minecraft`.
Plugin JARs stay in the image and are copied only when their bytes differ.
Server/plugin/JVM or entrypoint updates change the image; configuration edits do
not. Preloading reduces the stop/start outage, not the image import's total work
or the time Java, Leaf and plugins need to initialize.

The service's post-start gate waits for Docker to create and start the container,
then requires both Leaf's `Done (...)` message and AuthMe's successful-enable
message from that container start, with no AuthMe disable message. Absent or
created containers are pending startup, not immediate failures; exited or other
non-running states fail the check. The gate polls at one-second intervals for
up to 300 attempts. Systemd keeps the unit activating until the gate passes;
the entire start job has a six-minute timeout. This is a startup check, not
continuous health monitoring or proof of a successful client login.
Failed starts remain subject to the configured restart policy.
No RCON password or new SSH credential is needed. Pin updates deliberately,
back up first and test the chosen build before inviting players; do not
auto-fetch latest JARs.
After authorized deployment, operator acceptance includes external A resolution,
an empty AAAA answer, TCP 25565 reachability, no exposed RCON/query service,
a whitelisted newcomer completing registration and an existing account logging
in, with persisted world edits across graceful restart. Nonwhitelisted names and
wrong passwords must be rejected. After Rikkichy is registered, test a second
client impersonating that name: without the password it must not enter the world
or execute operator commands. Cancelling or timing out
the login dialog must disconnect. Check skins after login. Port scans do not
prove authentication. Inspect the timer schedule and a manual archive privately.
Report observed capacity only, not the configured player ceiling as a load result.

## Minecraft network tuning

`leafGlobalConfig` and `paperGlobalConfig` in
`hosts/nixos-server/modules/system/minecraft.nix` own
`/var/lib/minecraft/config/leaf-global.yml` and `paper-global.yml`.
Startup replaces both with writable templates; Leaf and Paper expand omitted
options to their pinned-version defaults. Put durable global settings in the
templates, not the generated files. World-specific configuration is unchanged.

Leaf enables `performance.reduce-packets.reduce-entity-move-packets` and
`reduce-entity-motion-packets` to filter redundant entity packets, plus
`async.async-chunk-send.enabled` to offload chunk preparation and sending.
Paper limits `chunk-loading-basic.player-max-chunk-send-rate` to **50 chunks
per second per player**. This caps chunk bursts at the cost of slower terrain
delivery during joins, teleports and fast travel; it is not a byte-rate cap.
View distance is 8 and simulation distance is 6. Network compression retains
the pinned server's threshold of 256, with native transport enabled.
Experimental async entity tracking and non-flush packet optimization remain off.

Use the approved rebuild/restart workflow; async chunk sending requires a
restart. These settings do not fix Internet routing, Wi-Fi loss or propagation
latency. After activation, compare existing-terrain play and exploration while
checking `/spark ping --player Denay39`, `/tps` and `/mspt`. Confirm client chunk
delivery and entity movement in-game; startup validation alone does not prove
lower latency or smoother play.

## Minecraft inventory recovery

Pinned [InventoryRollbackPlus 1.8.5](https://modrinth.com/plugin/inventoryrollbackplus/version/eDsOfX6z)
records inventories, armor, ender chests, XP and player status on death, join,
quit, world change and manual backup. It retains 50 death snapshots and 10 of
each other type per player, including empty inventories. Older snapshots roll
off at those limits. The plugin captures death inventories before most other
death handlers; items still drop normally.
Recovery only covers events recorded after the plugin is activated.

`inventoryRollbackConfig` in `hosts/nixos-server/modules/system/minecraft.nix`
owns public policy, copied to `plugins/InventoryRollbackPlus/config.yml` at
startup. Snapshots use local YAML storage under
`/var/lib/minecraft/plugins/InventoryRollbackPlus/`, persist across image
updates and are included in the daily offline archive. Display times use
`UTC+3` (Moscow); update checks and bStats are disabled.

As an authenticated operator, use:

```text
/irp forcebackup Denay39
/irp restore Denay39
```

The first command snapshots the online player's current state before a restore.
The second opens the backup menu: select the death category, timestamp and
inventory restore action. The full-inventory restore button requires the target
online and **overwrites their current inventory without making its own backup**.
Do not also recover the same dropped items or copy items out of the preview:
that can duplicate them. Restore only the intended inventory; teleport, XP,
health and ender-chest recovery are separate actions.

Restore/manual-backup permissions default to operators; ordinary players'
snapshots are automatic. Before relying on recovery after deployment, use a
disposable item to verify death capture and restoration through the in-game
menu. Installing the plugin requires the approved rebuild/restart workflow;
do not hot-load it into the running server.

## Minecraft block and container history

Pinned [CoreProtect Community Edition 24.1](https://modrinth.com/plugin/coreprotect/version/3sehX6Sg)
logs block changes, container transactions, item drops/pickups and other
gameplay events using its upstream logging defaults. Player command and chat
logging are disabled; authentication commands must not be stored as audit
history. Update checks and automatic error reporting are also disabled.
`coreProtectConfig` in the server module owns these settings and is copied to
`plugins/CoreProtect/config.yml` at startup.

CoreProtect uses SQLite at
`/var/lib/minecraft/plugins/CoreProtect/database.db`; the database persists
across rebuilds and is included in daily offline backups. No external database
or credentials are required. No automatic purge is configured: monitor disk
usage, and retain a backup before deliberately purging old history.
History only covers events recorded after activation.

As an authenticated operator, inspect blocks/containers with `/co inspect`
(repeat to disable), check `/co status`, or use scoped lookups:

```text
/co lookup u:Denay39 t:1h r:20 a:block
/co lookup u:Denay39 t:1h r:20 a:container
/co rollback u:Denay39 t:1h r:20 a:block #preview
```

The radius is centered on the operator. Review a preview before applying a
rollback without `#preview`; `/co restore` reapplies rolled-back actions.
Avoid broad/global rollbacks. Lookup, inspection and rollback permissions
default to operators; no additional player grants are provisioned.
Use InventoryRollbackPlus for full death-inventory snapshots, and do not
restore the same lost items through both plugins.

Deployment uses the approved image rebuild/restart workflow. After activation,
verify `/co status`, then place/break a disposable block and confirm its history
with the inspector before relying on production recovery.

## Minecraft account provisioning

Whitelisted players can connect using their exact name and create a unique
12–64-character password in the registration dialog, confirming it twice.
On subsequent connections they receive a login dialog. Where command-based
authentication is available, use `/register <password> <password>` and
`/login <password>`. Registration/login must finish before gameplay.

Offline whitelisting is not proof of identity: the first person using an
unregistered whitelisted name can claim it. Reserve **Rikkichy** before exposing
the server, and coordinate first registration with each friend. The
`authMeConfig` and `skinsRestorerConfig` module bindings own public policy, not
credentials. Whitelist and OP entries do not themselves create passwords.

After approved deployment, with the container running and AuthMe successfully
enabled, an operator can reserve each of the three names over existing SSH using
AuthMe's console `authme register` command. This prompt keeps the password out of
shell history, process arguments and terminal echo; do not use shell tracing,
terminal recording or command-audit plugins that record console input:

```sh
sudo docker exec -it minecraft /bin/bash -c '
  set -eu
  export LC_ALL=C
  read -rp "Exact player name: " name
  case "$name" in Rikkichy|ekhosmerti|Denay39) ;; *) exit 1 ;; esac
  read -rsp "Unique server password (12-64 visible ASCII characters): " password
  printf "\n"
  read -rsp "Repeat password: " confirmation
  printf "\n"
  [[ "$password" = "$confirmation" && "$password" =~ ^[!-~]{12,64}$ ]]
  printf "authme register %s %s\n" "$name" "$password" > /tmp/minecraft.stdin
  unset password confirmation
'
```

The command is asynchronous: privately inspect the registration success/error
message; writing the FIFO is not proof of account creation. AuthMe refuses to
overwrite an existing account. Transfer the unique password privately to its
owner; never use a Microsoft/Mojang, email or system password. After login, the
owner can change it with `/changepassword` and add TOTP with `/totp add`.
Password resets require identity verification by the operator, not merely a
claimed nickname. No email recovery provider is configured.

Offline Minecraft connections normally lack the online-mode encrypted transport.
AuthMe and its login dialog do not add network encryption: unique passwords
limit reuse damage but do not protect against network interception. Use a trusted
encrypted path when needed; none is provisioned here. Do not treat a restored
skin as proof of identity or grant permissions based on appearance.

AuthMe account hashes, IP history and any TOTP secrets live under
`/var/lib/minecraft/plugins/AuthMe`; SkinsRestorer state lives beside it under
`plugins/SkinsRestorer`. These are private runtime data, not Git/Nix inputs.
Full-world backups include them. Protect external copies accordingly, and remember
that restoring an old archive also rolls back passwords and authentication state.

## Social chat

[social 0.7.2 for Paper](https://modrinth.com/plugin/social-communication/version/PacU9kWI)
is hash-pinned for Minecraft 1.21.11. Players do not need a client mod.
PlaceholderAPI and DiscordSRV integrations are optional.
The required Gestalt 0.3.2 runtime JAR is fetched from an immutable upstream
commit and verified by SHA-256 during the Nix build. Social's embedded
`gestalt.properties` points both its checksum and download URLs at local
Nix-store files, so Gestalt bootstrap needs no network access. The resource
is stored uncompressed in the patched social JAR to preserve Nix closure
references inside the Docker image. MD5 is used only for the upstream loader's
local cache comparison, not artifact trust.
The loader repairs a mismatched or partial `plugins/social/libs/gestalt.jar`
from that local artifact. Other plugins and social's Maven libraries may still
need network access during their first startup.

`socialChatConfig` in `hosts/nixos-server/modules/system/minecraft.nix` owns
`plugins/social/settings/chat.yml`. Its keys use ConfigLib's camelCase names;
`joinByDefault: true` makes players members of the shared `global` channel so
they receive its messages. There is no staff channel, no channel-command aliases,
and no channel icon or hover prompt.
The groups module is disabled, so `/group` is not registered. The generic
`/social channel` subcommand remains upstream-provided, but there are no alternate
configured public channels to switch to. Private messages are separate from
player-created group channels and remain enabled, along with replies, mentions
and reactions. `socialMotdConfig` supplies a personalized Russian welcome in
`settings/motd.yml`: the gradient server title and `здарова, $(nickname)`.
AuthMe's separate welcome banner stays disabled. Other social settings retain
upstream defaults, including
disabled periodic announcements. Normal join/leave and death messages remain enabled.

Startup installs the JAR and writable chat/welcome policy copies; it does not overwrite
social's database, messages or other settings. A legacy `plugins/social/settings.yml`
would override the managed split configuration, so startup refuses it: migrate
and remove that legacy file before using this layout. Runtime edits to
`settings/chat.yml` and `settings/motd.yml` are overwritten at the next container start.
Social state is included in full-world backups and must stay out of Git.

After approved deployment, confirm social loads without errors and test normal
chat, replies, `/pm` and reactions between authenticated players. Confirm
`/group`, `/staff`, `/s`, `/global` and `/g` are not provided by social.
AuthMe's pre-login command allowlist is unchanged: do not add social commands.
Explicitly test that a client without successful authentication cannot send
chat, private messages or trigger reactions. Configuration evaluation and
source inspection are not proof of this integration.

## Minecraft backups and recovery

`hosts/nixos-server/modules/system/minecraft.nix` runs Leaf 1.21.11 build 179
with Java 21 in Docker. The Minecraft EULA is accepted. Host state lives in
`/var/lib/minecraft` (container `/data`); root-only completed archives live in
`/var/backup/minecraft` outside the container.
At **05:00 Europe/Moscow** the persistent timer stops the game, requires a clean
stop, archives the entire tree without dereferencing links, publishes by rename,
and retains seven completed archives. Cleanup attempts restart even after a
failed archive or forced stop. A missed timer can cause maintenance downtime
after boot. A successful systemd start requires the Leaf/AuthMe startup markers;
it does not prove a client can authenticate, join or persist world changes.

Invoke backups only through `sudo systemctl start minecraft-backup.service`.
Systemd serializes this unit; do not concurrently rebuild, restart the game or
restore. A stopped game is skipped without starting it or pruning archives.
Failed copies do not publish recovery points or prune completed archives.
Local root-only archives resist deletion by the game account, not root compromise,
disk failure or host loss. Keep an operator-controlled external copy.

Restoration requires separate operator approval and a trusted completed archive:

1. Stop scheduling with `sudo systemctl stop minecraft-backup.timer`. Wait for
   any in-flight backup (including its cleanup) to finish; inspect
   `sudo systemctl status minecraft-backup.service` until inactive or failed.
   Do not stop an in-flight backup merely to bypass this wait.
2. Run `sudo systemctl stop minecraft-server.service`. Require
   `sudo systemctl show minecraft-server -p ActiveState -p Result -p MainPID`
   to report `inactive`, `success`, and `0`. Investigate a forced/failed stop.
3. In a root shell, assign `archive` to the trusted absolute archive path.
   Run `gzip -t "$archive"` and `tar -tvzf "$archive"` and review all members:
   require only `minecraft/` and its descendants, no absolute names, no `..`
   path components, no escaping hard-link targets, and no device/FIFO entries.
   Preserve symbolic links as links (managed files may link into `/nix/store`);
   never use tar's dereference option. Do not extract an untrusted archive.
4. Extract into a fresh root-only staging directory, never onto the live tree:

   ```sh
   stage=$(mktemp -d /var/lib/minecraft-restore.XXXXXXXX)
   chmod 0700 "$stage"
   tar --extract --gzip --file "$archive" --directory "$stage" --no-same-owner
   test -d "$stage/minecraft" && test ! -L "$stage/minecraft"
   displaced=$(mktemp -d /var/lib/minecraft-displaced.XXXXXXXX)
   mv /var/lib/minecraft "$displaced/minecraft"
   mv "$stage/minecraft" /var/lib/minecraft
   chown -hR minecraft:minecraft /var/lib/minecraft
   chmod 0700 /var/lib/minecraft
   rmdir "$stage"
   ```

   Execute checked commands one at a time, or use a shell with `set -e`; stop
   on any error. Keep the printed/recorded `displaced` path for rollback.
   `chown -hR` does not traverse symlinks.
5. Start with the matching server/config version, then inspect
   `sudo docker logs -f minecraft` and verify the actual world and
   player state. Startup regenerates managed EULA, OP list, server properties
   and plugin policy; the writable whitelist and authentication databases are
   restored from the archive.
   A Nix generation rollback alone does not roll back world data; never open
   a newer-version world with an older server.
6. Preserve the displaced tree until acceptance. If recovery fails, stop the
   game, move the attempted tree to another unique recovery directory, and move
   `"$displaced/minecraft"` back to `/var/lib/minecraft`. Start the matching
   version and verify it. Restart `minecraft-backup.timer` only after acceptance.
