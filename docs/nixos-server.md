# nixos-server — headless NixOS

[Handbook](../handbook.md) · [Installation](install.md) · [Minecraft](minecraft.md)

The server uses NetworkManager-managed DHCP, console login, and key-only SSH on
port 22. SSH password/keyboard-interactive authentication and root login are
disabled. No desktop session is enabled.

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
