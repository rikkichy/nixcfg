# nixcfg

NixOS config for `nix` — 9950X3D / RTX 3090 / LUKS / Hyprland + Wayle.
Migrated off CachyOS. Clone to **`/home/ri/nixcfg`** — that exact path is
hardcoded in two places (`system.autoUpgrade.flake`, and the Hyprland
`mkOutOfStoreSymlink` in `home.nix`).

## Install, step by step

Boot the NixOS 26.05 minimal ISO. **Secure Boot must be OFF** — the ISO is not
signed with custom keys, and the stick simply will not appear in the boot menu
otherwise.

### 0. Get a network + become root

```
sudo -i
# wifi only: wpa_passphrase SSID PASS > /tmp/w.conf && wpa_supplicant -B -c /tmp/w.conf -i <iface>
ping -c1 github.com
```

### 1. Partition and encrypt

Target is the 1 TB NVMe. **This destroys it.** `lsblk` first and confirm the
name — it is `nvme0n1` on this box.

```
parted /dev/nvme0n1 -- mklabel gpt
parted /dev/nvme0n1 -- mkpart ESP fat32 1MiB 4GiB
parted /dev/nvme0n1 -- set 1 esp on
parted /dev/nvme0n1 -- mkpart primary 4GiB 100%

mkfs.fat -F32 -n BOOT /dev/nvme0n1p1

cryptsetup luksFormat /dev/nvme0n1p2          # type YES, then a passphrase
cryptsetup open /dev/nvme0n1p2 cryptroot
mkfs.xfs -L nixos /dev/mapper/cryptroot
```

4 GiB ESP is deliberate: `boot.loader.limine.maxGenerations = 10` keeps roughly
150 MB per generation in there.

### 2. Mount

```
mount /dev/mapper/cryptroot /mnt
mkdir -p /mnt/boot
mount /dev/nvme0n1p1 /mnt/boot
```

### 3. Generate hardware config, then clone this repo

```
nixos-generate-config --root /mnt

nix-shell -p git --run '
  git clone https://github.com/rikkichy/nixcfg /mnt/home/ri/nixcfg
'
cp /mnt/etc/nixos/hardware-configuration.nix /mnt/home/ri/nixcfg/
```

The clone lands as `root:root` because you are root here. You do not need to fix
that — `configuration.nix` reasserts `ri:users` on the tree at every boot,
before the desktop starts.

`hardware-configuration.nix` is **not** in this repo and never will be — it
describes *this machine's* filesystem and LUKS UUIDs, which do not exist until
step 1 has run. `flake.nix` imports it from the flake root, so it must sit next
to `flake.nix`. Ignore the `configuration.nix` that `nixos-generate-config`
also drops in `/mnt/etc/nixos`; yours comes from this repo.

### 4. Fill in the LUKS device name

`nixos-generate-config` already wrote the LUKS device into
`hardware-configuration.nix`, named after the mapping you opened in step 1:

```
boot.initrd.luks.devices."cryptroot".device = "/dev/disk/by-uuid/<uuid>";
```

`configuration.nix` only adds `allowDiscards` to it. Check the name matches:

```
boot.initrd.luks.devices."cryptroot".allowDiscards = true;
```

Without it, `services.fstrim` runs but no discard ever reaches the SSD through
the crypt layer.

**Use the name that is already there — do not invent a second one.** These are
attribute names, not device paths, so declaring `"luks-<uuid>"` alongside
`"cryptroot"` does not override it, it defines a *second* mapping of the same
partition. initrd then races two `systemd-cryptsetup@` units for
`/dev/nvme0n1p2`; the loser finds it busy, and when the loser is `cryptroot`,
`/dev/mapper/cryptroot` never appears and the boot hangs waiting for root. It
is a race, so it can boot fine several times before stranding you in the
initrd — recovery is a live USB, `cryptsetup open`, chroot, and edit. Verify
with `nix eval '.#nixosConfigurations.nix.config.boot.initrd.luks.devices'`
before rebooting; there must be exactly one entry.

### 5. **`git add` before installing — this is not optional**

Nix reads a git checkout through git. Files that are untracked are invisible to
it, so an uncommitted `hardware-configuration.nix` produces a confusing "file
not found" at eval even though the file is plainly sitting there.

```
cd /mnt/home/ri/nixcfg
git add -A
git -c user.email=ri@nix -c user.name=ri commit -m "Add hardware-configuration.nix"
```

### 6. Install

```
nixos-install --flake /mnt/home/ri/nixcfg#nix
```

It prompts for a **root** password at the end. Set one you remember.

### 7. Set a password for `ri` — you cannot sudo without it

The config declares `users.users.ri` with no password, so the account has none
after install. Autologin still works (greetd needs no password), but `sudo`
will reject you. Before rebooting, while still in the installer:

