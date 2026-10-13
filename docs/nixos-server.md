# nixos-server — headless NixOS

Related: [Installation](install.md) · [Shared configuration](shared.md) · [Minecraft](minecraft.md)

The normal system uses NetworkManager-managed DHCP, console login, and key-only
SSH on port 22. Normal SSH password/keyboard-interactive authentication and root
login are disabled. The initrd has a separate unlock-only SSH endpoint on port
2222. No desktop session is enabled.

Recovery: [SSH access and sudo password fallback](#ssh-and-remote-sudo) ·
[Encrypted-root SSH unlock](#encrypted-root-ssh-unlock) ·
[Bootloader checkpoints](#bootloader-migration) ·
[Minecraft restoration](minecraft.md#minecraft-backups-and-recovery)

## SSH and remote sudo

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
SSH does not forward the USB token. Local boot unlock uses a server-side token
or the disk passphrase; [initrd SSH](#encrypted-root-ssh-unlock) accepts the disk
passphrase remotely after authenticating the client's SSH key.

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
`nh os switch`, while retaining
a working root recovery shell. Reconnect with forwarding and check `ssh-add -l`
on the server: it must list the expected `ED25519-SK` identity.
The local command uses `NH_FLAKE=/etc/nixos`; for an explicit checkout/host,
use `nh os switch path:/etc/nixos --hostname nixos-server`.
Invalidate sudo timestamps before each test: `sudo -k; sudo -v` and,
separately, `sudo -k; sudo -i`. Verify client key/touch success, cancellation
or no-touch without unintended authorization, absent agent/key with correct
password fallback, and rejection with an unauthorized key and wrong password.
Exit each test root shell without closing the recovery shell. Retain recovery
until both sudo services pass. Cached sudo authorization is not proof of touch;
evaluation and isolated PAM checks are not hardware-authentication proof.

## Encrypted-root SSH unlock

The module import is commented out in `hosts/nixos-server/default.nix`; remote
initrd SSH unlock is disabled. Provision the dedicated host key before enabling
the import. The following describes the opt-in configuration.

`modules/system/initrd-ssh.nix` enables native systemd initrd networking and
OpenSSH on **IPv4 TCP 2222**, only until normal boot takes over. It reuses `ri`'s
declarative SSH public keys to authenticate **root in the initrd**, then forces
`systemd-tty-ask-password-agent --query`. This is an unlock prompt, not a root
shell: supplied commands, agent/TCP/X11 forwarding, tunnels and user RC scripts
are not available. Normal root SSH remains disabled on port 22.
Authorized-key changes must also reach the installed boot images; retained older
generations keep their initrd authorization until separately retired.

The two credentials have different jobs: touch the client-side FIDO key to
authenticate SSH, then enter the existing **LUKS recovery passphrase** over the
encrypted connection. The client's token does not become a server-local LUKS
token. Local FIDO unlock and console passphrase recovery remain available.

### Provisioning and trust

The guided installer asks before generating a dedicated host key at
`/etc/secrets/initrd/ssh_host_ed25519_key` in the target and prints its public
fingerprint. Declining cancels before erasure. It never reuses normal SSH host
keys or places the private key in the checkout. Limine appends it at bootloader
installation time, outside the Nix store.

**The private initrd host key is present on unencrypted `/boot`.** Anyone who
can read that partition can obtain it and impersonate the unlock endpoint.
Untrusted physical access/boot tampering is not addressed by this feature.
Use a trusted LAN or independently available router VPN, retain console access,
and do not expose this endpoint directly to the Internet. The normal-system
firewall and Hysteria tunnel do not protect or provide access to the initrd.

On an **existing server**, separately approve provisioning and keep a recovery
shell. Generate only if both key files are absent; preserve an existing key:

```sh
sudo -i
install -d -m 0700 /etc/secrets /etc/secrets/initrd
key=/etc/secrets/initrd/ssh_host_ed25519_key
if [ ! -e "$key" ] && [ ! -L "$key" ] && [ ! -e "$key.pub" ] && [ ! -L "$key.pub" ]; then
  ssh-keygen -q -t ed25519 -N '' -f "$key"
fi
ssh-keygen -lf "$key.pub"
exit
```

Check the actual wired NIC driver (`ethtool -i INTERFACE` or `lspci -k`) against
the module's `boot.initrd.availableKernelModules`; add missing drivers and check
required firmware before reboot. The hardware generator does not supply all
initrd NIC drivers. The module includes common Intel, Realtek, USB Ethernet and
virtio drivers, not every NIC.

After separate boot-configuration approval, use
`nh os boot path:/etc/nixos --hostname nixos-server`. A pre-switch check rejects
a missing/empty host key. Inspect the selected Limine entry, appended secrets
image, crypttab and built initrd; a successful build is not boot proof. Keep a
working generation, console and disk passphrase until acceptance succeeds.

### Connect and unlock

The initrd requests DHCP on wired Ethernet; it has no Avahi/mDNS, Wi-Fi setup,
Hysteria or host-side VPN. Reserve/verify a reachable DHCP address through the
router or console; the initrd lease can differ from the normal-system lease.
Networking is not required for local boot/unlock.

With the shared client configuration activated and the SSH credential handle
provisioned, connect from `nix` or `ne`:

```sh
ssh -o HostName=SERVER_IP nixos-server-unlock
```

Without the client alias:

```sh
ssh -tt -p 2222 -o IdentitiesOnly=yes -o ForwardAgent=no \
  -o ClearAllForwardings=yes -o HostKeyAlias=nixos-server-initrd \
  -i ~/.ssh/nixos-server root@SERVER_IP
```

Verify the presented fingerprint against the recorded **initrd** fingerprint
before entering the disk passphrase. The distinct `nixos-server-initrd` trust
identity avoids confusing this key with normal SSH; never bypass a mismatch.
The client key can authenticate directly; agent forwarding is unnecessary.
After successful unlock, boot proceeds and this SSH connection closes. Reconnect
normally with `ssh nixos-server` (or its IP override). If local FIDO already
unlocked root, the initrd endpoint may have disappeared before you connect.

Operator acceptance: from a separate client, prove authorized key/touch plus
correct passphrase unlocks, wrong key is rejected, wrong passphrase leaves root
locked, and arbitrary commands/forwarding are refused. Also test console
passphrase recovery without network and local FIDO boot. Preserve recovery
access throughout.

## Bootloader migration

On an existing server, migration is a bootloader update, not a reinstall.
For an approved migration, use `nh os boot path:/etc/nixos --hostname nixos-server
--install-bootloader`. Before separately approving reboot, inspect
`/boot/limine/limine.conf` and the Limine firmware entry. Retain the existing
systemd-boot EFI files, working generation, disk passphrase and recovery USB
until Limine has successfully booted and unlocked the installed system.

## Server services and private provisioning

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

## Public package cache (Attic)

`hosts/nixos-server/modules/system/attic.nix` is **disabled until provisioned**.
Enabling `services.atticd.enable` runs the pinned Nixpkgs Attic module, including
its native sandbox, as a dynamic user on `127.0.0.1:8080`. Nginx exposes
`https://cache.kror.net/` with ACME HTTPS; only TCP 80/443 open. Hysteria's UDP
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
This is time-bounded retention, not a disk quota; monitor free space and adjust
retention before the disk fills.

### Targets and publication boundary

`flake.nix` exports `cacheTargets.x86_64-linux` and the same named `packages`.
The four costly patches (`filen-desktop`, `fuzzel`, `quickshell`, `hyprland`) and
custom `tg-ws-proxy`, `photocraft`, `filmcraft`, `bibata-material-cursor`,
`google-sans-rounded`, `vpn`, and `omp` come from the **desktop's final pkgs**,
not a second import with approximate overlays. `spicetify-cli` is the exact
patched Home Manager `spicetifyPackage`, without Spotify. `vhelper` and
`openwave` use their exact locked input outputs consumed by the desktop.

These roots are redistributable according to their pinned package metadata:
Filen is AGPL, desktop patches preserve upstream free licenses, the custom
packages are MIT/Apache/GPL/OFL, and Vhelper/OpenWave/OMP are GPL/MIT/MIT.
The upload includes runtime closures, not build dependencies. Filen references
Nixpkgs Electron/rclone; OpenWave references the free GTK/audio stack; Vhelper
references Protontricks, whose pinned package uses `steam.run-free`, **not the
proprietary Steam client**. Wrappers/fonts reference ordinary free tools/libraries.
Preserve this boundary when adding roots or updating runtime dependencies.
Attic skips paths already signed by the official `cache.nixos.org-1` key.

No system/Home Manager aggregate closure is published. Proprietary Spotify,
Discord/Equicord, Brave, NokoChat and Kotlin LSP are deliberately excluded;
`allowUnfree` on the desktop is not redistribution permission. VTS OpenDeck's
separate exported package is not a cache target (the desktop uses Flatpak).
If proprietary caching becomes necessary, first establish redistribution rights
or design a separate authenticated private cache; do not add those roots here.

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
  arrangement; buying a domain does not provide one.
- Do not publish AAAA unless IPv6 is reachable; the shared server configuration
  disables IPv6. Keep LAN SSH and console recovery available.

The helper asks before provisioning credentials/enabling the checkout module,
before activation, before public-cache setup, and before generating the scoped
GitHub upload token. An already active Attic/Nginx deployment is validated without
another rebuild. Declining an initial activation leaves a command to run later;
rerun the helper afterward to finish cache setup. Enabling the server accepts ACME
terms; set `security.acme.defaults.email` separately if a contact is wanted.
Inspect failures with `journalctl -u atticd -u nginx`.

Existing JWT credentials and cache signing identity are preserved. A changed
saved public key, unsafe permissions/path, private cache, or incompatible
endpoint stops setup instead of silently replacing trust. A pending upload token
is retained until credential transfer succeeds; private keys/tokens never enter the checkout,
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
default). Provision the existing `~/.ssh/nixos-server` FIDO handle first;
verify the server host fingerprint through its console before accepting a new
SSH identity. SSH agent forwarding is disabled for these transfers. The helper
retrieves the saved public key over SSH and compares it to the HTTPS cache
identity before installing trust or publishing credentials.

`client` asks before writing root-owned `/etc/nix/attic.conf` and separately
before desktop activation/daemon restart. An identical existing file is reused;
a different file or symlink is refused rather than clobbered. Missing include
means official-cache-only behavior until activation. This file contains only
`extra-substituters` and `extra-trusted-public-keys`: no JWT or private key.
Official caches/signature checking remain enabled; no trusted user is added.
Server/Darwin trust is unchanged.

For the first activation, the helper builds with the verified cache URL/key as
root-only Nix invocation options, then activates that exact snapshot through
`nh`. This permits downloads before the optional include is active, without
rewriting immutable `nix.conf` or granting a trusted user. Uncached outputs can
still build locally; publish matching committed inputs first.

`github` requires an authenticated `gh` session and asks before setting
`ATTIC_PUBLIC_KEY` and the scoped `ATTIC_TOKEN` on `rikkichy/nixcfg`. The token
travels through protected files/stdin, never a pasted secret or command argument.
It asks separately before removing the server's staged token and before starting
publication of all targets. Failed credential transfer or cancellation retains the
staged token for retry. Renew the 90-day token by rerunning server mode after
consuming the staged token, then rerunning GitHub mode. It can pull/push only
`nixcfg`, not create/configure/destroy caches or delete paths. Expiration bounds
access; rotating the JWT key revokes **all** tokens and is not a renewal step.
Approved remote token cleanup uses a terminal and `sudo` to remove the file from
its root-owned directory. With agent forwarding disabled, remote sudo may
require the server account's password fallback.

The isolated safety check uses the same pinned OpenSSL and jq packages:

```sh
nix shell --no-write-lock-file \
  'path:.#nixosConfigurations.nix.pkgs.openssl' \
  'path:.#nixosConfigurations.nix.pkgs.jq' \
  --command bash scripts/attic-setup-test.sh
```

### CI use and download verification

`.github/workflows/package-cache.yml` publishes on relevant pushes to `main`
and manual dispatch. It builds each selected target separately (two concurrent
runners), keeps GC roots until upload, and uploads its runtime closure with Attic.
CI uses the independently provisioned `ATTIC_PUBLIC_KEY`, never a newly discovered
remote key or disabled signatures. The preflight checks that the upload secret
exists; build steps receive no token. The upload step reads it from a private
file and removes that file on exit. Actions are pinned to commit revisions.

CI builds the **committed** `flake.lock`. Local uncommitted input updates do not
match published derivations until deliberately committed. Wait for publication
before expecting matching downloads; evaluation alone is not a populated cache.

```bash
gh workflow run package-cache.yml --repo rikkichy/nixcfg -f target=fuzzel
gh run list --repo rikkichy/nixcfg --workflow package-cache.yml
# After provisioning/publication, use the desktop's authenticated trust settings:
nix build --no-link --max-jobs 0 'path:/etc/nixos#fuzzel'
```

Manual `target=all` publishes every explicit target; an unknown target fails
selection. `--max-jobs 0` refuses local source compilation, but an already present
store path is not download proof. For real acceptance, copy the published output
to a fresh temporary local store with `nix copy --from https://cache.kror.net/nixcfg
--to "local?root=$temporary_store" --option extra-trusted-public-keys "$key"
"$published_store_path"`; obtain the exact path from CI's build JSON/logs or
`nix eval --raw 'path:/etc/nixos#fuzzel.outPath'` at the same committed lock.
Use an input-addressed output for signature-enforcement checks: content-addressed
paths can be accepted independently of a trusted signature. Verify a narinfo
carries the recorded `nixcfg` signature, an anonymous download succeeds, and a
valid anonymous `PUT /_api/v1/upload-path` is refused. A malformed request's
HTTP 400 is not authentication proof; upload metadata belongs in the
`X-Attic-Nar-Info` header. Never discard real store paths or disable signature
checks merely to force a smoke test.

## Remote SSH over Hysteria2

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

The local forward binds only `127.0.0.1:2222`. The server ACL permits only its
own `127.0.0.1:22` and rejects other destinations. The remote SSH alias shares
the LAN alias's host-key identity; verify the server fingerprint on first use,
never bypass a mismatch. Keep the YubiKey connected to the client.

Salamander obscures QUIC rather than presenting a normal HTTP/3 website; it
cannot bypass a blanket UDP block. There is no full-device VPN or client
autostart. Router changes remain manual; activation requires explicit approval.
Test from the actual remote network before relying on it for access.
