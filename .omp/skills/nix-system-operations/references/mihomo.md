# Mihomo networking — desktop host nix

Sources: `hosts/nix/modules/system/networking.nix`,
`common/modules/nixos-mihomo-secrets.nix`, `common/dotfiles/mihomo.yaml`,
`common/pkgs/{mihomo-config,vpn.nix}`.
Mihomo, the `vpn` command and tunnel-specific network rules are desktop-only.
`nixos-server` imports neither the VPN service nor its secret renderer.
Operator procedures: [VPN in docs/nix-networking.md](../../../../docs/nix-networking.md#vpn-mihomo).
Read [private-input safety](boot-auth-secrets.md#subscription-provisioning-and-retained-identity-boundaries)
before changing subscription inputs.

## Public template, private runtime rendering

The NixOS Mihomo module runs a `DynamicUser` service, with `CAP_NET_ADMIN` from
`tunMode`, and consumes `/run/mihomo/config.yaml` through `LoadCredential`.
The repository template is public. The compiled Rust `mihomo-config` command takes
seven arguments: hostname, template path, Primary URL path, Quattro URL path,
output path, header path and username. There is no mode or HWID-path argument.
It uses the public hostname for `x-device-model` and fills the template with
JSON-serialized scalars at runtime. Unicode line separators and YAML-sensitive controls are
escaped so quotes, backslashes, newlines, and Unicode retain their decoded values.
Missing or unknown runtime placeholder fields fail before either output is published.
Keep runtime placeholders `${name}` unquoted in the public template. The renderer
supplies serialized scalars. Write `$$` for a literal dollar sign in that template.
The renderer also generates the controller's random bearer token on each render.
It atomically writes a mode-`0400` authorization-header file owned by the desktop
user. The header lives directly under root-owned `/run`, not in a user-writable
directory. All temporary files are created privately before publication.
Never substitute raw secret text. Never put secret strings into Nix, `writeText`,
derivation inputs, command arguments, logs, or documentation.

The only subscription inputs are `/etc/mihomo/subscription.url` and
`/etc/mihomo/quattro.url`, root-owned mode `0600`, with a root-owned mode-`0700`
parent. The renderer reads `/sys/class/dmi/id/product_uuid` directly at runtime
for both providers' `x-hwid`. It does not read, generate or persist a dedicated
HWID file, and has no machine-id fallback.

Inputs must be UTF-8. Unicode whitespace and U+001C–U+001F are removed, retaining
the subscription files' established normalization; empty results fail.
The firmware UUID must have the standard 8-4-4-4-12 hexadecimal form; letter case
is preserved, and all-zero/all-f UUIDs fail. Missing or invalid firmware data
fails startup, never invents a replacement identity.
Firmware identity is not universally the provider's registered device ID.
Cutover from an old HWID or hardware replacement can change authorization or
consume a provider device slot. Provider acceptance must be checked separately.

`mihomo-config` runs as root before each Mihomo start and intentionally has no
`RemainAfterExit`. It has no secret-decryption service dependency. The runtime
directory is `0700`. Rendered output is `0600`, written through a temporary file
and atomic replacement. `/run/mihomo/config.yaml` contains both subscription
URLs **and the firmware UUID**; treat it as private runtime material.
The service executes the compiled package, which is also a Mihomo restart trigger.
Changes to renderer source or dependencies therefore replace the next runtime rendering.
The API header is published before the rendered config. Failure prevents service
startup. A restart rotates it, so callers must read the file for each request.
Updating a source file does not change a running credential. Prove the
controlled changed-secret restart path after approved activation, without
printing configuration or provider URLs. After repairing missing inputs, a
Mihomo restart reruns the renderer.

## Tunnel and local control boundaries

Keep these three names synchronized when renaming the TUN device:

- `tun.device` in `common/dotfiles/mihomo.yaml`.
- `networking.networkmanager.unmanaged` in
  `hosts/nix/modules/system/networking.nix`.
- `networking.firewall.trustedInterfaces` in that same module.

The current device is `mihomo`. IPv6 is disabled, reverse-path filtering is
loose, and LAN application ports are scoped to the physical interfaces. Do not
turn those into unrestricted firewall openings to fix tunnel routing.
The controller binds `127.0.0.1:9090`, mixed proxy has `allow-lan: false`, and
Mihomo DNS and TUN DNS hijacking are disabled. Resolution uses the system DNS.
Krypton routing uses destination IP and port. TLS SNI sniffing on port 443
supports the exact Noko, `spype.pages.dev` and `ota.waydro.id` rules without
overriding the connection destination. The web dashboard is disabled. The controller API serves the
picker and CLI. Controller status is not tunnel proof.
Inspect `ip -br addr show mihomo` for an actual IPv4 address. `UP` with only link-local
IPv6 is not a working tunnel.

All controller requests must use `--header @/run/mihomo-api.header`.
Never expand the token into command arguments or log it. Browser CORS permits only the
localhost controller origin. See the operator guide for ownership and lifecycle.

Scoped mode proxies Krypton's `162.19.224.212` ports `6700` and `3030` plus
the exact `noko.chat`, `api.noko.chat`, `cdn.noko.chat`, `spype.pages.dev` and
`ota.waydro.id` hostnames, with `MATCH,DIRECT` for everything else.
`vpn mode global` selects `PROXY` in `GLOBAL` before changing Mihomo's mode.
Global traffic therefore uses the same subscription/server instead of
`GLOBAL`'s default `DIRECT`. `vpn mode scoped` restores rule mode. Both changes
close tracked connections so existing traffic follows the new policy. The mode
is runtime-only. The template starts scoped. Do not stop Mihomo to change
routing: that removes the tunnel. `profile.store-selected` persists server
choices in `cache.db` under the service's state directory. There are no geosite,
ASN or process routing rules. Process lookup is disabled. The service does not
request cross-user inspection privileges or override `ProtectProc`. Keep the
upstream sandbox.

## Subscription and node failure modes

- Keep `x-hwid` on **both** providers. A panel can return HTTP 200 with valid
  YAML but a single “App not supported” node targeting `0.0.0.0:1`.
  This occurs when the device ID is absent or rejected. Mihomo starts, then all connections fail.
  User-Agent controls format (`clash.meta` YAML versus generic base64), not
  device authorization. Inspect behavior privately without exposing inputs.
- Keep `proxy: DIRECT` on **both** providers. Otherwise Mihomo can fetch its
  subscription through the very tunnel it needs to repair.
  A bad update then cannot self-recover and may surface only as EOF.
- Child selectors use `empty-fallback: REJECT`. Each Krypton endpoint's proxy rule
  is paired with a rejection rule so unsupported flows cannot fall through to
  `MATCH,DIRECT`. Keep each pair aligned when updating the endpoints.
- HTTP health checks require 204 but do not test UDP relay. Lazy checks can leave
  inactive-provider latency stale. Preserve manual node selection.
- Node latency needs membership **and** health history. Top-level `PROXY`
  contains `PRIMARY` and `QUATTRO`, not the provider nodes.
  Query `/proxies/PRIMARY` or `/proxies/QUATTRO` for active-group membership and
  `/providers/proxies/primary` or `/providers/proxies/quattro` for delays. Reading
  either endpoint alone gives an incomplete but plausible list. `vpn nodes`
  merges them using `extra[testUrl]`, filters built-ins, sorts measured delays,
  and puts failed/unmeasured results last. Generic `history`/`alive` fields do
  not enforce the provider's expected HTTP status.

`vpn` is a `writeShellApplication` installed in `environment.systemPackages`,
not an alias: fish, Hyprland, and the Stream Deck use the same command.
`vpn subscription` selects Primary/Quattro, each retaining its manual server
selection. `vpn mode [global|scoped]` reads or changes routing. The Quickshell VPN
menu offers the opposite mode. There are no AUTO groups or separate selection-state
files. Bare `vpn` reports the server. `vpn use PATTERN` searches live
active-subscription nodes by regex because provider names change. It makes a
one-time selection. `vpn select NAME` validates an exact live name for pickers.
Keep the distinction and the two-level group selection when changing callers.
Consult [desktop-shell](../../desktop-shell/SKILL.md) for the picker/keybind
surface.
