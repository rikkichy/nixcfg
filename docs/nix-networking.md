# nix — networking

[Desktop operations](nix.md) · [Security and secrets](nix-security.md) · [Installation](install.md)

Host `nix` only: the Ryzen/NVIDIA desktop, user `ri`, checkout `/etc/nixos`.
Run repository commands there. The server and macOS host do not use these
VPN services. Source edits do not authorize activation, service restarts,
subscription changes or live application/network tests; obtain operator approval.

For missing private inputs, use
[first provisioning](nix-security.md#private-inputs-and-first-provisioning)
or [replacement and rollback](nix-security.md#reinstall-replacement-revocation-and-rollback).

## LAN face tracking

VBridger receives iFacialMocap tracking on UDP `49983`. The firewall permits
that port on `enp11s0` and `wlp8s0` only, alongside the existing LAN application
ports in `hosts/nix/modules/system/networking.nix`. Activate the configuration
before reconnecting the phone; source edits alone do not change the live firewall.

## VPN (mihomo)

`services.mihomo` runs the tunnel as a system service and starts at boot; there
is no app to launch. The web dashboard is disabled. The localhost controller at
`127.0.0.1:9090` remains available to the VPN picker and CLI with bearer-token
authentication. Browser origins are restricted to that localhost origin.

### Split routing and server selection

YouTube, Discord, Roblox/Sober, Instagram, Proton Mail, Spotify, Bitwarden, Pinterest,
cachix.org, noko.chat, anime-365.ru, 6b6t.org, enderdash.com and cyrisia.com use the selected proxy server; other
destinations use `DIRECT`. The listed services use Mihomo's geosite data except
cachix.org, noko.chat, anime-365.ru, 6b6t.org, enderdash.com and cyrisia.com, whose domain-suffix rules include all
subdomains (including api.noko.chat and dl.noko.chat).
Minecraft port `25565` uses the proxy only at Hypixel's `172.65.197.160`
(`mc.hypixel.net`) and 6b6t's `15.204.129.101` (`alt.6b6t.org`, the SRV target
for `6b6t.org` and `join.6b6t.org`). IP-and-port rules do not proxy other ports
at these addresses or other Minecraft servers. These are fixed DNS snapshots:
refresh the addresses when endpoints change. DNS handling remains unchanged.
Roblox's production network uses ASN data. Mihomo downloads geosite and ASN data
from the publisher's jsDelivr mirror and checks for updates daily; first startup
needs access to it.
In Mihomo 1.19.31, a failed overdue GEO update during startup can stop its updater
until a reload/restart. Check the GEO logs after a connectivity failure.
Native Discord's `.Discord-wrapped` process uses proxy/reject rules for all
public destinations, including IP-addressed voice UDP. Loopback and private LAN
rules take precedence. This does not identify Discord running inside a browser;
browser Discord retains domain routing without guaranteed voice-IP coverage.
Process lookup uses `find-process-mode: strict`. The service retains `DynamicUser`
and its other hardening, but uses `ProtectProc=default`, `CAP_SYS_PTRACE` and
`CAP_DAC_READ_SEARCH` to inspect socket owners across users. These privileges
permit broader process and file reads, not only Discord inspection. They do not
make application-name matching a security boundary. Shared service domains can
also include related products.

`scripts/mihomo-routing-test.py` exercises real process lookup and UDP rejection
against isolated Mihomo without a TUN or production credentials. It requires
Mihomo and Python with PyYAML. This same-user check does not prove the system
service's cross-user lookup; after activation, verify voice connections report
`ProcessName` / `.Discord-wrapped` and the selected proxy in `/connections`.

Empty subscriptions reject traffic instead of falling back to a direct connection.
Each service's proxy rule has a matching rejection rule: if the selected server
cannot relay UDP, that service fails closed while unrelated traffic stays direct.
Keep these pairs together when editing the target list. Use a UDP-capable server
for voice and games; a successful HTTP health check does not prove UDP support.
Health checks require the endpoint's HTTP 204 response. Checks remain lazy, so
an inactive subscription can show stale measurements.

TCP concurrency races multiple resolved addresses for faster connection setup;
it does not increase bandwidth. The TUN retains its gVisor stack.

**`SUPER + SHIFT + V`** opens the VPN picker. **Switch subscription** opens
**Primary** and **Quattro**, each retaining its selected server. **Choose server**
opens only the active subscription's live nodes, fastest first. Dismissing
either submenu leaves the selection unchanged. **Switch to global** routes traffic
handled by Mihomo through the selected subscription/server; **Switch to scoped**
restores the service-specific rules. The prompt shows the current mode.
Switching closes existing Mihomo connections so applications reconnect using the
new policy; downloads, calls and games can be interrupted. The mode is a runtime
choice; Mihomo starts in scoped mode from the template. **Edit config** opens the public
`common/dotfiles/mihomo.yaml` template in Zed (`zeditor`), including when Mihomo
is unavailable; it never opens the private rendered configuration. Saving edits
does not activate them: apply them with an approved NixOS rebuild.
There are no DIRECT, AUTO or on/off controls. The picker is also available as
`vpnp` and as **VPN server** in desktop tools:

```
vpn                              # show the selected server
vpn status                       # show the selected server
vpn mode                         # show global or scoped routing
vpn mode global                  # proxy Mihomo traffic through the selected server
vpn mode scoped                  # restore service-specific routing
vpn subscription                 # active subscription name
vpn subscription primary         # select Primary's remembered server
vpn subscription quattro         # select Quattro's remembered server
vpn list                         # active subscription's nodes and latency
vpn use <pattern>                # fastest matching node in that subscription
vpn select <name>                # exact node in that subscription
vpn ip                           # public IP and country under the current routing mode
```

Selection persists in Mihomo's cache. `vpn use` is a one-time manual choice,
not continuous automatic selection.

`vpn use` takes a case-insensitive regex, not a node name — `vpn use швец`
picks the fastest Swedish node. **Match on the flag emoji** (`vpn use 🇸🇪`) when
you want something durable: node names carry numbering, `WlFl`/`LTE` suffixes
and trailing spaces that providers change without notice.

The proxy-group hierarchy is **PROXY** choosing **PRIMARY** or
**QUATTRO**, and each subscription group contains only provider nodes.
`profile.store-selected` persists selections in
`/var/lib/private/mihomo/cache.db`. With no valid cached choice, Mihomo uses
the first available member. Runtime state does not need to be deleted.

Changing servers does not change routing policy. Direct destinations still
pass through the TUN, but Mihomo connects through the physical interface.
Stopping Mihomo removes the tunnel; it is not a routing toggle.
External shortcuts can invoke `vpnp`, `vpn mode global`, `vpn mode scoped`,
or `vpn select <name>`.

`scripts/vpn-mode-test.py /nix/store/...-vpn/bin/vpn` checks a built CLI against
isolated Mihomo with loopback-only traffic. It requires Python and `mihomo` on
PATH, and verifies global proxy selection, scoped routing and closing old flows
without accessing production credentials or changing the desktop tunnel.

For a zapret cutover, pause it rather than uninstalling it, then verify video
playback, Discord voice/screenshare and a Sober game join. Confirm their
connections select `PROXY` while an unrelated destination selects `DIRECT`.
Configuration evaluation does not prove these live application paths.

Edit the public template `common/dotfiles/mihomo.yaml`; [runtime rendering](../.omp/skills/nix-system-operations/references/mihomo.md#public-template-private-runtime-rendering)
supplies private strings outside Nix evaluation/build inputs. Never put credentials
in the template; Mihomo's private provider/state files must also stay outside Git.

The renderer also generates a fresh controller token on each service start.
It publishes `/run/mihomo-api.header` atomically, owned by desktop user `ri`
with mode `0400`, under the root-owned `/run` directory. The file contains only
the controller authorization header, never subscription URLs or HWID. CLI and
recovery requests use `curl --header @/run/mihomo-api.header` so the token is not
placed in process arguments. Do not copy it into Git, logs, shell history or
application profiles. No new age key or SOPS input is required.

Other controller clients must read that header at request time and authenticate.
OpenDeck should invoke the host `vpn` command rather than access the controller
directly from its sandbox. The template is not a standalone runnable config:
the runtime renderer supplies authentication and subscription credentials.

Mihomo's DNS server and TUN DNS hijacking are disabled. Applications and
proxy-node lookups use the system resolver; configure upstream DNS through
NetworkManager, not the Mihomo template. When the system uses the LAN router,
the router retains its ControlD DoQ connection and private endpoint.

Domain rules rely on HTTP/TLS/QUIC sniffing without DNS mappings. ECH and
unsupported traffic can prevent domain classification; those connections
follow IP rules or the final `DIRECT` rule. Sniffing does not replace the
destination address selected by the system resolver.

After an approved rebuild disables fake-IP handling, fully restart applications
to discard cached synthetic addresses.


Private input provisioning and SOPS/PIV administration are in
[the security guide](nix-security.md#private-inputs-and-first-provisioning).

### Tunnel diagnosis

When renaming the TUN, preserve the [three-way device-name invariant](../.omp/skills/nix-system-operations/references/mihomo.md#tunnel-and-local-control-boundaries).

If the VPN looks connected but traffic is not tunnelled, do not trust the
controller status — check that the interface actually has its IPv4 address:

```
ip -br addr show mihomo
```

A link that is `UP` with only a link-local v6 address is a tunnel that is not
carrying anything.

## Telegram proxy (tg-ws-proxy)

`Flowseal/tg-ws-proxy` is packaged from source in `hosts/nix/pkgs/bypasses/tg-ws-proxy.nix`
and pinned as a `flake = false` input. Update it explicitly with
`nix flake update tg-ws-proxy --flake /etc/nixos`, then build and activate through
the [host maintenance workflow](nix.md#updates-and-prebuilt-systems).
The package includes `httpx` and `h2` for upstream's HTTP/2 transport.
After updating the pin, check upstream runtime dependencies and build
`nix build --no-link 'path:.#nixosConfigurations.nix.pkgs.tg-ws-proxy'`
before activation.

A systemd **user** service runs it headless on `127.0.0.1:1443`. The secret is
generated once on first start and kept in
`~/.local/state/tg-ws-proxy/secret` (mode 600) — deliberately *not* in this
repo, which is public, and persisted so the value stays stable across restarts
instead of changing every time the service comes up.

Read it with:

```
cat ~/.local/state/tg-ws-proxy/secret
systemctl --user status tg-ws-proxy
```

Then in Telegram Desktop: **Settings → Advanced → Connection type → Proxy**,
add an **MTProto** proxy, server `127.0.0.1`, port `1443`, and paste that
secret.

The GUI tray version is also on PATH as `tg-ws-proxy-tray-linux` if you prefer
it; stop the user service first so the two do not both bind 1443.
