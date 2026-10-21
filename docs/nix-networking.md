# nix — networking

[Desktop operations](nix.md) · [Security and secrets](nix-security.md) · [Installation](install.md)

Host `nix` only: the Ryzen/NVIDIA desktop, user `ri`, checkout `/etc/nixos`.
Run repository commands there. The server and macOS host do not use these
VPN services. Source edits do not authorize activation, service restarts,
subscription changes or live application/network tests. Obtain operator approval.

For missing private inputs, use
[first provisioning](nix-security.md#private-inputs-and-first-provisioning)
or [replacement and rollback](nix-security.md#reinstall-replacement-revocation-and-rollback).

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

### Split routing and server selection

Scoped mode proxies only the observed Krypton startup endpoints on
`162.19.224.212`: loader port `6700` and subsequent initialization port `3030`.
All other destinations and ports use `DIRECT`, including loopback and private
LAN addresses. The IP-and-port rules do not depend on DNS or protocol sniffing.
`vps-c35938de.vps.ovh.net` is the server's reverse-DNS hostname, not a confirmed
hostname used by the loader. Update the rules if Krypton's endpoints move.

There are no domain, geosite, ASN or application-process routing rules.
Sniffing and process lookup are disabled; the service does not request
cross-user process-inspection privileges.

Empty subscriptions reject traffic instead of falling back to a direct connection.
Each endpoint's proxy rule has a matching rejection rule so an unsupported flow
cannot fall through to `MATCH,DIRECT`. Keep each pair together.
Health checks require the endpoint's HTTP 204 response. Checks remain lazy, so
an inactive subscription can show stale measurements.

TCP concurrency races multiple resolved addresses for faster connection setup.
It does not increase bandwidth. The TUN retains its gVisor stack.

**`SUPER + SHIFT + V`** opens the VPN picker. **Switch subscription** opens
**Primary** and **Quattro**, each retaining its selected server. **Choose server**
opens only the active subscription's live nodes, fastest first. Dismissing
either submenu leaves the selection unchanged. **Switch to global** routes traffic
handled by Mihomo through the selected subscription/server. **Switch to scoped**
restores the Krypton-only rule. The prompt shows the current mode.
Switching routing mode closes existing Mihomo connections so applications
reconnect using the new policy. Downloads, calls and games can be interrupted.
Server and subscription changes do not close existing connections.
The mode is a runtime choice. Mihomo starts in scoped mode from the template.
**Edit config** opens the public `common/dotfiles/mihomo.yaml` template in Zed (`zeditor`), including when Mihomo
is unavailable. It never opens the private rendered configuration. Saving edits
does not activate them: apply them with an approved NixOS rebuild.
There are no DIRECT, AUTO or on/off controls. The picker is also available as
`vpnp` and as **VPN server** in desktop tools:

```
vpn                              # show the selected server
vpn status                       # show the selected server
vpn mode                         # show global or scoped routing
vpn mode global                  # proxy Mihomo traffic through the selected server
vpn mode scoped                  # proxy only the Krypton loader endpoint
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
picks the fastest Swedish node. **Match on the flag emoji** (`vpn use 🇸🇪`) for
more stable matching. Node names carry numbering, `WlFl`/`LTE` suffixes
and trailing spaces that providers change without notice.

The proxy-group hierarchy is **PROXY** choosing **PRIMARY** or
**QUATTRO**, and each subscription group contains only provider nodes.
`profile.store-selected` persists selections in
`/var/lib/private/mihomo/cache.db`. With no valid cached choice, Mihomo uses
the first available member. Runtime state does not need to be deleted.

Changing servers does not change routing policy. Direct destinations still
pass through the TUN, but Mihomo connects through the physical interface.
Stopping Mihomo removes the tunnel. It is not a routing toggle.
External shortcuts can invoke `vpnp`, `vpn mode global`, `vpn mode scoped`,
or `vpn select <name>`.

After approved activation, launch Krypton and confirm that its connections to
`162.19.224.212` on ports `6700` and `3030` select `PROXY`, while an unrelated
destination selects `DIRECT`. Verify that Minecraft reaches its window.
Configuration validation does not prove connectivity or a successful game launch.

Edit the public template `common/dotfiles/mihomo.yaml`. The compiled Rust
[`mihomo-config` renderer](../.omp/skills/nix-system-operations/references/mihomo.md#public-template-private-runtime-rendering)
supplies private strings at runtime, outside Nix evaluation and build inputs.
The service and its restart trigger use the same renderer package.
Never put credentials in the template. Mihomo's private provider/state files must also stay outside Git.

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
proxy-node lookups use the system resolver. Configure upstream DNS through
NetworkManager, not the Mihomo template. When the system uses the LAN router,
the router retains its ControlD DoQ connection and private endpoint.

Routing uses the destination IP and port only; no sniffing or DNS mappings are
needed. Changing the template does not reroute an already established loader
connection: restart the instance after approved activation.


Private input provisioning and SOPS/PIV administration are in
[the security guide](nix-security.md#private-inputs-and-first-provisioning).

### Tunnel diagnosis

When renaming the TUN, preserve the [three-way device-name invariant](../.omp/skills/nix-system-operations/references/mihomo.md#tunnel-and-local-control-boundaries).

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