```
nixos-enter --root /mnt -c 'passwd ri'
```

Or after first boot: log in on a TTY as `root` and run `passwd ri`.
No password is set in the config on purpose — this repo is public.

### 8. Reboot

Flatpak apps install themselves a couple of minutes after you log in — Flathub
plus `org.vinegarhq.Sober` and `me.amankhanna.opendeck`. To add another, put it
in the list in `configuration.nix` and rebuild. If one is missing:

```
systemctl --user start flatpak-bootstrap
journalctl --user -u flatpak-bootstrap
```

There is still one thing you must do by hand:

At the first keyring prompt leave the password **empty** and confirm —
autologin types no password, so a non-blank keyring would stay locked forever.
At rest it is protected by LUKS.

Later changes are `sudo nixos-rebuild switch --flake path:/home/ri/nixcfg#nix`
(first build also writes `flake.lock` — commit it). After that first switch the
same thing is two menus away: press SUPER, type `hal`, pick **Halrune
Commander**, then **Nix** and "Rebuild and switch". The rest of that menu is
where you roll back, list generations and collect garbage.

Halrune Commander is the launcher's one entry for this machine's own tools —
the wallpaper pickers, the clipboard, emoji, the blue-light filter, the VPN,
the nix menu and the session menu. It is held at the top of the list, its rune
sits at the top of the bar as well, and both are coloured from the wallpaper
like everything else here. Clicking the one on the bar opens the same menu.
Each row shows the command beside it, so typing `wpp` in that menu picks the
wallpaper the same way typing it in a terminal does, and every one of them
still works as a command on its own.

## Wallpapers and colours

Every themed file on this machine is generated from a wallpaper —
`fuzzel.ini`, both `gtk.css`, the btop theme, the terminal palette and
`hypr/scheme/current.lua`. None of them can live in the repo, because the
colour engine rewrites them on every change and a read-only store symlink
would make that fail.

So a fresh install themes itself once, from a gradient shipped in
`dotfiles/`, and you get a coloured desktop without doing anything. The
`wallpaper-restore` user unit does this, and from then on it is what puts your
wallpaper back at every login — the shell itself remembers nothing, so without
it you would log in to a blank desktop. It reads
`~/.local/state/wallpaper/current`, which `wpp` writes.

`~/Pictures/Wallpapers` is created empty. **The collection itself is user
data — restore it from a backup**, it is far too large for a public repo.
`wpp` picks from that folder and re-themes everything; with the folder still
empty it falls back to the shipped gradient rather than refusing to run.

`awpp` is the same picker for video wallpapers, over
`~/Videos/Animated Wallpapers` — also created empty, also user data. It plays
the video over the desktop and takes the colours from a frame of it, so
everything is themed the same way a still image would theme it. Picking a
still with `wpp` puts the video away.

## VPN (mihomo)

`services.mihomo` runs the tunnel as a system service, with the dashboard at
**<http://127.0.0.1:9090/ui/>** — that is where you pick a node. It starts at
boot; there is no app to launch.

### Turning it off

**`SUPER + SHIFT + V`** opens a picker over the active subscription's live node
list, fastest first. `DIRECT`, `AUTO`, **Primary**, and **Quattro** stay pinned
at the top, so the same picker switches subscriptions and nodes. It is also
available as `vpnp`, or through the CLI beneath it:

```
vpn                              # toggle
vpn on                           # restore the active subscription
vpn off                          # direct connection
vpn status                       # current node, AUTO, or DIRECT
vpn subscription                 # active subscription name
vpn subscription primary         # switch to Primary
vpn subscription quattro         # switch to Quattro
vpn list                         # active subscription's nodes and latency
vpn use <pattern>                # fastest matching node in that subscription
vpn select <name>                # exact node in that subscription
vpn ip                           # exit IP and country
```

Each subscription keeps its own AUTO/manual node selection in mihomo's cache.
Off records the active subscription in
`~/.local/state/vpn/last-subscription`, so `vpn on` restores the same provider
and that provider restores its own node.

`vpn use` takes a case-insensitive regex, not a node name — `vpn use швец`
picks the fastest Swedish node. **Match on the flag emoji** (`vpn use 🇸🇪`) when
you want something durable: node names carry numbering, `WlFl`/`LTE` suffixes
and trailing spaces that providers change without notice.

The dashboard exposes the same hierarchy: **PROXY** chooses **PRIMARY**,
**QUATTRO**, or **DIRECT**; each subscription group chooses its own AUTO group
or a node. DIRECT still sends traffic through the TUN and DNS hijack, but mihomo
dials out the physical interface, so nothing has to be stopped.

**All choices stick across reboots** (`profile.store-selected`, cached in
`/var/lib/private/mihomo/cache.db`). DIRECT remains DIRECT until explicitly
changed, and both subscription groups retain their independent node choices.
Deleting `cache.db` selects Primary and its AUTO group.

