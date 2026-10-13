# Mihomo networking — desktop host nix

Sources: `hosts/nix/modules/system/networking.nix`,
`common/modules/nixos-mihomo-secrets.nix`, `common/dotfiles/mihomo.yaml`,
`common/pkgs/{mihomo-config.py,vpn.nix}`, and `.secrets/nix/sops.nix`.
Mihomo, the `vpn` command and tunnel-specific network rules are desktop-only;
`nixos-server` imports neither the VPN service nor its secret renderer.
Operator procedures: [VPN in docs/nix-networking.md](../../../../docs/nix-networking.md#vpn-mihomo).
Read [SOPS safety](boot-auth-secrets.md#sops-authoring-and-identity-boundaries)
before changing secret inputs and [nixcfg-validation](../../nixcfg-validation/SKILL.md)
for validation and security acceptance checks.

## Public template, private runtime rendering

The NixOS Mihomo module runs a `DynamicUser` service, with `CAP_NET_ADMIN` from
`tunMode`, and consumes `/run/mihomo/config.yaml` through `LoadCredential`.
The repository template is public. `mihomo-config.py` takes a public hostname
for `x-device-model` and fills the public YAML template with JSON-serialized
scalars at runtime. Unicode line separators and YAML-sensitive controls are
escaped so quotes, backslashes, newlines, and Unicode retain their exact values.
Missing or unknown runtime placeholder fields fail before either output is published.
Keep runtime placeholders `${name}` unquoted in the public template; the renderer
supplies serialized scalars. Write `$$` for a literal dollar sign in that template.
It also generates the controller's random bearer token on each render and
atomically writes a mode-`0400` authorization-header file owned by the desktop
user. The header lives directly under root-owned `/run`, not in a user-writable
directory; all temporary files are created privately before publication.
Never substitute raw secret text or put secret strings into Nix, `writeText`,
derivation inputs, command arguments, logs, or documentation.

The desktop wrapper uses SOPS only when `.secrets/nix/personal.yaml` exists.
Keys are `mihomo/primary_url`, `mihomo/quattro_url`, and `mihomo/hwid`.
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
The API header is published before the rendered config; failure prevents service
startup. A restart rotates it, so callers must read the file for each request.
Updating a source file does not change a running credential. Prove the
controlled changed-secret restart path after approved activation, without
printing configuration or provider URLs. After repairing missing inputs, a
Mihomo restart reruns the renderer.

## Tunnel and local control boundaries

Keep these three names synchronized when renaming the TUN device:

- `tun.device` in `common/dotfiles/mihomo.yaml`;
- `networking.networkmanager.unmanaged` in
  `hosts/nix/modules/system/networking.nix`;
- `networking.firewall.trustedInterfaces` in that same module.

The current device is `mihomo`; IPv6 is disabled, reverse-path filtering is
loose, and LAN application ports are scoped to the physical interfaces. Do not
turn those into unrestricted firewall openings to fix tunnel routing.
The controller binds `127.0.0.1:9090`, mixed proxy has `allow-lan: false`, and
Mihomo DNS and TUN DNS hijacking are disabled. Resolution uses the system DNS;
domain routing relies on sniffing. The web dashboard is disabled; the controller
API serves the picker and CLI. Controller status is not tunnel proof: inspect
`ip -br addr show mihomo` for an actual IPv4 address; `UP` with only link-local
IPv6 is not a working tunnel.

All controller requests must use `--header @/run/mihomo-api.header`; never expand
the token into command arguments or log it. Browser CORS permits only the
localhost controller origin. See the operator guide for ownership and lifecycle.

Scoped mode uses service-selective rules with `MATCH,DIRECT`; ordinary Nix
downloads and Git pushes go direct. `vpn mode global` selects `PROXY` in `GLOBAL`
before changing Mihomo's mode, so global traffic uses the same subscription/server
instead of `GLOBAL`'s default `DIRECT`. `vpn mode scoped` restores rule mode.
Both changes close tracked connections so existing traffic follows the new policy.
The mode is runtime-only; the template starts scoped. Do not stop Mihomo to change
routing: that removes the tunnel. `profile.store-selected` persists server choices
in `cache.db` under the service's state directory.
Native Discord is matched by its `.Discord-wrapped` executable, including
IP-addressed voice UDP. Process lookup requires `ProtectProc=default` and
`CAP_SYS_PTRACE`/`CAP_DAC_READ_SEARCH` alongside `CAP_NET_ADMIN`; retain
`DynamicUser` and the remaining sandbox. These are broad cross-user inspection
privileges, not Discord-only access. Browser Discord is only domain-routed.
`scripts/mihomo-routing-test.py` checks same-user lookup and UDP fail-closed
behavior in isolated Mihomo; cross-user service lookup needs live verification
after approved activation. See the operator guide for this security boundary.

## Subscription and node failure modes

- Keep `x-hwid` on **both** providers. A panel can return HTTP 200 with valid
  YAML but a single “App not supported” node targeting `0.0.0.0:1` when the
  device ID is absent or rejected. Mihomo starts, then all connections fail.
  User-Agent controls format (`clash.meta` YAML versus generic base64), not
  device authorization. Inspect behavior privately without exposing inputs.
- Keep `proxy: DIRECT` on **both** providers. Otherwise Mihomo can fetch its
  subscription through the very tunnel it needs to repair: a bad update then
  cannot self-recover and may surface only as EOF.
- Child selectors use `empty-fallback: REJECT`. Service proxy rules are paired
  with rejection rules so a node without UDP support cannot fall through to
  unrelated traffic's `MATCH,DIRECT`. Keep the target and rejection pairs aligned.
- HTTP health checks require 204 but do not test UDP relay; lazy checks can leave
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
selection. `vpn mode [global|scoped]` reads or changes routing; the Fuzzel VPN
menu offers the opposite mode. There are no AUTO groups or separate selection-state
files. Bare `vpn` reports the server. `vpn use PATTERN` searches live
active-subscription nodes by regex because provider names change; it makes a
one-time selection. `vpn select NAME` validates an exact live name for pickers.
Keep the distinction and the two-level group selection when changing callers;
consult [desktop-shell](../../desktop-shell/SKILL.md) for the picker/keybind
surface.
