# nixcfg

NixOS config for `nix` — 9950X3D / RTX 3090 / LUKS / Hyprland + Caelestia.
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

Later changes are `sudo nixos-rebuild switch --flake /home/ri/nixcfg#nix`
(first build also writes `flake.lock` — commit it).

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
| `home.nix` | home-manager: Caelestia, dotfiles, web apps |
| `hypr/` | Hyprland Lua config, symlinked live into `~/.config/hypr` |
| `dotfiles/` | verbatim files copied in by `home.nix` |

`vhelper` and `openwave` are separate flake inputs and live in their own
repos (`rikkichy/vhelper`, `rikkichy/openwave`) — edit them there, not here.

## Two rules that are easy to break

**Caelestia owns a set of files at runtime.** `caelestia scheme set …`
rewrites `fuzzel.ini`, `btop/themes/caelestia.theme`, `htop/htoprc`,
`cava/config`, `gtk-3.0/gtk.css`, `gtk-4.0/gtk.css`, `qtengine/config.json`,
`nvtop/nvtop.colors` and `hypr/scheme/current.lua`. Home-manager files are
read-only store symlinks, so **do not** put any of those under
`xdg.configFile` — every colour change would start failing. This is also why
home-manager's `gtk` module is not used (it emits `gtk-4.0/gtk.css` and
fights Caelestia over the same dconf keys).

**`shell.json` is declarative now.** `programs.caelestia.settings` in
`home.nix` writes `~/.config/caelestia/shell.json` as a read-only symlink, so
settings changed in the Caelestia GUI can no longer be saved. Change them
here and rebuild. Per-monitor overrides in
`~/.config/caelestia/monitors/<name>/` stay writable.

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
