# nixcfg

NixOS and nix-darwin configurations with shared Home Manager shell and editor
settings. Clone to **`/etc/nixos`** on every host; `nixcfgPath` in `flake.nix`
provides that runtime path to the desktop and Mac.

## Hosts and guides

| Host | Platform | User | Guide |
| --- | --- | --- | --- |
| `nix` | `x86_64-linux`, Ryzen 9950X3D / RTX 3090 | `ri` | [NixOS installation and operations](docs/nix.md) |
| `ne` | `aarch64-darwin`, Apple Silicon | `rii` | [macOS bootstrap and applications](docs/ne.md) |
| `nixos-server` | `x86_64-linux`, headless UEFI / LUKS | `ri` | [Interactive installer](#interactive-linux-installer) |

- [Shared shell and editor](#shared-shell-and-editor)
- [Spotify and wallpaper colors](#spotify-and-wallpaper-colors)
- [Repository layout](#layout)
- [Validation and safety](#validation-and-safety)
- Linux recovery: [disk unlock](docs/nix.md#touch-only-disk-unlock),
  [boot menu](docs/nix.md#limine-recovery-with-a-zero-timeout),
  [sudo fallback](docs/nix.md#touch-only-sudo-with-password-fallback),
  [SOPS provisioning and recovery](docs/nix.md#private-inputs-and-first-provisioning).

## Interactive Linux installer

`install.nix` packages `scripts/install.sh` as `nix run path:.#install`.
On a networked x86_64 NixOS UEFI live ISO, clone into `/etc/nixos`:

```sh
sudo nix-shell -p git --run 'git clone https://github.com/rikkichy/nixcfg.git /etc/nixos'
cd /etc/nixos
```

If `/etc/nixos` already contains a checkout, use it instead; do not overwrite
existing configuration. The live ISO's `/etc/nixos` is the source checkout;
`/mnt/etc/nixos` is the installed target, populated by the installer.
Review the source, then start the guided installation from this directory:

```sh
sudo nix --extra-experimental-features 'nix-command flakes' run path:.#install
```

Optional: append `-- --plan` for read-only disk inventory and an outline of the
installation/recovery steps. This preview does not evaluate the host; the
installation itself evaluates it and repeats disk safety checks before erasing.

Select `nixos-server` for the headless server. `nix` is specifically the
Ryzen/NVIDIA desktop, not a generic desktop profile; `ne` is not installable
with this Linux tool. The server uses NetworkManager-managed DHCP, console
login, and key-only SSH on port 22; SSH password/keyboard-interactive
authentication and root login are disabled. No desktop session is enabled.

Both Linux hosts use the shared UEFI Limine policy in
`common/modules/nixos-limine.nix`, retaining ten generations. The desktop keeps
its zero-second timeout; the server displays the menu for five seconds.
Darwin does not import this module. LUKS/FIDO2 policy is independent of the loader.

On an existing server, migration is a bootloader update, not a reinstall.
For an approved migration, use `nh os boot path:/etc/nixos --hostname nixos-server
--install-bootloader`. Before separately approving reboot, inspect
`/boot/limine/limine.conf` and the Limine firmware entry. Retain the existing
systemd-boot EFI files, working generation, disk passphrase and recovery USB
until Limine has successfully booted and unlocked the installed system.

Before installation, ensure this checkout contains your FIDO2 SSH public key
in `hosts/nixos-server/default.nix`; local edits on another machine are not
included by cloning GitHub. The shared SSH module on `ne` and `nix` connects
as `ri` to `nixos-server.local`, advertised by the server through mDNS. The SSH
host-key identity stays `nixos-server.local` for both LAN and tunneled access.
After activating the client configuration, connect with:

```sh
ssh nixos-server
```

Securely provision the existing `~/.ssh/nixos-server` FIDO2 credential-handle
file on each client outside the checkout and Nix store. Home Manager activation
sets `~/.ssh` to mode `0700` and the handle file to `0600` when they exist;
it does not create or copy keys. Provision files with these permissions if
copying them after activation. The same YubiKey is required on either client.
Only resident credentials can recover their handle files with `ssh-keygen -K`;
non-resident credentials require the original handle file.

If the server's LAN address changes, find it with `ip -br address` at its
console and use `ssh -o HostName=SERVER_IP nixos-server`. Before client
activation, use `ssh -o IdentitiesOnly=yes -i ~/.ssh/nixos-server ri@SERVER_IP`.
Back up an unmanaged client `~/.ssh/config` before Home Manager takes ownership.

Verify the server host-key fingerprint through the console before accepting it.
The SSH YubiKey stays connected to the client and requires touch; the server
does not request FIDO2 user verification. An authenticator's AlwaysUV policy
or a local key-file passphrase can still require an additional prompt.
SSH does not unlock LUKS or forward the USB token. Server boot unlock needs a
server-side token or the disk passphrase.

For remote sudo, `nixos-server` enables `pam_rssh` for `sudo` and `sudo-i`.
It requests signatures through a forwarded SSH agent and trusts only the
root-controlled `/etc/ssh/authorized_keys.d/<user>` key inventory. The same
FIDO SSH key authorizes login and remote sudo; removing it from the server's
declarative authorized keys revokes both after activation. Server-local U2F
and the Unix account password remain fallback paths. Other hosts and PAM
services do not enable remote sudo authentication.

On the **client**, use an OpenSSH agent with FIDO security-key support, load
the existing credential handle, and connect:

```sh
ssh-add ~/.ssh/nixos-server
ssh nixos-server
```

An agent must already be running and selected through `SSH_AUTH_SOCK`.
`IdentityFile` alone does not load the key into an agent. For tunneled access,
use `ssh nixos-server-remote` after starting the configured tunnel.
The shared client configuration forwards the agent only for `nixos-server`
and `nixos-server-remote`. Activate that configuration on the connecting
client (`nix` or `ne`); rebuilding the server does not update client settings.
Before client activation, pass `-A` explicitly; use `-a` to disable forwarding
for an individual connection. Use a dedicated
agent containing only the server key where practical. A compromised server
can request signatures from a forwarded agent; touch does not identify the
requesting operation. Do not approve unexpected touches.

Activate server policy only with separate operator approval, using
`sudo nixos-rebuild switch --flake path:/etc/nixos#nixos-server`, while retaining
a working root recovery shell. Reconnect with forwarding and check `ssh-add -l`
on the server: it must list the expected `ED25519-SK` identity.
Invalidate sudo timestamps before each test: `sudo -k; sudo -v` and,
separately, `sudo -k; sudo -i`. Verify client key/touch success, cancellation
or no-touch without unintended authorization, absent agent/key with correct
password fallback, and rejection with an unauthorized key and wrong password.
Exit each test root shell without closing the recovery shell. Retain recovery
until both sudo services pass. Cached sudo authorization is not proof of touch;
evaluation and isolated PAM checks are not hardware-authentication proof.

Numbered menus select the host, disk and YubiKey. The target menu shows only
unused internal disks, with vendor/model and GiB/TiB sizes; choose "Show external
disks" to include eligible USB/removable targets. `--list-disks` shows the full
inventory and exclusion reasons. The final disk summary includes its serial
and requires `ERASE`; an incorrect response retries, while Ctrl+C cancels.
The installer creates a 4 GiB EFI partition plus a LUKS2/XFS root. Mounted disks,
active device-mapper/RAID holders, swap, live-media backing devices, mounted
Btrfs members and unresolved usage are rejected, including in the external
view. ZFS members require manual installation. Selection and disk identity
are rechecked before partitioning. This destroys the selected disk's existing
data; it is not an upgrade tool.

Only public source and encrypted ciphertext belong in the checkout. Before
erasing, the installer creates an independent Git checkout at the reviewed
source HEAD and overlays the reviewed working files, including local edits,
deletions, new files and tracked `.omp` resources. Source Git configuration,
hooks and credentials are not copied. The installed `main` branch tracks
`origin/main` at `https://github.com/rikkichy/nixcfg.git`.

Generated hardware and UUIDs replace only the installed
`hosts/<host>/hardware.nix`; the source checkout is unchanged. After user
creation, the installer assigns `/etc/nixos` to the target's `ri:users`.
Generated hardware and local edits remain uncommitted; new files are marked
intent-to-add so Git-based flakes can see them. As `ri`, use
`git pull --ff-only` and `nh os switch`; resolve upstream conflicts rather than
discarding the generated hardware file. No snapshot adoption is needed.
After formatting, udev identities are refreshed before hardware generation.
Before installation, the evaluated root, EFI and cryptroot configuration must
match the mapper and UUIDs read directly from the new filesystems/LUKS header.
Evaluation is not a full build, and post-erase failures require manual recovery.

Enter disk, root and `ri` passwords interactively; retain them independently
of the YubiKey. The token must be USB-visible to the server: KVM keyboard
forwarding is insufficient. Choose `0` to skip token enrollment.
Sudo and boot enrollments have separate `y/N` approvals before disk erasure.

`common/modules/nixos-yubikey.nix` provides both Linux hosts' systemd-initrd
FIDO2 discovery and touch-only sudo policy. Sudo registration is host-specific
(`pam://<hostname>`), stored root-owned at `/etc/u2f-mappings`, and keeps
password fallback. No token reset, recovery-slot removal, SOPS provisioning,
or automatic reboot is performed. On failure, keep the recovery shell and
inspect `/mnt` and `cryptroot`; do not rerun the erasing installer as recovery.
Use the [disk](docs/nix.md#touch-only-disk-unlock) and
[sudo](docs/nix.md#touch-only-sudo-with-password-fallback) acceptance checklists
with the selected hostname before relying on touch-only authentication.

Developer checks: `bash scripts/install-test.sh` with Git, Nix, jq and GNU tar
on PATH (also available through the packaged installer), packaged `--help`/`--plan`,
the standard full validation, and
`nix build --dry-run 'path:.#nixosConfigurations.nixos-server.config.system.build.toplevel'`.
Mocks and evaluation do not prove disk installation, live PAM, or cold boot.
The real stale-UUID regression is `sudo bash scripts/install-uuid-test.sh` in a
disposable Linux VM with the installer's runtime tools on PATH. It uses private
loop devices and briefly pauses udev; do not run it on a production host.
It checks hardware generation against changed on-disk metadata, not a full
installation or boot.

All three hosts import the system module `common/modules/nh.nix`, which installs
`nh` and sets `NH_FLAKE=/etc/nixos`. Use `nh os switch` on either Linux host and
`nh darwin switch --hostname ne` on the Mac. The server does not need Home Manager
for this shared command.

### Adopt the installed snapshot

Use this recovery procedure only when `/etc/nixos` contains installed source
and generated hardware but lacks Git metadata. The guided installer normally
creates a user-owned checkout. Keep using `path:` rebuilds until adoption is
complete; do not clone over the snapshot or replace its hardware file.

Run the following in Bash as `ri`, only when `/etc/nixos/.git` does not exist.
First preserve a separate, root-only backup, then give `ri` ownership of the
public configuration tree:

```sh
backup=$(sudo mktemp -d /var/lib/nixcfg-installed.XXXXXX)
sudo cp -a /etc/nixos "$backup/"
printf 'Installed snapshot backup: %s/nixos\n' "$backup"
sudo chown -R "$(id -u):$(id -g)" /etc/nixos
```

Create fresh metadata and fetch the public upstream. A **mixed** reset populates
the index and establishes a baseline without changing any working files:

```sh
cd /etc/nixos
git init -b installed
git remote add origin https://github.com/rikkichy/nixcfg.git
git fetch origin
git remote set-head origin --auto
git reset --mixed origin/HEAD
git status --short
git diff
```

The baseline is the fetched upstream default branch, not necessarily the
revision used for installation. Review the differences before updating or
publishing: they include generated hardware, installation-time source edits,
and any upstream changes since installation. If the snapshot lacks tracked
`.omp` resources, those files appear deleted; restore only that directory with
`git restore --source=HEAD --staged --worktree -- .omp` if desired.
Never use `reset --hard` or a blanket restore to resolve this diff.

Stage only reviewed public paths (including `hosts/<host>/hardware.nix`) and
commit the installed configuration before merging upstream updates. Do not
stage plaintext secrets or private identities. The `installed` branch has no
tracking branch; use an explicit `git fetch origin` and reviewed
`git merge origin/HEAD` for updates. Keep the backup until the adopted
configuration has built and booted successfully.

### Server services and private provisioning

`hosts/nixos-server/modules/system/services.nix` supplies OMP, YubiKey Manager,
`age-plugin-yubikey`, PC/SC, Docker with weekly native pruning, and the Moscow
timezone. `ri` can manage Docker and NetworkManager; Docker membership is
root-equivalent. Pruning may remove stopped containers and unused resources,
but does not opt into volume pruning. PC/SC access is granted only to `ri` for
context/card operations; SSH authentication does not forward a client YubiKey.

Both Linux hosts share NetworkManager and Avahi. Mihomo/TUN, the `vpn` command
and VPN secret provisioning belong only to the desktop host `nix`.
The server does not import desktop gaming/LAN firewall ports. The first approved
network migration belongs at the console/KVM: it replaces dhcpcd ownership and
disables IPv6, so an existing SSH connection can drop. Verify addressing, DNS
and SSH before leaving that console; no network activation is automatic here.

`nixos-server` has no Mihomo service, configuration renderer or SOPS import.
It needs no `/etc/mihomo` inputs or VPN age identity.

#### Minecraft deployment and access

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
The server-list title is **WhatsApp Miku SMP**, rendered in a green-to-aqua
gradient by pinned [MiniMOTD 2.2.5](https://modrinth.com/plugin/minimotd/version/Ch5nDFAs)
for Paper. The second line is randomly selected from fourteen Russian subtitles
in `miniMOTDConfig` on each server-list ping; consecutive picks can repeat.
The 64×64 PNG at `hosts/nixos-server/dotfiles/minecraft/server-icon.png` supplies
the Miku icon. The container startup copies it to `/data/server-icon.png` and
installs the hash-pinned plugin as `plugins/MiniMOTD.jar`. The module owns the
`miniMOTDConfig` template, copied to writable `plugins/MiniMOTD/main.conf` on each
start; edit the template rather than the generated file. MiniMOTD icon overrides,
fake player counts and max-player overrides are disabled; player names remain
hidden. Changes require the approved image rebuild and service restart workflow.
Pinned [SkinsRestorer 15.12.6](https://github.com/SkinsRestorer/SkinsRestorer/releases/tag/15.12.6)
restores skins by name; authenticated players can use `/skin set <skinName>` and
`/skin clear`. Skin lookups are not account verification. Cancelled logins do not
trigger skin updates, and AuthMe's pre-login command list does not permit skin
commands. No RCON, query, JMX or management listener is provisioned.
MiniMOTD, AuthMe, SkinsRestorer, LimitedLives and social are the provisioned plugins.
All run as the game user and must be treated as code. Managed public config
templates are copied at startup; account databases, skin caches, saved life
counts and social user data persist.
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
   sudo nixos-rebuild switch --flake path:/etc/nixos#nixos-server
   ```

   This deployment is required for startup-policy changes, not ordinary
   `/whitelist add` or `/whitelist remove` commands.
   Do not deploy or restart while a backup or restore is running.
   `nixos-rebuild switch` builds and fetches the system/image closure, then a
   pre-switch check imports the desired image while the old server is still
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

#### Minecraft account provisioning

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

#### Social chat

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
`settings/motd.yml`: the gradient server title, `здарова, $(nickname)`, life
commands and the Monday 06:00 Moscow reset reminder. AuthMe's separate welcome
banner stays disabled. Other social settings retain upstream defaults, including
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

#### LimitedLives gameplay

[LimitedLives 4.2.2](https://modrinth.com/plugin/limitedlives/version/g6fmkYed)
is the pinned stable release for Paper-compatible Minecraft 1.21.11. Its required
AnnoyingAPI dependency is embedded; PlaceholderAPI and WorldGuard are optional
and are not provisioned.

Edit `limitedLivesConfig` in `hosts/nixos-server/modules/system/minecraft.nix`.
Startup installs it as `/var/lib/minecraft/plugins/LimitedLives/config.yml`.
Use the approved rebuild/restart workflow for durable changes; direct edits to
that generated config are overwritten on the next container start.

| Setting | Configured behavior | Alternatives |
| --- | --- | --- |
| `lives.default`, `max`, `min` | 3 starting, 4 maximum, punishment at 0 | Change starting/cap/threshold values |
| `death-causes` | Empty list: all death causes cost a life | Restrict to causes such as `PLAYER_ATTACK` or `FALL` |
| `commands.punishment.death` | Vanilla name ban immediately at zero lives; no expiry | Console commands with `%player%` and `%killer%` placeholders |
| `commands.revive` | Vanilla pardon when lives increase above zero | Custom console commands |
| `obtaining.stealing` | A PvP killer gains a life, up to their maximum | Set `false` to disable |
| `obtaining.crafting.enabled` | Disabled: no craftable life item | Enable with a configured recipe, item, amount and trigger |
| `grace-period` | Disabled; template supplies 60 seconds for `FIRST_JOIN`/`REVIVE` if enabled | Duration, triggers and cause exceptions |
| `worlds-blacklist` | Empty: all worlds | Exclude worlds, or set `act-as-whitelist=true` to allow only listed worlds |
| `keep-inventory.enabled` | Disabled: vanilla gamerule behavior is retained | Plugin-specific keep/drop/destroy rules; requires `keepInventory=false` |

Do not enable the plugin's inventory rules casually: upstream warns of inventory
loss if combined with the vanilla keepInventory gamerule. Its rule index is
`max lives - current lives`, not a historical death counter.

Operator commands (amount precedes the target name):

```text
/lives get Rikkichy
/lives set 3 Rikkichy
/lives add 1 ekhosmerti
/lives remove 1 Denay39
/lifereload
```

A surviving player rescues a banned friend with:

```text
/lives give 1 Rikkichy
```

This transfers a life, rather than creating one. The donor needs at least two
lives and retains at least one; the recipient may be offline. Moving from zero
to one life triggers `minecraft:pardon`, allowing the rescued player to reconnect
and authenticate with one life. No timed-ban plugin is used.
If everyone is at zero before the weekly reset, the operator can run `lives add 1 <name>` through the
existing FIFO console to rescue someone. A bare pardon does not restore lives.
Revival intentionally pardons any name ban for that player, including a manual
moderation ban; this friends-server policy does not distinguish ban reasons.

**Weekly reset:** `minecraft-lives-reset.timer` runs on **Monday at 06:00
Europe/Moscow**, after the daily 05:00 backup slot. It sets every known player's
lives to the configured default (3), including offline players and players with
4 lives. Zero-to-positive changes invoke the same pardon hook as donations.
The world and inventories are not reset. Players can donate to rescue friends
before Monday; this is a shared calendar schedule, not seven days per death.

The persistent timer catches a missed run after host downtime. Its service
starts Minecraft if stopped, orders itself after any queued backup, and waits
for the server's Leaf/AuthMe readiness gate. It rechecks readiness once before
writing `limitedlives:lives set 3 !all_players` through the private console FIFO.
The pinned plugin's `!all_players` selector includes offline players; vanilla
`@a` does not. `defaultLives` in the module supplies both new-player lives and
the reset amount. No database edits or additional plugin are needed.

Inspect `systemctl list-timers minecraft-lives-reset.timer` and
`journalctl -u minecraft-lives-reset.service` on the server. A successful service
means the command was submitted, not that the plugin acknowledged every change;
check the Minecraft console's per-player responses and `/lives get <name>` for
acceptance. Startup or console transport failures fail the service without a
reset retry. Manual runs of the service also reset lives immediately.

The module's `playerPermissionsFile` installs managed `/data/permissions.yml`.
Its default parent permission grants `limitedlives.get.self` and
`limitedlives.give`, so ordinary authenticated players can check their own lives
and donate. No admin add/set/remove, ban/pardon, bypass or wildcard permissions
are granted. AuthMe still blocks `/lives` before login. Operator commands retain
their upstream permissions; `limitedlives.bypass` defaults to false even for
operators, so Rikkichy is not automatically exempt from life loss.
`limitedlives.max.<number>` can override a player's cap; no permission-manager
plugin is required for the two default player grants.

`/lifereload` rereads the runtime gameplay config. Use the approved restart
workflow for managed changes, especially permissions or crafting recipes.

Life counts are UUID-keyed persistent plugin state under
`/var/lib/minecraft/plugins/LimitedLives`, included in full-world backups.
Startup replaces only the JAR and `config.yml`, not storage settings or data.
Changing `lives.default` affects players without a stored life count; it does not
reset saved counts. Lowering the maximum does not automatically clamp existing
counts either. Use `/lives set 3 <name>` for a deliberate reset, rather than
deleting storage. Existing spectators need an operator to restore their survival
mode; this policy does not switch gamemodes. Restoring a backup also restores
its saved life counts and vanilla ban list.
See the [pinned upstream configuration](https://github.com/srnyx/limited-lives/blob/4.2.2/src/main/resources/config.yml)
for feature filters, grace-period exceptions and complete recipe options.

#### Minecraft backups and recovery

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

### Remote SSH over Hysteria2

The opt-in `hosts/nixos-server/modules/system/hysteria.nix` service transports
SSH over Hysteria2 with Salamander obfuscation. It is disabled until provisioned;
UDP 443 opens only when `systemd.services.hysteria.enable` is true. Existing
OpenSSH/YubiKey authentication and LAN access remain unchanged.

Templates follow the official [server configuration](https://v2.hysteria.network/docs/advanced/Full-Server-Config/),
[TCP forwarding](https://v2.hysteria.network/docs/advanced/Full-Client-Config/#tcp-forwarding),
and [ACL](https://v2.hysteria.network/docs/advanced/ACL/) documentation:

- Server: `hosts/nixos-server/dotfiles/hysteria/server.example.yaml`, installed
  as `/etc/hysteria/server.example.yaml`.
- Client: `common/dotfiles/hysteria/client.example.yaml`, installed on `ne` and
  `nix` as `~/.config/hysteria/client.example.yaml`, alongside the `hysteria` CLI.

Guided provisioning uses `hysteria-setup.nix` and `scripts/hysteria-setup.sh`.
On **nixos-server**, through its console or an existing trusted connection:

```sh
cd /etc/nixos
git pull --ff-only
sudo nix run path:/etc/nixos#hysteria-setup -- server
```

The command detects public IPv4 through `https://ifconfig.me/ip` with a
10-second curl timeout. Press Enter to accept it or enter a different IP/domain;
VPN/proxy egress may differ from the reachable inbound address. Failed detection
falls back to manual entry. The command asks before generating independent
passwords and a one-year ECDSA certificate, populates the private
server configuration, and enables the checkout's Hysteria module. It asks
separately before `nixos-rebuild switch`; declining leaves activation pending.
It refuses existing credentials instead of overwriting or rotating them.
Keep the local enablement edit when updating Git; commit it deliberately.

The server's configuration and TLS key stay root-only under `/etc/hysteria`.
The systemd unit loads them as credentials for an unprivileged dynamic user.
`/var/lib/hysteria-bootstrap/client.json` is mode `0600`, owned by `ri`, and
contains the public endpoint, certificate and tunnel passwords, **not** the
TLS private key or SSH key. Treat it as a secret; retain it outside the repo
for additional clients, or remove it after enrolling all clients.

On **each client** (`ne` or `nix`), connect the YubiKey and provision its existing
`~/.ssh/nixos-server` handle file first. Then:

```sh
cd /etc/nixos
git pull --ff-only
nix run path:/etc/nixos#hysteria-setup -- client
```

Enter the server's LAN address (`nixos-server.local` by default). The command
fetches the bootstrap file over SSH as `ri`, retaining host-key verification
and YubiKey authentication. It writes private client configuration and the
trusted certificate under `~/.config/hysteria` with restrictive permissions.
No client system activation is needed, and existing files are never replaced.
Verify the SSH host fingerprint at first connection; never bypass a mismatch.

If behind a router, manually forward UDP 443 to the server's reserved LAN
address. Do not forward TCP 22 for this transport. Test from a phone hotspot:

```sh
# Leave running in one terminal:
nix run path:/etc/nixos#hysteria-setup -- connect

# In another terminal:
ssh -o IdentitiesOnly=yes -o HostKeyAlias=nixos-server.local \
  -i ~/.ssh/nixos-server -p 2222 ri@127.0.0.1
```

With the shared Home Manager configuration activated, the shorter equivalent
is `ssh nixos-server-remote`; the installed `hysteria` CLI can also run the
client directly. A running server service is not proof of remote reachability.

Renew the certificate before its 365-day expiry; replacing it requires updating
each client's trust file and the bootstrap certificate. Update the private
client configuration and bootstrap endpoint if the public address changes.
Restart the server after changing systemd-loaded credentials. Setup is initial
provisioning, not renewal or recovery: after a partial failure, inspect retained
files rather than deleting working credentials to make the command run again.
If activation failed or was declined, retry only the displayed rebuild command.
The non-destructive regression check is `bash scripts/hysteria-setup-test.sh`
with the packaged command's GNU coreutils and jq available.

The local forward binds only `127.0.0.1:2222`. The server ACL permits only its
own `127.0.0.1:22` and rejects other destinations. The remote SSH alias shares
the LAN alias's host-key identity; verify the server fingerprint on first use,
never bypass a mismatch. Keep the YubiKey connected to the client.

Salamander obscures QUIC rather than presenting a normal HTTP/3 website; it
cannot bypass a blanket UDP block. There is no full-device VPN or client
autostart. Router changes remain manual; activation requires explicit approval.
Test from the actual remote network before relying on it for access.

## Shared shell and editor

All three hosts import `common/modules/shell.nix` through Home Manager for their
primary user. It owns portable CLI packages, Fish abbreviations and
aliases, Starship, zoxide, direnv, Matugen, Departure Mono Nerd Font, and shared
Starship/fastfetch/btop/micro configuration. Optional local Fish additions belong
in `~/.config/fish/user-config.fish`. Host modules own platform-specific shell
initialization and terminal integration.

Linux OMP comes from `github:rikkichy/oh-my-pi-flake`. Its hourly GitHub workflow
commits the latest stable release after builds and smoke checks on both Linux
architectures. `flake.lock` selects the installed release; `nix flake update omp`
refreshes that pin. The desktop's daily upgrade includes OMP and takes effect
after reboot. macOS uses the `can1357/tap/omp` Homebrew formula.

The server's `hosts/nixos-server/home.nix` imports only the shared shell module.
Fish is `ri`'s system login shell; reconnect SSH after activation to start it.
Conflicting managed files are preserved with `.before-home-manager`; existing
backups are not overwritten.

Only the desktop and Mac import `common/modules/zed.nix`, which owns Zed's read-only
settings, extension selection, language-server commands, and the captured theme.
On Linux it also owns the Zed package; on Darwin it configures the existing app.
Edit this module rather than Zed's settings UI. Extensions are installed by Zed
on startup, not version-pinned by Nix. Before the first Linux activation, back up
any unmanaged `~/.config/zed/settings.json` or conflicting Matugen theme file.
Restart Zed after activation so language servers use the new generation.

Project environments still come from direnv. Zed's Node runtime and the fallback
Go runtime are editor-scoped, not global project toolchains. Darwin Rust keeps
using rustup; install `rust-src` and `rustfmt` for each project toolchain that
needs standard-library navigation and formatting. Linux supplies default Rust
tools and sources; project development shells can override them.
QML language-server support is Linux-only, with Qt and Quickshell import
metadata passed explicitly; Darwin retains QML syntax support.

JetBrains Kotlin LSP pre-release builds expire. If its log reports an expired
build, update `hosts/nix/pkgs/kotlin-lsp.nix` from the upstream release and checksum and
upgrade only the Darwin cask with `brew upgrade --cask kotlin-lsp`.
Darwin activation deliberately does not upgrade Homebrew packages.

## Spotify and wallpaper colors

The desktop and Mac import `common/modules/spotify.nix`. The pinned
`spicetify-nix` input patches Spotify at build time; do not install a second
unmodified Spotify package. The Wallpaper theme replaces color variables only:
no custom theme CSS or JavaScript, extensions, custom apps, assets, fonts or layout
changes. Native RTL rules are retained. `common/pkgs/spicetify-bootstrap.patch`
keeps the rewritten JavaScript modules loaded even with every add-on disabled;
their class names must match Spicetify's rewritten stylesheets.

Both hosts render `common/dotfiles/matugen/templates/spotify-palette.css` into
writable `~/.config/spicetify/colors.css`. Spotify's normal XPUI stylesheet points
to that file: the Linux package contains the link; Darwin links the deployed
resource after Home Manager copies the app. An absent palette is seeded with
Spotify's default colors, without overwriting existing wallpaper colors.

Run `wpp`/`awpp` on Linux or `wallpaper-theme` on macOS, then fully restart Spotify
to load the palette. There is no stylesheet watcher, local web server, or remote
debugging endpoint. Spotify/Spicetify updates follow the Nix input pins; client
compatibility still requires keeping those pins current. See the
[Mac guide](docs/ne.md#spotify-and-spicetify) for update-cache protection and recovery.

## Layout

Ownership comes first: `common/` contains configuration and packages shared by
multiple hosts; `hosts/{nix,nixos-server,ne}/` contain their own entry points,
modules, packages and dotfiles. Create subdirectories only for real content.
Within each host's `modules/`, `system/` contains NixOS or nix-darwin modules
and `home/` contains Home Manager modules.
Secrets remain separate in `.secrets/`.

| Path | What |
|---|---|
| `flake.nix` | inputs + NixOS and Darwin host outputs |
| `install.nix`, `scripts/install.sh` | interactive UEFI installer and its packaged runtime dependencies |
| `hosts/nixos-server/` | headless server policy and installer-replaced hardware configuration |
| `common/modules/nixos-yubikey.nix` | Linux-only shared cryptroot FIDO2 and sudo U2F policy |
| `common/modules/nixos-limine.nix` | shared Linux UEFI Limine policy; menu timeouts remain host-owned |
| `common/modules/nh.nix` | system-wide nh package and default checkout for all three hosts |
| `common/modules/nixos-networking.nix` | shared Linux NetworkManager and Avahi policy |
| `common/modules/nixos-mihomo-secrets.nix` | desktop SOPS/legacy inputs and private runtime rendering |
| `common/pkgs/overlay.nix` | shared Linux OMP release-binary package and VPN command package |
| `common/pkgs/mihomo-config.py`, `common/dotfiles/mihomo.yaml` | desktop private-config renderer and public tunnel template |
| `hosts/nixos-server/modules/system/services.nix` | headless tooling, PIV permissions, Docker and timezone |
| `hosts/ne/default.nix` | macOS host identity, primary-user wiring and system module imports |
| `hosts/ne/home.nix` | Home Manager imports and state version |
| `hosts/ne/modules/system/` | Homebrew inventory, Nix policy, macOS preferences and power settings |
| `hosts/ne/modules/home/` | shell environment, Ghostty, Matugen, Marta, keyboard and file associations |
| `hosts/ne/pkgs/zed-file-associations.nix` | native macOS file-association helper |
| `hosts/nix/default.nix` | desktop identity, user and explicit system module imports |
| `hosts/nix/hardware.nix` | detected hardware, root LUKS device and root/boot filesystems |
| `hosts/nix/boot.nix` | bootloader, initrd/LUKS additions, kernel and crash resilience |
| `hosts/nix/hardware-policy.nix` | CPU policy, NVIDIA, peripheral access and Bluetooth |
| `hosts/nix/lighting.nix` | headless RGB shutdown, device exclusions and process isolation |
| `hosts/nix/storage.nix` | data mounts, permissions, XFS scrubbing and trim |
| `hosts/nix/modules/system/locale.nix` | desktop locale and timezone |
| `hosts/nix/modules/system/nix.nix` | Nix settings and garbage collection |
| `hosts/nix/modules/system/security.nix` | polkit, shared authentication import, allocator policy and smart cards |
| `hosts/nix/modules/system/networking.nix` | shared network import and desktop-only interface-scoped LAN ports |
| `hosts/nix/modules/system/audio.nix` | PipeWire and the Blessing 3 equalizer |
| `hosts/nix/modules/system/session.nix` | Hyprland/UWSM, greetd, portals, keyring, session environment and fonts |
| `hosts/nix/modules/system/gaming.nix` | Steam, Gamescope, GameMode, game packages, osu! MIME and scheduling |
| `hosts/nix/modules/system/applications.nix` | desktop package inventory, application integration, Docker and printing |
| `hosts/nix/modules/system/flatpak.nix` | Flatpak service and bootstrap/update units |
| `hosts/nix/modules/system/maintenance.nix` | checkout helpers, automated updates and desktop notifications |
| `hosts/nix/pkgs/overlay.nix` | desktop package wiring and upstream patches |
| `common/pkgs/vpn.nix` | shared Linux VPN command package |
| `hosts/nix/home.nix` | Home Manager imports, state version and desktop packages |
| `hosts/nix/modules/home/matugen.nix` | generated palettes, cursors, wallpaper entries/pickers and restoration |
| `hosts/nix/modules/home/fuzzel.nix` | Fuzzel settings, general desktop entries/actions and shared pickers |
| `hosts/nix/modules/home/network-reset.nix` | network recovery backend, desktop entry and terminal launcher |
| `hosts/nix/modules/home/quickshell.nix` | Quickshell service, QML deployment and live Hyprland symlink |
| `hosts/nix/dotfiles/ricing/quickshell/` | Material 3 Expressive rail, controls, notifications and calendar |
| `hosts/nix/modules/home/applications.nix` | application settings, MIME defaults, GTK/Qt and Telegram proxy |
| `common/modules/shell.nix` | portable Fish, direnv and CLI dotfiles |
| `common/modules/zed.nix` | shared Zed settings, extensions, language servers and theme |
| `common/modules/discord.nix`, `common/dotfiles/discord/` | shared Equicord plugin settings and static theme; each host's Matugen module writes QuickCSS |
| `common/modules/spotify.nix`, `common/dotfiles/matugen/templates/spotify-palette.css` | shared Spicetify packaging and writable color-only palette |
| `hosts/nix/modules/home/foot.nix` | Foot and terminal palette integration |
| `hosts/nix/dotfiles/ricing/hypr/` | Hyprland Lua config, symlinked live into `~/.config/hypr` |
| `common/dotfiles/`, `hosts/nix/dotfiles/`, `hosts/ne/dotfiles/` | shared and host-owned assets/templates |
| `hosts/nix/dotfiles/ricing/`, `hosts/nix/dotfiles/gaming/`, `hosts/nix/dotfiles/bypasses/` | desktop appearance, game settings and proxy configuration |
| `.secrets/.sops.yaml`, `.secrets/{nix,nixos-server}/` | public recipient policy and host-isolated secret declarations/ciphertext |

Host composition uses explicit imports. `nix` is the NixOS desktop,
`nixos-server` the headless Linux server, and `ne` the Apple Silicon Darwin
host; new hosts require their own real settings.
A new host keeps its boot, disks, networking, users and workloads in
`hosts/<name>/`, alongside its `modules/`, `pkgs/` and `dotfiles/`. Move a module
into `common/modules/` only when multiple hosts actually use it. The Mac uses nix-darwin and
Home Manager's Darwin integration; Linux system modules are not portable to it.

Portable shell settings and their CLI packages are owned together by
`common/modules/`, shared by both hosts. Linux themes, Foot
and systemd user services are confined to `hosts/nix/modules/home/`.
Keep architecture, checkout path, username, state versions and secrets explicit
per host. Do not reuse this desktop's hardware file, PAM enrollment, secret
recipients or Linux package overlay on another host by default.

`vhelper` and `openwave` are separate flake inputs and live in their own
repos (`rikkichy/vhelper`, `rikkichy/openwave`) — edit them there, not here.

## Validation and safety

Run commands from `/etc/nixos`. Use explicit `path:` flake references while
iterating so newly added files are visible; plain Git flake references omit
untracked files. The repository is public: keep plaintext secrets, private keys,
and identity descriptors outside the checkout, including ignored files.

```sh
.omp/skills/nixcfg-validation/scripts/check.sh quick
# Evaluate both hosts, without building or activation:
.omp/skills/nixcfg-validation/scripts/check.sh full
# For changes confined to one host, use full nix or full ne.
# Build on the Mac, without activation:
darwin-rebuild build --flake path:.#ne
```

Full validation evaluates both hosts by default; use a single-host selector only
when shared configuration and flake inputs are unaffected. The Darwin check
evaluates its derivation, not a native build. A `--dry-run` or derivation evaluation
proves neither compilation, activation, live authentication nor boot. Host guides
contain switch commands; activation, secret provisioning, hardware enrollment and
reboot require separate operator approval.

The project skills and command prompts under `.omp/`, together with `AGENTS.md`,
are tracked repository resources. See `AGENTS.md` for skill routing; the
handbook and host guides provide operator documentation.
