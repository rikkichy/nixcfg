# nix — networking

[Desktop operations](nix.md) · [Security and secrets](nix-security.md) · [Installation](install.md)

Host `nix` only: the Ryzen/NVIDIA desktop, user `ri`, checkout `/etc/nixos`.
Run repository commands there. The server and macOS host do not use these
VPN services. Source edits do not authorize activation, service restarts,
subscription changes or live application/network tests. Obtain operator approval.

For missing private inputs, use
[first provisioning](nix-security.md#private-inputs-and-first-provisioning)
or [subscription recovery](nix-security.md#subscription-recovery-and-retained-identities).

## LAN face tracking

VBridger receives iFacialMocap tracking on UDP `49983`. The firewall permits
that port on `enp11s0` and `wlp8s0` only, alongside the existing LAN application
ports in `hosts/nix/modules/system/networking.nix`. Activate the configuration
before reconnecting the phone. Source edits alone do not change the live firewall.

## VPN (mihomo)

`services.mihomo.enable = true` in `hosts/nix/modules/system/networking.nix`
starts the tunnel at boot. Configuration changes take effect after an approved
activation. The following controls require the service to be running.
There is no app to launch. The web dashboard is disabled. The localhost controller at
`127.0.0.1:9090` remains available to the VPN picker and CLI with bearer-token
authentication. Browser origins are restricted to that localhost origin.

### Proxy-only routing and server selection

All Internet application traffic uses the selected proxy, including Claude and
Anthropic hostnames, subdomains, literal IPs and traffic with hidden SNI.
There is no hostname allowlist or TLS sniffing. Loopback, private IPv4 LAN and
local discovery remain direct; system DNS can still use the LAN router.

`hosts/nix/modules/system/mihomo-killswitch.nix` installs an independent
kernel OUTPUT/FORWARD guard before NetworkManager and Mihomo start. Public
egress outside the TUN is denied for applications and forwarded containers,
including existing connections. IPv6 egress is denied except on loopback.
Only the trusted Mihomo service account can open direct public IPv4 connections,
for subscription retrieval, resolver bootstrap and proxy transport. The source
module owns the exact LAN, discovery and DHCP exceptions.

If the proxy fails, unsupported traffic is rejected, or Mihomo stops, Internet
applications lose connectivity rather than switching to direct access.
Empty subscriptions reject traffic. Keep `MATCH,PROXY` followed by
`MATCH,REJECT` in the template. Health checks require HTTP 204 and remain lazy,
so an inactive subscription can show stale measurements.

This protects against routing/tunnel failure, not a privileged administrator,
a compromised Mihomo process or an authenticated controller client changing
the policy. Keep the controller credentials private and do not use its API
to enable direct mode. LAN DNS is an intentional exception, not a promise
that DNS queries are hidden from the LAN resolver.

TCP concurrency races multiple resolved addresses for faster connection setup.
It does not increase bandwidth. The TUN retains its gVisor stack.
Because the TUN accepts connections locally, Nix's `connect-timeout` never sees
an unreachable upstream. A stalled cache request would hang rebuilds for the
default 300 s, so `hosts/nix/modules/system/nix.nix` sets
`stalled-download-timeout = 20`, and Nix retries the request instead.
`cache.nixos.org` is the primary substituter there: some exit nodes stall TLS to
`mirror.yandex.ru`, which remains only a lower-priority fallback.

**`SUPER + SHIFT + V`** opens the VPN picker. **Switch subscription** opens
**Primary** and **Quattro**, each retaining its selected server. **Choose server**
opens only the active subscription's live nodes, fastest first. Dismissing
either submenu leaves the selection unchanged. The view shows the subscription
and server, not a claim of verified firewall health.
Server and subscription changes do not close existing connections.
**Edit config** opens the public `common/dotfiles/mihomo.yaml` template in Neovim in Foot, including when Mihomo
is unavailable. It never opens the private rendered configuration. Saving edits
does not activate them: apply them with an approved NixOS rebuild.
There are no routing-mode, DIRECT, AUTO or on/off controls. The picker is also available as
**VPN** in Settings or `quickshell -c expressive ipc call desktop toggle vpn`:

```
vpn                              # show the selected server
vpn status                       # show the selected server
vpn subscription                 # active subscription name
vpn subscription primary         # select Primary's remembered server
vpn subscription quattro         # select Quattro's remembered server
vpn list                         # active subscription's nodes and latency
vpn use <pattern>                # fastest matching node in that subscription
vpn select <name>                # exact node in that subscription
vpn ip                           # public IP and country through the selected proxy
```

Selection persists in Mihomo's cache. `vpn use` is a one-time manual choice,
not continuous automatic selection.

`vpn use` takes a case-insensitive regex, not a node name — `vpn use швец`
picks the fastest Swedish node. **Match on the flag emoji** (`vpn use 🇸🇪`) for
more stable matching. Node names carry numbering, `WlFl`/`LTE` suffixes
and trailing spaces that providers change without notice.

The proxy-group hierarchy is **PROXY** choosing **PRIMARY** or
**QUATTRO**, and each subscription group contains only provider nodes.
`profile.store-selected` persists selections in
`/var/lib/private/mihomo/cache.db`. With no valid cached choice, Mihomo uses
the first available member. Runtime state does not need to be deleted.

Changing servers does not change routing policy. Stopping Mihomo removes the
tunnel but leaves the guard in place; it is not a direct-network fallback.
External shortcuts can invoke `quickshell -c expressive ipc call desktop toggle vpn`
or `vpn select <name>`.

#### Activation and recovery acceptance

Source changes do not enable the live kill switch. Activation, service-stop
tests and reboot each need operator approval and a local recovery console.
Retain a known-working generation before switching: all Internet applications,
downloads and games now depend on the chosen proxy and its protocol support.

After approved activation, verify `systemctl is-active mihomo-killswitch`,
`sudo nft list table inet mihomo_guard`, the TUN's IPv4 address and actual
Claude access through the proxy. With separately approved interruption, stop
Mihomo, confirm new and existing Internet traffic cannot go direct, and capture
the physical interface to confirm no packets reach the test destination.
Restart Mihomo and verify connectivity recovers. Repeat boot acceptance
before describing the installed machine's startup behavior as verified.

The guard is replaced atomically on reload and deliberately survives service
stop, including a configuration rollback. For recovery, boot the retained
known-working generation; do not flush the firewall as a connectivity workaround.
The isolated [VM regression](reference/mihomo.md#kill-switch-verification)
does not replace these operator checks.

Edit the public template `common/dotfiles/mihomo.yaml`. The compiled Rust
[`mihomo-config` renderer](reference/mihomo.md#public-template-private-runtime-rendering)
supplies private strings at runtime, outside Nix evaluation and build inputs.
The service and its restart trigger use the same renderer package.
Never put credentials in the template. Mihomo's private provider/state files must also stay outside Git.
Provision only root-owned mode-`0600` `/etc/mihomo/subscription.url` and
`/etc/mihomo/quattro.url`, under root-owned mode-`0700` `/etc/mihomo`.
The renderer reads `/sys/class/dmi/id/product_uuid` at runtime for both
providers' `x-hwid`; no dedicated HWID file is used. The private
`/run/mihomo/config.yaml` contains both subscription URLs and that UUID.
Firmware UUIDs do not universally match provider-registered IDs: cutover or
hardware replacement may require provider authorization or consume device slots.

The renderer also generates a fresh controller token on each service start.
It publishes `/run/mihomo-api.header` atomically, owned by desktop user `ri`
with mode `0400`, under the root-owned `/run` directory. The file contains only
the controller authorization header, never subscription URLs or HWID. CLI and
recovery requests use `curl --header @/run/mihomo-api.header` so the token is not
placed in process arguments. Do not copy it into Git, logs, shell history or
application profiles.

Other controller clients must read that header at request time and authenticate.
OpenDeck should invoke the host `vpn` command rather than access the controller
directly from its sandbox. The template is not a standalone runnable config:
the runtime renderer supplies authentication and subscription credentials.

Mihomo's DNS server and TUN DNS hijacking are disabled. Applications and
proxy-node lookups use the system resolver. Configure upstream DNS through
NetworkManager, not the Mihomo template. When the system uses the LAN router,
the router retains its ControlD DoQ connection and private endpoint.

File-only subscription provisioning and retained-identity recovery boundaries
are in [the security guide](nix-security.md#private-inputs-and-first-provisioning).

### Tunnel diagnosis

When renaming the TUN, preserve the [device-name invariant](reference/mihomo.md#tunnel-and-local-control-boundaries).

If the VPN appears connected but traffic is not tunnelled, do not trust the
controller status. Check that the interface has its IPv4 address:

```
ip -br addr show mihomo
```

A link that is `UP` with only a link-local v6 address is not carrying tunnel traffic.

## Telegram proxy (tg-ws-proxy)

`Flowseal/tg-ws-proxy` is packaged from source in `hosts/nix/pkgs/bypasses/tg-ws-proxy.nix`
and pinned as a `flake = false` input. Update it explicitly with
`nix flake update tg-ws-proxy --flake /etc/nixos`, then build and activate through
the [host maintenance workflow](nix.md#updates-and-prebuilt-systems).
The package includes `httpx` and `h2` for upstream's HTTP/2 transport.
After updating the pin, review upstream runtime dependencies.

A systemd **user** service runs it headless on `127.0.0.1:1443`.
The secret is generated once on first start and kept in
`~/.local/state/tg-ws-proxy/secret` (mode 600), outside this public repository.
The user service's `StateDirectory` owns its mode-700 parent directory under
`XDG_STATE_HOME`. The persisted value stays stable across service restarts.

Read it with:

```
cat ~/.local/state/tg-ws-proxy/secret
systemctl --user status tg-ws-proxy
```

In Telegram Desktop, open **Settings → Advanced → Connection type → Proxy**.
Add an **MTProto** proxy with server `127.0.0.1` and port `1443`.
Paste the secret.

The package ships only the headless server. Tray entry points and GUI
dependencies are removed during packaging.
