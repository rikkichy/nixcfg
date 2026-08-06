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
chown -R 1000:100 /mnt/home/ri/nixcfg
```

That `chown` is **not** cosmetic. You are root in the installer, so the clone
lands as `root:root` and `ri` cannot write to it. `home.nix` maps `hypr/` into
`~/.config/hypr` with `mkOutOfStoreSymlink` precisely so Caelestia can rewrite
`hypr/scheme/current.lua` at runtime (see *Two rules that are easy to break*).
Leave it root-owned and that write silently fails — `hyprland.lua` cannot
bootstrap `current.lua` from `default.lua` on first start, `require` of it
fails, and because `variables.lua` interpolates colours into strings the whole
`variables` module comes back empty. Every `vars.*` is then `nil`, which throws
a dozen `hl.*` argument errors and makes `keybinds.lua` abort partway, silently
dropping most of the binds. `caelestia scheme set` never works either.
`1000:100` is `ri:users`; the account does not exist yet at this point, so
`chown ri:users` would fail here.

`hardware-configuration.nix` is **not** in this repo and never will be — it
describes *this machine's* filesystem and LUKS UUIDs, which do not exist until
step 1 has run. `flake.nix` imports it from the flake root, so it must sit next
to `flake.nix`. Ignore the `configuration.nix` that `nixos-generate-config`
also drops in `/mnt/etc/nixos`; yours comes from this repo.

### 4. Fill in the LUKS device name

Open `/mnt/home/ri/nixcfg/configuration.nix`, find the commented
`boot.initrd.luks.devices` line, uncomment it and paste the real name — the
UUID is in the `hardware-configuration.nix` you just copied:

```
boot.initrd.luks.devices."luks-<uuid>".allowDiscards = true;
```

Without this, `services.fstrim` runs but no discard ever reaches the SSD
through the crypt layer.

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

### 8. Reboot, then one time only

```
flatpak remote-add --user --if-not-exists flathub \
  https://flathub.org/repo/flathub.flatpakrepo
flatpak install --user flathub org.vinegarhq.Sober
flatpak install --user flathub me.amankhanna.opendeck
```

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

Once this is a git repo, `--flake /home/ri/nixcfg` reads the tree **through
git**, and the rule is about *tracking*, not committing:

| State | Seen by Nix? |
|---|---|
| tracked, committed | yes |
| tracked, edited but uncommitted | yes — the dirty working tree is used, with a `warning: Git tree is dirty` |
| **untracked** | **no** — silently absent, as if the file did not exist |

So an uncommitted edit to a file already in git does take effect on the next
rebuild. A **new** file does not, until `git add`. That is the same trap as
step 5 above, and it fails the same way: not an error, just a build that
quietly ignores the file. `git status` before rebuilding, or use
`path:/home/ri/nixcfg`, which ignores git entirely and reads the directory.