To stop the service outright — `systemctl stop mihomo` — you do not need it for
this, and it also takes the DNS hijack down with it. DIRECT is the toggle you
want.

The config lives in `dotfiles/mihomo.yaml`. Three values cannot: both
subscription URLs are credentials and the device id is machine-specific, while
this repo is public. They live in `/etc/mihomo/` and are spliced into the config
at boot.

### On a fresh install

Write both subscription URLs **before the first rebuild** — `mihomo-config`
refuses to run without either one, and mihomo will not start:

```
sudo install -d -m 755 /etc/mihomo
printf '%s\n' 'https://…primary subscription link…' | sudo tee /etc/mihomo/subscription.url
printf '%s\n' 'https://…Quattro subscription link…' | sudo tee /etc/mihomo/quattro.url
sudo chmod 600 /etc/mihomo/subscription.url /etc/mihomo/quattro.url
```

If you have a backup of `/etc/mihomo/hwid` from the installed system, restore it
in the same step. Otherwise it is seeded from `/etc/machine-id` on first boot,
which a fresh install regenerates — and a panel can cap how many devices a
subscription may have, so a reinstall may consume another slot while the VPN
stays dead until that device is freed in the panel. All three files are `0600`;
back up the set, not just the links.

Forgot, and rebuilt anyway? Nothing is broken — write the missing file and:

```
sudo systemctl restart mihomo
```

`mihomo-config` is pulled in as a dependency, so that re-runs it. Then:

```
systemctl status mihomo
journalctl -u mihomo -f
```

Two settings in `configuration.nix` are tied to `tun.device: mihomo` inside that
file — `networking.firewall.trustedInterfaces` and
`networking.networkmanager.unmanaged`. Rename the device in one place and all
three need to change together.

If the VPN looks connected but traffic is not tunnelled, do not trust the
dashboard — check that the interface actually has its IPv4 address:

```
ip -br addr show mihomo
```

A link that is `UP` with only a link-local v6 address is a tunnel that is not
carrying anything.

## Telegram proxy (tg-ws-proxy)

`Flowseal/tg-ws-proxy` is packaged from source in `pkgs/tg-ws-proxy.nix` and
pulled in as a `flake = false` input, so the nightly `autoUpgrade` bumps it
like everything else.

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

## Layout

| Path | What |
|---|---|
| `flake.nix` | inputs + `nixosConfigurations.nix` |
| `configuration.nix` | system: boot, GPU, Hyprland, gaming, packages |
| `home.nix` | home-manager: wayle, theming, dotfiles, web apps |
| `hypr/` | Hyprland Lua config, symlinked live into `~/.config/hypr` |
| `dotfiles/` | verbatim files copied in by `home.nix` (plus `mihomo.yaml`, used by `configuration.nix`) |

`vhelper` and `openwave` are separate flake inputs and live in their own
repos (`rikkichy/vhelper`, `rikkichy/openwave`) — edit them there, not here.

## Two rules that are easy to break

**The colour engine owns a set of files at runtime.** Every time the wallpaper
changes, `matugen` rewrites `fuzzel.ini`, `btop/themes/wallpaper.theme`,
`nvtop/nvtop.colors`, `gtk-3.0/gtk.css`, `gtk-4.0/gtk.css`, both `thunar.css`,
`qtengine/scheme.colors` and `hypr/scheme/current.lua`. Home-manager files are
read-only store symlinks, so **do not** put any of those under
`xdg.configFile` — every colour change would start failing. This is also why
home-manager's `gtk` module is not used: it emits `gtk-4.0/gtk.css` too.

**Change the colours by editing templates, not the generated files.** The
templates are in `dotfiles/matugen/templates/` and are tracked; anything you
type into the files listed above is gone at the next wallpaper. Run `wpp` to
re-render after editing a template.

**Wayle's settings are not in this repo.** `config.toml` is managed here, but
anything changed in the wayle GUI or with `wayle config set` lands in
`runtime.toml` beside it — and `runtime.toml` wins where the two overlap. So a
value set here that has ever been set at runtime simply does not apply;
`wayle config reset <field>` is what releases it. Those live settings are not
restored by a reinstall.

## Auto-updates

`system.autoUpgrade` builds daily and **stages** for next boot (`operation =
"boot"`), so a kernel or NVIDIA bump never disturbs a running session. Bad
update → pick the previous generation in the Limine menu.
Watch it with `journalctl -u nixos-upgrade.service`.

`--flake /home/ri/nixcfg` reads the tree through git, so the rule is about
tracking, not committing. Editing a file that is already in git works without
committing. A **new** file is invisible until `git add` — no error, it is just
silently ignored, the same trap as step 5. `git add -A` before rebuilding, or
use `path:/home/ri/nixcfg` to bypass git entirely.
