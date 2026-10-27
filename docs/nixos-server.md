# nixos-server — headless NixOS

Related: [Installation](install.md) · [Shared configuration](shared.md)

The normal system uses NetworkManager-managed DHCP, console login, and key-only
SSH on port 22. Normal SSH password/keyboard-interactive authentication and root
login are disabled. Unlock encrypted root at the local console before connecting.
No desktop session is enabled.

Recovery: [SSH access and sudo password fallback](#ssh-and-remote-sudo) ·
[Encrypted-root console unlock](#encrypted-root-console-unlock) ·
[Bootloader checkpoints](#bootloader-migration)

Minecraft hosting is not configured: there is no game container, backup timer,
service account or TCP 25565 firewall allowance. Applying this configuration
does not erase existing `/var/lib/minecraft` or `/var/backup/minecraft` data.
Router port forwarding and external DNS records are managed separately.

## SSH and remote sudo

Before installation, ensure that this checkout contains your FIDO2 SSH public key
in `hosts/nixos-server/default.nix`. Local edits on another machine are not
included by cloning GitHub. The shared SSH module on `ne` and `nix` connects
as `ri` to `nixos-server.local`, advertised by the server through mDNS. The SSH
host-key identity stays `nixos-server.local` for both LAN and tunneled access.
After activating the client configuration, connect with:

```sh
ssh nixos-server
```

Securely provision the existing `~/.ssh/nixos-server` FIDO2 credential-handle
file on each client outside the checkout and Nix store. Home Manager activation
sets `~/.ssh` to mode `0700` and the handle file to `0600` when they exist.
It does not create or copy keys. Provision files with these permissions if
copying them after activation. The same YubiKey is required on either client.
Only resident credentials can recover their handle files with `ssh-keygen -K`.
Non-resident credentials require the original handle file.

If the server's LAN address changes, find it with `ip -br address` at its
console. Use `ssh -o HostName=SERVER_IP nixos-server`. Before client
activation, use `ssh -o IdentitiesOnly=yes -i ~/.ssh/nixos-server ri@SERVER_IP`.
Back up an unmanaged client `~/.ssh/config` before Home Manager takes ownership.

Verify the server host-key fingerprint through the console before accepting it.
The SSH YubiKey stays connected to the client and requires touch. The server
does not request FIDO2 user verification. An authenticator's AlwaysUV policy
or a local key-file passphrase can still require an additional prompt.
SSH does not forward the USB token. Boot unlock uses a server-side token
or the disk passphrase at the local console. Ordinary SSH is available only after boot.

For remote sudo, `nixos-server` enables `pam_rssh` for `sudo` and `sudo-i`.
It requests signatures through a forwarded SSH agent and trusts only the
root-controlled `/etc/ssh/authorized_keys.d/<user>` key inventory. The same
FIDO SSH key authorizes login and remote sudo. Removing it from the server's
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
client (`nix` or `ne`). Rebuilding the server does not update client settings.
Before client activation, pass `-A` explicitly. Use `-a` to disable forwarding
for an individual connection. Use a dedicated
agent containing only the server key where practical. A compromised server
can request signatures from a forwarded agent. Touch does not identify the
requesting operation. Do not approve unexpected touches.

Activate server policy only with separate operator approval, using
`nh os switch`. Retain a working root recovery shell.
Reconnect with forwarding and check `ssh-add -l`
on the server: it must list the expected `ED25519-SK` identity.
The local command uses `NH_FLAKE=/etc/nixos`. For an explicit checkout/host,
use `nh os switch path:/etc/nixos --hostname nixos-server`.
Invalidate sudo timestamps before each test: `sudo -k; sudo -v` and,
separately, `sudo -k; sudo -i`. Verify client key/touch success.
Verify that cancellation or no-touch does not grant unintended authorization.
Verify correct password fallback with an absent agent/key, and rejection with an unauthorized key and wrong password.
Exit each test root shell without closing the recovery shell. Retain recovery
until both sudo services pass. Cached sudo authorization is not proof of touch.
Evaluation and isolated PAM checks are not hardware-authentication proof.

## Encrypted-root console unlock

Unlock encrypted root at the local console with the server-side FIDO2 token
or the existing LUKS recovery passphrase. Remote preboot unlock is not available.
Ordinary SSH and the Hysteria tunnel become available only after boot.

Keep console or KVM access, a working generation, the disk passphrase and a
tested recovery ISO. Before an approved reboot, inspect the selected boot entry,
crypttab and built initrd for the root mapping and FIDO2/USB/HID support.
A successful build does not prove that the system can boot or unlock root.

With separate operator approval, check cold boot with the local token and
console passphrase recovery without a token. Check no-touch and wrong-token
fallback while retaining recovery access. Do not remove recovery passphrase slots.

## Bootloader migration

On an existing server, migration is a bootloader update, not a reinstall.
For an approved migration, use `nh os boot path:/etc/nixos --hostname nixos-server
--install-bootloader`. Before separately approving reboot, inspect
`/boot/limine/limine.conf` and the Limine firmware entry. Retain the existing
systemd-boot EFI files, working generation, disk passphrase and recovery USB
until Limine has successfully booted and unlocked the installed system.

## Server services and private provisioning

`hosts/nixos-server/modules/system/services.nix` supplies YubiKey Manager,
`age-plugin-yubikey`, PC/SC, Docker with weekly native pruning, and the Moscow
timezone. `ri` can manage Docker and NetworkManager. Docker membership is
root-equivalent. Pruning may remove stopped containers and unused resources,
but does not opt into volume pruning. PC/SC access is granted only to `ri` for
context/card operations. SSH authentication does not forward a client YubiKey.

Both Linux hosts share NetworkManager and Avahi. Mihomo/TUN, the `vpn` command
and VPN secret provisioning belong only to the desktop host `nix`.
The server does not import desktop gaming/LAN firewall ports. The first approved
network migration belongs at the console/KVM. It replaces dhcpcd ownership and
disables IPv6, so an existing SSH connection can drop. Verify addressing, DNS
and SSH before leaving that console. No network activation is automatic here.

`nixos-server` has no Mihomo service, configuration renderer or SOPS import.
It needs no `/etc/mihomo` inputs or VPN age identity.

OMP is installed and updated through the [shared Bun launcher](shared.md#shared-shell-and-editor), not the system package cache.

## Obsidian Headless

`hosts/nixos-server/modules/system/services.nix` installs the pinned Nixpkgs
`obsidian-headless` package and permits its unfree license specifically.
The [upstream `ob` CLI](https://github.com/obsidianmd/obsidian-headless) syncs
and publishes vaults without the desktop app; it is not a web notes editor.
Run it as `ri`, not root. Account credentials and vault contents remain
application-owned and must stay outside this checkout and the Nix store.

`obsidian-sync.service` runs `ob sync --continuous` as `ri`, using
`/home/ri/vaults/Obsidian` and the account credentials under `/home/ri`.
It starts at boot without an SSH login and restarts after exit with a 10-second
delay. Changes are watched continuously, not on a timer; network availability
and Obsidian Sync determine propagation latency.

Stop any manually running continuous sync before approved activation so only
one process owns the vault. If the vault is not yet configured, perform initial
setup after activation with the service stopped:

```sh
sudo systemctl stop obsidian-sync
ob login
ob sync-list-remote
ob sync-setup --vault "Obsidian" --path ~/vaults/Obsidian --device-name nixos-server
sudo systemctl start obsidian-sync
```

Enter account and vault encryption passwords at the interactive prompts,
not in command arguments. Check synchronization with
`journalctl -u obsidian-sync -f`. For account or vault changes, stop the service
first and start it again after setup. Authentication failures require operator
attention; automatic restarts do not replace login.
The CLI and credentials remain on the host. Only the vault's `OpenBot` and
`Studies` subfolders are shared with the container, as described below.

## OpenBot agent server

`hosts/nixos-server/modules/system/openbot.nix` runs the
[upstream headless container](https://github.com/nightly-labs/openbot/blob/main/docs/docker.md)
as `docker-openbot.service`. The image is pinned by version and digest; the
Electron seccomp profile is fetched as a single file pinned by upstream commit
and SHA-256, so server evaluation does not need the full OpenBot source flake.
Systemd starts it at boot and restarts it after exit. No desktop login is needed.
Encrypted root still requires console unlock after a reboot.

The container includes its virtual displays and keyring. Electron's sandbox
stays enabled through the upstream seccomp profile and `no-new-privileges`.
Chromium gets 1 GiB of shared memory, and Docker allows 60 seconds for graceful
shutdown. Host networking shares the server's network namespace, routes and
loopback instead of Docker bridge/NAT. No port mappings or firewall allowances
are added. Remote clients use OpenBot's account, Signal and TURN services through
outbound connections; the container does not serve a browser UI on the server's
LAN address.

After pulling the configuration, activate on the server with separate approval:

```sh
nh os switch path:/etc/nixos --hostname nixos-server
docker exec -it openbot openbot login --name nixos-server
docker exec openbot openbot status
```

Use the same account in the desktop app or at <https://openbot.run/app>, select
`nixos-server`, and connect providers there. Desktop provider credentials are
not copied to the server. Queue work or configure routines for recurring tasks.
Provider quotas and expired authentication can still interrupt agents.

Manage lifecycle through systemd, not `docker restart`, because NixOS owns the
container. Logs are available with `journalctl -u docker-openbot -f`.
For phone pairing, run `docker exec -it openbot openbot mobile-connect`.

### Obsidian notes access

Only these host vault directories are mounted into OpenBot, both read/write:

| Host directory | Container path |
|---|---|
| `/home/ri/vaults/Obsidian/OpenBot` | `/data/OpenBot/Shared/Obsidian/OpenBot` |
| `/home/ri/vaults/Obsidian/Studies` | `/data/OpenBot/Shared/Obsidian/Studies` |

Point agents at the container paths. Systemd tmpfiles creates the host directories
and their two vault parents with mode `0700`, owned by `ri`; the container's
UID 1000 matches `ri` for write access. Each bind mount refuses to start if its
source is missing.

The rest of the host vault, its `.obsidian` settings and the host's Obsidian
credentials are not mounted. This limits access to host vault files, not to the
container's own persistent `/data` or its network access. Changes in the shared
folders are immediately visible on the host; `obsidian-sync.service` continuously
synchronizes the host vault with Obsidian Sync. Existing vaults at other paths
are not moved.
The shared notes are outside the `openbot-data` volume and need their own backup.

### Declarative humanizer skills

`hosts/nixos-server/dotfiles/openbot/skills/` owns the compact English
`humanizer-en` and Russian `humanizer-ru` skills and their upstream MIT licenses.
The OpenBot module mounts each skill directory read-only from the Nix store into
both `/data/.agents/skills/<name>` and `/data/.claude/skills/<name>`.
Only these two names are mounted, leaving other skills and provider settings
writable. No Downloads directory, installer, credentials, or package download
is involved at container startup.

These are native provider-global skills, not OpenBot local-library entries:
OpenBot does not list home-directory skills in its Skills UI. Codex, Grok and
OpenCode support the global `.agents` directory; Claude Code uses `.claude`.
A provider with a separate account configuration directory or without global
skill discovery needs its own workspace installation instead. The mounts do
not modify OpenBot's library database or copy files into agent workspaces.

After approved activation, start a fresh agent session and ask it to use
`humanizer-en` or `humanizer-ru` for the supplied text. Edit the tracked sources
and rebuild to update them; agent-side edits to these mounted skills are denied.
The source path changes with their contents, so activation recreates the
container with the new skill versions. The original Downloads copies are not
the deployment source.

### Persistent data and isolation

The named Docker volume `openbot-data`, mounted at `/data`, survives container
replacement. It contains workspaces, databases, browser state, provider sign-ins,
and the keyring with its password file. Keep this entire recovery unit together.
Before upgrades, stop `docker-openbot.service` and back up the volume securely.
No automatic backup or image updater is configured. Update the image version and
digest deliberately, review the matching upstream seccomp profile, and activate
the revised configuration. Never roll an older image back onto a migrated database.

Agents have full access inside the container. Apart from the scoped Obsidian
folders, no host home is mounted, and the Docker socket is not exposed.
Host networking exposes host-local listeners to agents and lets their processes
bind host ports. It does not isolate agents from the LAN.
No CPU or memory cap is imposed; set limits before sharing the server with
resource-sensitive workloads. Credentials belong in interactive provider setup
or separately provisioned runtime files, never in this repository or the Nix store.

## Public package cache (Attic)

`hosts/nixos-server/modules/system/attic.nix` is **disabled until provisioned**.
Enabling `services.atticd.enable` runs the pinned Nixpkgs Attic module, including
its native sandbox, as a dynamic user on `127.0.0.1:8080`. Nginx exposes
`https://cache.kror.net/` with ACME HTTPS. Only TCP 80/443 open. Hysteria's UDP
443 is independent. The public binary-cache endpoint is
`https://cache.kror.net/nixcfg`. Public means anonymous **downloads**, not uploads:
Attic requires a signed token with push permission for writes.

SQLite, cache signing keys and local NAR storage live under `/var/lib/atticd`
on the existing encrypted persistent root. No impermanence migration is needed.
The JWT private key is separately provisioned at `/etc/attic/server.env`, never
in the checkout or Nix store. Back up both together: SQLite contains the cache's
Nix signing key, which is distinct from the JWT key. Stop Attic before a plain
filesystem copy of its database/storage, or use a consistent snapshot/SQLite
backup. GC runs every 12 hours and removes paths unused for 90 days by default.
This is time-bounded retention, not a disk quota. Monitor free space and adjust
retention before the disk fills.

### Targets and publication boundary

`flake.nix` exports `cacheTargets.x86_64-linux` and the same named `packages`.
The desktop packages and custom wrappers/assets come from the
**desktop's final pkgs**, not a second import with approximate overlays.
Vhelper remains installed on the desktop but is not a cache publication target.
`sops-install-secrets` uses the desktop's exact `config.sops.package`; only the
helper's runtime closure is published, never secret manifests or secret files.
Quickshell, Hyprland, Filen, Fuzzel and the Spicetify CLI use unmodified Nixpkgs packages
and are not custom cache targets. Spotify's theme patches run during app
packaging. Static Bibata Modern Ice assets are fetched from their publisher,
not republished through this cache.

These roots are redistributable according to their pinned package metadata:
desktop packages retain upstream free licenses, the custom packages are
MIT/Apache/GPL/OFL.
The upload includes runtime closures, not build dependencies.
Wrappers/fonts reference ordinary free tools/libraries.
Preserve this boundary when adding roots or updating runtime dependencies.
Attic skips paths already signed by the official `cache.nixos.org-1` key.

No system/Home Manager aggregate closure is published. Proprietary Spotify,
Discord/Equicord, Brave and Kotlin LSP are deliberately excluded.
`allowUnfree` on the desktop is not redistribution permission. VTS OpenDeck's
separate exported package is not a cache target (the desktop uses Flatpak).
If proprietary caching becomes necessary, first establish redistribution rights
or design a separate authenticated private cache. Do not add those roots here.

### Guided setup

`attic-setup.nix` packages `scripts/attic-setup.sh` and its tools. Run the server
mode through the server console or an existing trusted SSH connection:

```sh
cd /etc/nixos
git pull --ff-only
sudo nix run path:/etc/nixos#attic-setup -- server
```

Before approving provisioning:

- Point the **DNS-only A record** `cache.kror.net` at this server's public IPv4.
- Allow/forward inbound **TCP 80 and 443**. CGNAT requires a reachable ingress
  arrangement. Buying a domain does not provide one.
- Do not publish AAAA unless IPv6 is reachable. The shared server configuration
  disables IPv6. Keep LAN SSH and console recovery available.

The helper asks before provisioning credentials/enabling the checkout module.
It also asks before activation, public-cache setup, and generating the scoped
GitHub upload token. An already active Attic/Nginx deployment is validated without
another rebuild. Declining an initial activation leaves a command to run later.
Rerun the helper afterward to finish cache setup. Enabling the server accepts ACME
terms. Set `security.acme.defaults.email` separately if a contact is wanted.
Inspect failures with `journalctl -u atticd -u nginx`.

Existing JWT credentials and cache signing identity are preserved. A changed
saved public key, unsafe permissions/path, private cache, or incompatible
endpoint stops setup instead of silently replacing trust. A pending upload token
is retained until credential transfer succeeds. Private keys/tokens never enter the checkout,
Nix store, command arguments or printed output. The **public** cache key is
safe to display. Private temporary files are removed when the helper exits.

The root-owned `/var/lib/attic-bootstrap` directory contains the public
`nixcfg.pub` and a mode-0600 `ci-token` owned by `ri`. These let desktop setup
retrieve the independently recorded public key and let GitHub setup transfer the
upload token without remote sudo. The JWT key remains root-only in `/etc/attic`.

On desktop **nix**, update the checkout, connect the SSH YubiKey and run:

```sh
cd /etc/nixos
git pull --ff-only
nix run path:/etc/nixos#attic-setup -- github
```

Wait for successful cache publication before approving desktop activation:

```sh
nix run path:/etc/nixos#attic-setup -- client
```

Both modes ask for the server's LAN IP/DNS name (`nixos-server.local` by
default). Provision the existing `~/.ssh/nixos-server` FIDO handle first.
Verify the server host fingerprint through its console before accepting a new
SSH identity. SSH agent forwarding is disabled for these transfers. The helper
retrieves the saved public key over SSH and compares it to the HTTPS cache
identity before installing trust or publishing credentials.
Remote checks and token cleanup explicitly run through `sh`, independent of the
server account's login shell (including Fish); interactive cleanup retains its TTY
for sudo.

`client` asks before writing root-owned `/etc/nix/attic.conf` and separately
before desktop activation/daemon restart. An identical existing file is reused.
A different file or symlink is refused rather than overwritten. Missing include
means that the existing substituters remain in use until activation. This file contains only
`extra-substituters` and `extra-trusted-public-keys`: no JWT or private key.
Official caches/signature checking remain enabled. No trusted user is added.
Server/Darwin trust is unchanged.

For the first activation, the helper builds with the verified cache URL/key as
root-only Nix invocation options, then activates that exact snapshot through
`nh`. This permits downloads before the optional include is active, without
rewriting immutable `nix.conf` or granting a trusted user. Uncached outputs can
still build locally. Publish matching committed inputs first.

`github` requires an authenticated `gh` session and asks before setting
`ATTIC_PUBLIC_KEY` and the scoped `ATTIC_TOKEN` on `rikkichy/nixcfg`. The token
travels through protected files/stdin, never a pasted secret or command argument.
It asks separately before removing the server's staged token and before starting
publication of all targets. Failed credential transfer or cancellation retains the
staged token for retry. Renew the 90-day token by rerunning server mode after
consuming the staged token, then rerunning GitHub mode. It can pull/push only
`nixcfg`, not create/configure/destroy caches or delete paths. Expiration bounds
access. Rotating the JWT key revokes **all** tokens and is not a renewal step.
Approved remote token cleanup uses a terminal and `sudo` to remove the file from
its root-owned directory. With agent forwarding disabled, remote sudo may
require the server account's password fallback.

### CI use and download verification

`.github/workflows/package-cache.yml` publishes on relevant pushes to `main`
and manual dispatch. It builds each selected target separately (two concurrent
runners), keeps GC roots until upload, and uploads its runtime closure with Attic.
CI uses the independently provisioned `ATTIC_PUBLIC_KEY`, never a newly discovered
remote key or disabled signatures. The preflight checks that the upload secret
exists. Build steps receive no token. The upload step reads it from a private
file and removes that file on exit. Actions are pinned to commit revisions.

CI builds the **committed** `flake.lock` and rejects implicit lock updates.
Local uncommitted input updates do not match published derivations until deliberately committed.
Wait for publication before expecting matching downloads. Evaluation alone is not a populated cache.

```bash
gh workflow run package-cache.yml --repo rikkichy/nixcfg -f target=quickshell
gh run list --repo rikkichy/nixcfg --workflow package-cache.yml
# After provisioning/publication, use the desktop's authenticated trust settings:
nix build --no-link --max-jobs 0 'path:/etc/nixos#quickshell'
```

Manual `target=all` publishes every explicit target. An unknown target fails
selection. `--max-jobs 0` refuses local source compilation, but an already present
store path is not download proof.
For real acceptance, copy the published output to a fresh temporary local store with `nix copy --from https://cache.kror.net/nixcfg
--to "local?root=$temporary_store" --option extra-trusted-public-keys "$key"
"$published_store_path"`.
Obtain the exact path with `nix eval --raw 'path:/etc/nixos#quickshell.outPath'` at the same committed lock.
Use an input-addressed output for signature-enforcement checks.
Content-addressed paths can be accepted independently of a trusted signature. Verify that a narinfo
carries the recorded `nixcfg` signature. Verify that an anonymous download succeeds and a
valid anonymous `PUT /_api/v1/upload-path` is refused. A malformed request's
HTTP 400 is not authentication proof. Upload metadata belongs in the
`X-Attic-Nar-Info` header. Never discard real store paths or disable signature
checks merely to force a smoke test.

## Remote SSH over Hysteria2

The opt-in `hosts/nixos-server/modules/system/hysteria.nix` service transports
SSH over Hysteria2 with Salamander obfuscation. It is disabled until provisioned.
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
10-second curl timeout. Press Enter to accept it or enter a different IP/domain.
VPN/proxy egress may differ from the reachable inbound address. Failed detection
falls back to manual entry. The command asks before generating independent
passwords and a one-year ECDSA certificate. It populates the private
server configuration and enables the checkout's Hysteria module. It asks
separately before `nixos-rebuild switch`. Declining leaves activation pending.
It refuses existing credentials instead of overwriting or rotating them.
Keep the local enablement edit when updating Git. Commit it deliberately.

The server's configuration and TLS key stay root-only under `/etc/hysteria`.
The systemd unit loads them as credentials for an unprivileged dynamic user.
`/var/lib/hysteria-bootstrap/client.json` is mode `0600`, owned by `ri`, and
contains the public endpoint, certificate and tunnel passwords, **not** the
TLS private key or SSH key. Treat it as a secret. Retain it outside the repo
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
Verify the SSH host fingerprint at first connection. Never bypass a mismatch.

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
is `ssh nixos-server-remote`. The installed `hysteria` CLI can also run the
client directly. A running server service is not proof of remote reachability.

Renew the certificate before its 365-day expiry. Replacing it requires updating
each client's trust file and the bootstrap certificate. Update the private
client configuration and bootstrap endpoint if the public address changes.
Restart the server after changing systemd-loaded credentials. Setup is initial
provisioning, not renewal or recovery. After a partial failure, inspect retained
files rather than deleting working credentials to make the command run again.
If activation failed or was declined, retry only the displayed rebuild command.

The local forward binds only `127.0.0.1:2222`. The server ACL permits only its
own `127.0.0.1:22` and rejects other destinations. The remote SSH alias shares
the LAN alias's host-key identity. Verify the server fingerprint on first use.
Never bypass a mismatch. Keep the YubiKey connected to the client.

Salamander obscures QUIC rather than presenting a normal HTTP/3 website. It
cannot bypass a blanket UDP block. There is no full-device VPN or client
autostart. Router changes remain manual. Activation requires explicit approval.
Test from the actual remote network before relying on it for access.
