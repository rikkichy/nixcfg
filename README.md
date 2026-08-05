# nixcfg

NixOS config for `nix` — 9950X3D / RTX 3090 / LUKS / Hyprland + Caelestia.
Migrated off CachyOS. Clone to **`/home/ri/nixcfg`** — that exact path is
hardcoded in two places (`system.autoUpgrade.flake`, and the Hyprland
`mkOutOfStoreSymlink` in `home.nix`).

## Install order

1. Install NixOS. LUKS on the NVMe, ESP ≥ 2 GB (`boot.loader.limine.maxGenerations = 10`
   keeps ~150 MB per generation in there).
2. `git clone <this repo> /home/ri/nixcfg`
3. **Copy in the generated `hardware-configuration.nix`.** It is not in this
   repo — it is machine-specific and produced by `nixos-generate-config`.
   `flake.nix` imports it, so evaluation fails until it exists.
4. In `configuration.nix`, uncomment `boot.initrd.luks.devices."luks-XXXX".allowDiscards`
   and paste the real device name from `hardware-configuration.nix`. Without
   it `services.fstrim` runs but no discard ever reaches the SSD through the
   crypt layer.
5. `sudo nixos-rebuild boot --flake /home/ri/nixcfg#nix` (first build also
   writes `flake.lock` — commit it).
6. Reboot, then one time only:
   ```
   flatpak remote-add --user --if-not-exists flathub \
     https://flathub.org/repo/flathub.flatpakrepo
   flatpak install --user flathub org.vinegarhq.Sober
   flatpak install --user flathub me.amankhanna.opendeck
   ```
7. At the first keyring prompt, leave the password **empty** and confirm —
   autologin types no password, so a non-blank keyring would stay locked
   forever. At rest it is protected by LUKS.

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

Once this is a git repo, `--flake /home/ri/nixcfg` evaluates **committed
content only**. An uncommitted edit is not an error — the nightly build just
silently rebuilds the last commit. Commit, or use `path:/home/ri/nixcfg`.
