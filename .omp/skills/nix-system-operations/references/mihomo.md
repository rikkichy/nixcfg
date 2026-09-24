# Mihomo networking — Linux hosts

Sources: `common/modules/nixos-networking.nix`,
`common/modules/nixos-mihomo-secrets.nix`, `common/dotfiles/mihomo.yaml`,
`common/pkgs/{mihomo-config.py,vpn.nix}`, and each host's `.secrets/<host>/sops.nix`.
Desktop-only LAN ports remain in `hosts/nix/modules/system/networking.nix`.
Operator procedures: [VPN in docs/nix.md](../../../../docs/nix.md#vpn-mihomo)
and [server provisioning](../../../../handbook.md#server-services-and-private-provisioning).
Read [SOPS safety](boot-auth-secrets.md#sops-authoring-and-identity-boundaries)
before changing secret inputs and [nixcfg-validation](../../nixcfg-validation/SKILL.md)
for validation and security acceptance checks.

## Public template, private runtime rendering

The NixOS Mihomo module runs a `DynamicUser` service, with `CAP_NET_ADMIN` from
`tunMode`, and consumes `/run/mihomo/config.yaml` through `LoadCredential`.
The repository template is public. `mihomo-config.py` takes a public hostname
for `x-device-model`, inserts the three private values, and serializes JSON
(valid YAML) at runtime; this safely preserves quotes, backslashes, and newlines.
Never replace serialization with
textual placeholder splicing or put secret strings into Nix, `writeText`,
derivation inputs, command arguments, logs, or documentation.

Each host wrapper uses SOPS only when its own `.secrets/<host>/personal.yaml`
exists. Keys are `mihomo/primary_url`, `mihomo/quattro_url`, and `mihomo/hwid`.
Server provisioning requires its own real recipient rule and host key; never
borrow the desktop private identity or silently reuse its HWID.
Without ciphertext the legacy files are the inputs:
`/etc/mihomo/subscription.url`, `/etc/mihomo/quattro.url`, and
`/etc/mihomo/hwid`. Keep those root-owned mode `0600` files for rollback even
when SOPS is active. All inputs must exist and be nonempty; a missing HWID fails,
never generates a replacement identity.

SOPS strings remain raw. Legacy mode removes whitespace to preserve its
established effective values. Import the exact meaningful HWID privately;
distinguish file framing from identity and do not blindly normalize the SOPS
strings or derive HWID from machine-id. Decryption success does not establish
provider acceptance or simultaneous-device-limit compatibility.

Secret installation uses sops-nix systemd activation. `mihomo-config` requires
and runs after `sops-install-secrets.service` in SOPS mode, and runs before each
Mihomo start: it intentionally has no `RemainAfterExit`. Root-owned decrypted
inputs are mode `0400`; the runtime directory is `0700` and rendered output
`0600`, written through a temporary file and atomic replacement. SOPS updates
request a Mihomo restart so a new `LoadCredential` receives the new rendering.
Updating a source file does not change a running credential. Prove the
controlled changed-secret restart path after approved activation, without
printing configuration or provider URLs. After repairing missing inputs, a
Mihomo restart reruns the renderer.

## Tunnel and local control boundaries

Keep these three names synchronized when renaming the TUN device:

- `tun.device` in `common/dotfiles/mihomo.yaml`;
- `networking.networkmanager.unmanaged` in
  `common/modules/nixos-networking.nix`;
- `networking.firewall.trustedInterfaces` in that same module.

The current device is `mihomo`; IPv6 is disabled, reverse-path filtering is
loose, and LAN application ports are scoped to the physical interfaces. Do not
turn those into unrestricted firewall openings to fix tunnel routing. The
controller binds `127.0.0.1:9090`, mixed proxy has `allow-lan: false`, and DNS
hijacks port 53 through the TUN. The dashboard is not tunnel proof: inspect
`ip -br addr show mihomo` for an actual IPv4 address; `UP` with only link-local
IPv6 is not a working tunnel.

Run **`vpn off` before network-heavy work** such as substituter fetches and
Git pushes. Node routing can cause stuck downloads or TLS unexpected EOF that
looks unrelated to the VPN. Off means selecting `DIRECT` in the top-level
`PROXY` group, **not stopping Mihomo**, which also removes DNS hijacking.
`profile.store-selected` persists the choice in `cache.db` under the service's
state directory; without it, startup resets to the first group member.

## Subscription and node failure modes

- Keep `x-hwid` on **both** providers. A panel can return HTTP 200 with valid
  YAML but a single “App not supported” node targeting `0.0.0.0:1` when the
  device ID is absent or rejected. Mihomo starts, then all connections fail.
  User-Agent controls format (`clash.meta` YAML versus generic base64), not
  device authorization. Inspect behavior privately without exposing inputs.
- Keep `proxy: DIRECT` on **both** providers. Otherwise Mihomo can fetch its
  subscription through the very tunnel it needs to repair: a bad update then
  cannot self-recover and may surface only as EOF.
- Node latency needs membership **and** health history. Top-level `PROXY`
  currently contains `PRIMARY`, `QUATTRO`, and `DIRECT`, not the provider nodes.
  Query `/proxies/PRIMARY` or `/proxies/QUATTRO` for active-group membership and
  `/providers/proxies/primary` or `/providers/proxies/quattro` for delays. Reading
  either endpoint alone gives an incomplete but plausible list. `vpn nodes`
  merges them, filters built-ins, sorts measured delays, and puts unknowns last.

`vpn` is a `writeShellApplication` installed in `environment.systemPackages`,
not an alias: fish, Hyprland, and the Stream Deck use the same command.
`vpn subscription` selects Primary/Quattro, each with its own selection and
`*-AUTO` group; a per-user `last-subscription` file remembers which to restore
when `PROXY` is `DIRECT`. `vpn use PATTERN` searches live active-subscription
nodes by regex because provider names change. `vpn select NAME` validates an
exact live name for pickers. Keep the distinction and the two-level group
selection when changing callers; consult
[desktop-shell](../../desktop-shell/SKILL.md) for the picker/keybind surface.
