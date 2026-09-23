# nix — NixOS

[Handbook](../handbook.md) · [macOS host](ne.md)

Ryzen 9950X3D / RTX 3090 / LUKS / Hyprland + Quickshell, user `ri`.
Source paths below are relative to `/etc/nixos`; run repository commands there
unless an installation step specifies otherwise.

## Contents

- [Installation](#install-step-by-step)
- [Rebuilds and desktop tools](#rebuilds-and-desktop-tools)
- [Wallpapers and colours](#wallpapers-and-colours)
- [Theme ownership rules](#two-rules-that-are-easy-to-break)
- [Expressive desktop shell](#expressive-desktop-shell)
- [VPN and private inputs](#vpn-mihomo)
- [Telegram proxy](#telegram-proxy-tg-ws-proxy)
- [RGB lighting](#rgb-lighting)
- [Auto-updates](#auto-updates)
- [Touch-only disk unlock](#touch-only-disk-unlock)
- [Limine recovery](#limine-recovery-with-a-zero-timeout)
- [Touch-only sudo](#touch-only-sudo-with-password-fallback)

## Install, step by step

For guided host/disk selection and separately approved YubiKey enrollment,
use the [interactive Linux installer](../handbook.md#interactive-linux-installer).
The manual procedure below is for the `nix` desktop.

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
mv /mnt/etc/nixos /mnt/etc/nixos.generated

nix-shell -p git --run '
  git clone https://github.com/rikkichy/nixcfg /mnt/etc/nixos
'
cp /mnt/etc/nixos.generated/hardware-configuration.nix /mnt/etc/nixos/hosts/nix/hardware.nix
```

The clone lands as `root:root` because you are root here. You do not need to fix
that — `hosts/nix/storage.nix` reasserts `ri:users` on the tree at every boot,
before the desktop starts.

`hosts/nix/hardware.nix` is tracked and specific to this machine.
For another host, create its own `hosts/<name>/` configuration and verify every
disk/boot setting. `hosts/nix/default.nix` imports this desktop's hardware.
Ignore the generated `/mnt/etc/nixos.generated/configuration.nix`; the system module
comes from this repo.

### 4. Fill in the LUKS device name

`nixos-generate-config` already wrote the LUKS device into
the generated hardware configuration, copied to `hosts/nix/hardware.nix`, named after the mapping you opened in step 1:

```
boot.initrd.luks.devices."cryptroot".device = "/dev/disk/by-uuid/<uuid>";
```

`hosts/nix/boot.nix` adds discard support; `common/modules/nixos-yubikey.nix`
adds systemd FIDO discovery to that same mapping. Neither enrolls the disk.
Keep the name `cryptroot` consistent.
The retained passphrase remains the fallback; see **Touch-only disk unlock**
below before enrolling a token.

Without `allowDiscards`, `services.fstrim` runs but no discard reaches the SSD
through the crypt layer.

**Use the name that is already there — do not invent a second one.** These are
attribute names, not device paths, so declaring `"luks-<uuid>"` alongside
`"cryptroot"` does not override it, it defines a *second* mapping of the same
partition. initrd then races two `systemd-cryptsetup@` units for
`/dev/nvme0n1p2`; the loser finds it busy, and when the loser is `cryptroot`,
`/dev/mapper/cryptroot` never appears and the boot hangs waiting for root. It
is a race, so it can boot fine several times before stranding you in the
initrd — recovery is a live USB, `cryptsetup open`, chroot, and edit. Verify
with `nix eval 'path:.#nixosConfigurations.nix.config.boot.initrd.luks.devices'`
before rebooting; there must be exactly one entry for this root partition.

### 5. Review source paths before installing

Nix's Git flake view omits untracked files. Review and stage only intended
public configuration/ciphertext paths, never use a blanket add around secret
provisioning. `path:` includes untracked and ignored files, so **no plaintext,
identity descriptor, or private key may be staged anywhere inside the checkout**.

```
cd /mnt/etc/nixos
git add hosts/nix/hardware.nix
```

### 6. Install

```
nixos-install --flake /mnt/etc/nixos#nix
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
in the list in `hosts/nix/modules/system/flatpak.nix` and rebuild. If one is missing:

```
systemctl --user start flatpak-bootstrap
journalctl --user -u flatpak-bootstrap
```

There is still one thing you must do by hand:

At the first keyring prompt leave the password **empty** and confirm —
autologin types no password, so a non-blank keyring would stay locked forever.
At rest it is protected by LUKS.

## Rebuilds and desktop tools

Later changes are `sudo nixos-rebuild switch --flake path:/etc/nixos#nix`
(first build also writes `flake.lock` — commit it). Press META+ALT and select
**Nix maintenance**: the parent lists generations in a held terminal,
and native actions include **Rebuild and switch**, rollback and garbage collection.
`nh os switch` is the terminal alternative: `programs.nh.flake` sets
`NH_FLAKE=/etc/nixos` declaratively. No custom Fish export is needed.
Run it as your normal user; it requests elevation as needed. An explicit
`NH_OS_FLAKE` takes precedence for OS commands.

The live `~/.config/hypr` symlink targets `hosts/nix/dotfiles/ricing/hypr/`.
If it points elsewhere, switch the host configuration before reloading Hyprland.
Keep the locally generated `scheme/current.lua` in that directory; it is ignored
by Git and must remain writable.

Wallpaper, animated wallpaper, clipboard, emoji, blue-light filter, VPN,
network recovery and session tools are available through META+ALT.
Short commands such as `wpp`, `clipp`, `vpnp` and `troubleshootp` remain searchable there.
Bare META and the palette-tinted rune on the bar open the apps-only launcher.
There is no `nixp` shell command; maintenance operations are desktop actions.
**META + ALT** opens Fuzzel on a directory containing only these tools and their
native actions. Search starts empty and matches tool names normally. Press the
chord again to dismiss it. Tools and desktop actions stay hidden from the main
launcher using native desktop-entry visibility.
Clipboard capture is supervised by Home Manager. Start a fresh graphical session
after applying this configuration to avoid overlapping old unmanaged watchers.

**Network recovery acts immediately, without confirmation.** Its default action
force-kills Helium and Discord, clears failed network-route backoff, cleans
Discord's disposable caches, and refreshes system DNS/connections. Apps remain
closed; nothing restores their sessions. Cookies, settings and persistent
application data are preserved, but unsaved work can be lost.
Use its native actions for individual scopes, or
`network-reset [all|system|helium|discord|reconnect]` in a terminal.
`reconnect` briefly disconnects Ethernet; ordinary system reset keeps the link,
VPN choice and fake-IP mappings intact. `troubleshootp` runs the same command
in a held terminal. No post-reset connectivity checks run.

## Wallpapers and colours

Runtime palettes are generated from a wallpaper: `fuzzel/colors.ini`, both
`gtk.css`, the btop theme, terminal colours and `hypr/scheme/current.lua`.
Their templates are tracked, but generated destinations must remain writable.
Fuzzel's static `fuzzel.ini` is managed separately and includes its palette.

So a fresh install themes itself once, from a gradient shipped in
`hosts/nix/dotfiles/ricing/`, and you get a coloured desktop without doing anything. The
`wallpaper-restore` user unit does this, and from then on it is what puts your
wallpaper back at every login — the shell itself remembers nothing, so without
it you would log in to a blank desktop. It reads
`~/.local/state/wallpaper/current`, which the wallpaper pipeline writes.
Restoration regenerates every palette from the recorded image, so existing
palette files do not hide template changes or missing outputs.

**Wallpaper collections are user data — restore them from a backup.**
`wpp` reads `~/Pictures/Wallpapers`; a missing or empty directory applies the
shipped gradient. Collection directories are not created by the configuration.

`awpp` reads `~/Videos/Animated Wallpapers` and reports an empty collection.
It starts mpvpaper after extracting a valid frame, then derives the desktop colours
and cursors from that frame without holding up playback. A theme-generation
failure is reported but does not stop the selected video. Picking a still with
`wpp` displays the image and stops the video before generating colours and cursors.
At login, animated playback does not wait for theme restoration.

Both pickers generate missing thumbnails with at most four workers and reuse
fresh cache entries. Cursor rendering also reuses unchanged, complete outputs;
changing the accent or renderer, or losing a cursor file, triggers regeneration.

## Two rules that are easy to break

**The colour engine owns a set of files at runtime.** Every time the wallpaper
changes, `matugen` rewrites `fuzzel/colors.ini`, `btop/themes/wallpaper.theme`,
`nvtop/nvtop.colors`, `gtk-3.0/gtk.css`, `gtk-4.0/gtk.css`, both `thunar.css`,
`qtengine/scheme.colors`, `quickshell/colors.json` and `hypr/scheme/current.lua`. Home-manager files are
read-only store symlinks, so **do not** put any of those under
`xdg.configFile` — every colour change would start failing. This is also why
home-manager's `gtk` module is not used: it emits `gtk-4.0/gtk.css` too.

**Change the colours by editing templates, not the generated files.** The
terminal and btop templates are in `common/dotfiles/matugen/templates/`; the
Linux-only templates are in `hosts/nix/dotfiles/ricing/matugen/templates/`. Anything you type
into the generated files is gone at the next wallpaper. Run `wpp` to re-render
after editing a template.

Home Manager installs the template configuration at `~/.config/matugen/config.toml`,
with noninteractive source-color selection. Direct Matugen commands render palettes;
`wpp`/`awpp` also apply terminal and cursor updates, set the wallpaper, and keep
wallpaper records. Those steps stay outside Matugen hooks because failed hooks do not
produce a failing exit status. `services.awww` owns the daemon; its readiness
check orders wallpaper restoration after the socket is usable.

## Expressive desktop shell

`quickshell.service` runs the pinned Quickshell package with
`hosts/nix/dotfiles/ricing/quickshell/`. The unit's restart trigger includes the QML store path,
so a configuration rebuild updates the unit as well as its files. Apply with the
normal `nixos-rebuild switch --flake path:/etc/nixos#nix`; no manual
notification daemon or wallpaper daemon should run alongside the managed ones.

The left rail groups a folded tray toggle, notifications, the centered
clock/calendar, and occupied workspaces, in that order. Empty workspaces are
hidden; occupied ordinary and special workspaces appear beneath the clock.
Tray icons expand vertically upward without moving the clock or overlapping
the notification button; Escape or the toggle folds them away.
The folded tray and notification buttons both occupy 56 × 48 logical pixels.
Special workspaces use Google's official Material Symbols Rounded:
`communication` uses `chat`, `music` uses `music_note`, and other special
workspaces use `layers`. Bundled SVGs and their Apache-2.0 license live in
`hosts/nix/dotfiles/ricing/quickshell/icons/`. Icons follow workspace names rather than temporary IDs;
ordinary workspaces retain their numeric labels.
Microphone, volume, network and Bluetooth remain at the bottom.
Each of those buttons opens only its own controls: microphone input,
sound output/media, internet connections, or Bluetooth devices. They use native
PipeWire, MPRIS, NetworkManager and Bluetooth models. Network credentials use
`nmtui`, pairing uses Blueman, and detailed audio routing uses Pavucontrol.
Right-clicking microphone or sound toggles mute; Super+K opens Sound.
Audio popovers place the device dropdown beside the mute switch in the header,
above a full-width slider. On means unmuted; long device names elide.
Wallpaper, night-light and power remain available through the launcher tools
`wpp`, `awpp`, `sunp` and `powermenu`; DND lives in notification history.

```sh
quickshell -c expressive ipc call desktop toggle microphone
quickshell -c expressive ipc call desktop toggle sound
quickshell -c expressive ipc call desktop toggle network
quickshell -c expressive ipc call desktop toggle bluetooth
quickshell -c expressive ipc call desktop toggle notifications
quickshell -c expressive ipc call desktop toggle calendar
quickshell -c expressive ipc call desktop close
quickshell -c expressive ipc call desktop dismissAll
quickshell -c expressive ipc call desktop dnd
quickshell -c expressive ipc call desktop hide
quickshell -c expressive ipc call desktop reveal
quickshell -c expressive ipc call desktop status
```

IPC selects the same configuration as the service. `reveal` avoids the CLI's
reserved `show` subcommand. Escape and clicking outside dismiss panels.
Calendar, notifications and device controls are compact popovers next to their
trigger, centered vertically on it where screen bounds allow. Hyprland handles
their subtle 96%–100% pop-in and fade, reversed on close; QML keeps a fixed size.
Calendar height follows its contents; notification history and device controls
scroll within capped heights. Keyboard IPC uses the corresponding rail button
on the focused monitor as its origin. No full-screen overlay is created.
Reduced-motion mode disables this compositor animation as well.
Notification bodies are plain text; DND suppresses popups, not history.
History is memory-only, bounded to 100 entries, and clears on shell restart
or QML reload. Expired notifications remain readable but their actions are
disabled; transient notifications do not enter history. Critical and explicit
zero-timeout notifications remain until closed. An identical replacement
notification cannot restart its timeout because Quickshell 0.3.1 exposes no
update signal when every field is unchanged.

`awww.service` owns still wallpapers independently of the shell;
`wallpaper-restore.service` waits for its socket and restores the recorded
image. Matugen renders writable `quickshell/colors.json`; Quickshell watches it
and keeps the last valid palette on malformed writes. Missing colors use a
complete dark fallback. Set `QS_REDUCED_MOTION=1` in the user service environment
to disable shell animations.

### Material 3 Expressive design basis

The [official introduction](https://m3.material.io/blog/building-with-m3-expressive)
describes an evolution of M3, not M4. Its fourteen component additions/updates
are app bars, button groups, common buttons, extended FABs, FAB menus, FABs,
icon buttons, loading indicators, navigation bars, navigation rails, progress
indicators, sliders, split buttons and toolbars. Its style updates are spatial
and effects springs, emphasized typography, 35 decorative shapes with morphing,
and richer dynamic color schemes.

Its seven tactics map to this desktop as follows:

| Tactic | Shell application |
|---|---|
| Vary shapes | selected workspace pills, rounded cards and pressed corner morphs |
| Rich, nuanced color | wallpaper-derived primary, secondary and tertiary role pairs |
| Guide with typography | bold rounded headings, readable labels and the stacked rail clock |
| Contain related content | separate microphone, sound, network and Bluetooth popovers |
| Fluid, natural motion | spatial springs for controls; compositor pop-in/fade for popovers |
| Flexible components | per-monitor rails, scrollable controls and device-dependent actions |
| Combine tactics for hero moments | media artwork and playback controls in the sound popup |

The article cautions against making essential actions too small, insufficient
contrast, ungrouped information, and too many hero moments. Controls provide
48-pixel hit areas, focus indicators, keyboard operation and accessible names.
Qt dimensions and spring coefficients are desktop adaptations, not claims of
pixel-identical Android tokens. The shell uses relevant components rather than
inserting every FAB/loading shape into a desktop that has no use for it.

Tray motion uses Material's [Expressive spring tokens](https://raw.githubusercontent.com/androidx/androidx/androidx-main/compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/tokens/ExpressiveMotionTokens.kt):
default spatial (stiffness 380, damping ratio 0.8) for expansion/shape, default
effects (1600, 1.0) for opacity, and fast spatial (800, 0.6) for icon rotation.
The coefficients are converted for Qt's native 16ms spring integrator; geometry
and opacity remain separate so transparency does not bounce. The toggle uses
the stock `pan-up` theme icon. Occupied-workspace selection retains its animated
48-to-56-pixel size and rounded-shape transition.

Implementation reference: [Quickshell v0.3.1](https://git.outfoxxed.me/quickshell/quickshell/src/tag/v0.3.1),
including its native Hyprland IPC and service APIs. The flake applies a
socket-lifetime correction required with the pinned Qt.

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

The public template is `hosts/nix/dotfiles/bypasses/mihomo.yaml`. `mihomo-config` serializes the
three private strings into a root-only `/run/mihomo/config.yaml`; Mihomo receives
it through systemd `LoadCredential`, retaining `DynamicUser`. SOPS scalar values
are preserved exactly; legacy file inputs retain their existing whitespace
normalization. Values are never Nix evaluation/build inputs. Mihomo's private
provider/state files can also contain credentials; keep those outside Git.

### Private inputs and first provisioning

`.secrets/nix/personal.yaml` contains the encrypted inputs, and the nested policy
authorizes the administrator YubiKey and host key. SOPS supplies the active
runtime inputs. Keep `/etc/mihomo/subscription.url`, `/etc/mihomo/quattro.url`,
and `/etc/mihomo/hwid` for rollback. On an unprovisioned checkout without
ciphertext these are the inputs instead. All three must exist, be nonempty, and be
root-owned mode `0600`; HWID is not generated automatically. Restore them from
the installed system or a protected backup, using an editor/file transfer that
does not expose values in terminal output, command arguments, or shell history.
For a genuinely new subscription, obtain its intended device identity from the
operator/provider rather than inventing a migration value.

| Path | Contents |
| --- | --- |
| `.secrets/.sops.yaml` | Public recipient policy, matching `^nix/personal\.yaml$` |
| `.secrets/nix/personal.yaml` | Operator-created ciphertext for host `nix`, intended for Git |
| `.secrets/nix/sops.nix` | Host secret declarations and conditional cutover |
| `/var/lib/sops-nix/key.txt` | Root-only native host age private key |
| `~/.config/sops/age/yubikey.txt` | Administrator PIV identity descriptor, outside Git |
| `/run/secrets/mihomo/{primary_url,quattro_url,hwid}` | Root-owned mode `0400` decrypted runtime inputs |
| `/run/mihomo/config.yaml` | Root-only serialized runtime configuration |

The administrator YubiKey and host recipients are **alternatives in one
recipient group**, not a threshold scheme. The host decrypts unattended;
the administrator uses a PIV YubiKey touch. There is deliberately no independent
recovery recipient: losing both private keys loses access to the ciphertext.
The operator accepts this risk. Neither the account password nor the LUKS
passphrase automatically decrypts SOPS.

First provisioning is an operator procedure, not something a rebuild does:

1. Establish the administrator PIV identity as described below and obtain its
   public recipient. Keep its identity descriptor outside the checkout.
2. Retain an existing host key. Only if none exists, create one in a root shell
   with `umask 077`, a root-owned `0700` `/var/lib/sops-nix` directory, and
   `age-keygen -o /var/lib/sops-nix/key.txt`. Never overwrite an established key.
   Keep it `root:root`, mode `0600`; obtain only its public recipient with
   `age-keygen -y /var/lib/sops-nix/key.txt`. Automatic key generation is disabled.
3. Set the policy rule's `age` value to the two real public recipients
   (administrator and host), comma-separated. Do not copy example keys or
   create separate `key_groups`. The rule is relative to `.secrets/`.
4. In a protected editor, create a YAML mapping `mihomo` containing the string
   keys `primary_url`, `quattro_url`, and `hwid`. Import the existing effective
   values without displaying them. In particular preserve the **exact meaningful
   HWID**, not this installation's machine-id. The legacy renderer removed
   whitespace; distinguish file framing from the actual established value and
   privately compare the imported value with the working device identity.
   Do not perform blind whitespace replacement on the SOPS strings.
5. Encrypt using the nested policy, writing only ciphertext into the checkout.
   For `sops edit`, set `TMPDIR` to a private `0700` directory outside the
   checkout, preferably tmpfs, and disable editor swap, backup, and persistent
   undo files. Never create an unencrypted `personal.yaml` in the repo first.
   Use the commands below to create/edit the encrypted document; enter secrets
   only in the protected editor, not in command arguments.
6. Independently test administrator and host decryption without
   printing plaintext. Privately compare all imported values, especially HWID.
   Merely adding `personal.yaml` selects SOPS at the next evaluation: finish
   these tests and provision the host key **before activation**.
7. Review/stage the policy, ciphertext, and module explicitly. Run quick/full
   validation and a build, then request activation. Check runtime permissions,
   start ordering, a controlled changed-secret restart, and provider behavior.
   Keep all `/etc/mihomo` inputs and the known-working generation until cutover
   and rollback have been exercised.

`mihomo-config` has no persistent completed state and reruns on each Mihomo
start, after its required `sops-install-secrets.service` in SOPS mode. Secret
installation uses sops-nix's systemd activation mode. SOPS changes request a
Mihomo restart so `LoadCredential` picks up the new rendered file; updating its
source alone cannot update a running credential. After repairing missing
inputs, `sudo systemctl restart mihomo` rerenders them.
Check service state without dumping configuration or provider URLs to logs.

### PIV touch-only administration and nested SOPS commands

PIV via `age-plugin-yubikey` is separate from the FIDO credentials used by boot
and sudo. Inspect the model, firmware, management setup, and occupied compatible
PIV slots first; absence of a certificate alone does not prove a slot unused.
Check installed `age-plugin-yubikey --help`. For an approved **new key** in a
confirmed-unused slot, request `--generate --serial SERIAL --slot SLOT
--pin-policy never --touch-policy always` and save its output only to
`~/.config/sops/age/yubikey.txt` with restrictive permissions. `SERIAL` and
`SLOT` mean the inspected device and slot, not literal values to copy.

Generation may require management authorization or a PIN. The plugin may also
change default PIN/PUK/management settings during setup: review that behavior
before authorizing it. Never reset an applet, clear a FIDO PIN, or weaken other
credentials. PIN/touch policy is fixed at generation/import; an existing
PIN-requiring PIV key needs a separately authorized replacement, not an edited
descriptor. FIPS policies can prohibit `never`; report incompatibility rather
than silently choosing `once` or cached touch. See the
[plugin documentation](https://github.com/str4d/age-plugin-yubikey#configuration)
and [Yubico policy restrictions](https://docs.yubico.com/yesdk/users-manual/application-piv/pin-touch-policies.html).

Run SOPS as the administrator, not root merely to borrow the host key. In Bash:

```bash
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/yubikey.txt"
umask 077
export TMPDIR="$(mktemp -d /run/user/"$(id -u)"/sops-edit.XXXXXX)"
# From the repository root; also creates a new encrypted document via the editor:
sops --config .secrets/.sops.yaml edit .secrets/nix/personal.yaml
# Equivalent after cd .secrets:
sops --config .sops.yaml edit nix/personal.yaml
# Only after a reviewed change to real recipients, using an authorized identity:
sops --config .sops.yaml updatekeys nix/personal.yaml
```

The last two commands are alternatives run **inside `.secrets/`**, not subsequent
root-directory commands. Remove the private temporary directory after the editor
has exited and no recovery files are needed. SOPS searches for config upward,
never downward from the repository root; do not rely on it finding the child
policy. Changing policy alone does not update existing ciphertext.

For an independent decryption test use a clean test environment with no other
age identities, SOPS key environment variables/commands, SSH keys, or GPG
keyring; an explicit `SOPS_AGE_KEY_FILE` alone is not proof of isolation.
Leave unused identity variables/commands unset, not empty. In that isolated
environment, use `sops --config .secrets/.sops.yaml decrypt
.secrets/nix/personal.yaml > /dev/null` from the repository root, not a command that
prints plaintext. Replug the YubiKey before the
administrator-only test: no routine PIN, touch required, no-touch must not
complete decryption. Repeat with only the root host key and no token. Do not
record these checks as passed until actually performed. Touch proves presence, not identity;
the host and any compromised secret-consuming process can access plaintext.

### Reinstall, replacement, revocation, and rollback

On a replacement machine, restore or reconstruct the **existing** PIV descriptor
with `age-plugin-yubikey --identity --serial SERIAL --slot SLOT`; do not run
`--generate` as recovery. Create a new root-only native host age key, add its
public recipient alongside the administrator in the policy, then use an
already-authorized identity to run:

```bash
sops --config .secrets/.sops.yaml updatekeys .secrets/nix/personal.yaml
```

Test the new host alone, with the YubiKey removed and all other identities
excluded, before unattended provisioning. Restore the same URLs and HWID; do
not regenerate HWID from the new machine-id. Successful decryption does not
guarantee provider acceptance or simultaneous-device limits. Generate/verify
the new machine's hardware configuration. Its disk enrollment and sudo mapping
are separate procedures. Keep the old host recipient until explicit retirement.

If the host age key is lost, use the administrator YubiKey to authorize a
replacement host key; a rebuild cannot regenerate access to existing ciphertext.
If the YubiKey is lost, use an authorized host to add/test a replacement
administrator recipient. There is no third decryption route if both are lost.

Recipient removal with `updatekeys` changes who can unwrap the current SOPS
data key; it is not data-key rotation (`sops rotate --in-place`) or revocation
of subscription credentials at the provider. For compromise, review all three:
remove the compromised recipient and update ciphertext, rotate its data key with
the remaining recipients, and replace exposed application credentials. Old Git
revisions remain decryptable by old authorized recipients. A lost token also
needs separate removal of its exact sudo registration and LUKS token/keyslot,
after fallback/replacement tests; never wipe all slots or an entire applet.

For SOPS cutover rollback, use a known-working system generation with retained
`/etc/mihomo` inputs. For source rollback, restore the matched module,
policy/ciphertext, renderer, and imports from the chosen revision; preserve host
private keys. Removing ciphertext alone is not a revocation procedure. A pure
layout move preserves ciphertext bytes/metadata and runtime identities: compare
checksums, adapt relative paths/rules/imports, and do not rotate or reenroll
hardware merely because a file moved.

Two settings in `hosts/nix/modules/system/networking.nix` are tied to `tun.device: mihomo` inside that
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

`Flowseal/tg-ws-proxy` is packaged from source in `hosts/nix/pkgs/bypasses/tg-ws-proxy.nix` and
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

## RGB lighting

`hosts/nix/lighting.nix` runs `openrgb-off` once at boot, without a GUI, tray app or
SDK server. It sets both ENE RAM modules and the Gainward RTX 3090 to Off, and
sends black in Direct mode to MSI Mystic Light's JAF/JARGB headers.
Wooting and Elgato detectors are disabled; explicit device-name selectors also
exclude the Wooting keyboard, Stream Deck and Wave XLR from lighting commands.
Other hardware status indicators are outside OpenRGB's supported controls.

After a rebuild, reapply with `sudo systemctl start openrgb-off`.
Inspect failures with `journalctl -u openrgb-off`. The root-only service does not
require user-facing OpenRGB udev permissions. Its private mount namespace hides
the allocator preload only for this service; system-wide hardening stays enabled.

## Auto-updates

`system.autoUpgrade` builds daily and **stages** for next boot (`operation =
"boot"`), so a kernel or NVIDIA bump never disturbs a running session. For a bad
update, use **Limine recovery with a zero timeout** below to select a previous
generation; the default menu is not visible.
Watch it with `journalctl -u nixos-upgrade.service`.

`nh`'s default `/etc/nixos` and `--flake /etc/nixos` read the tree through Git.
Tracked modifications are visible without committing; new source files need
`git add` (or `git add -N` to mark intent without staging their contents).
For untracked iteration use `nh os switch path:/etc/nixos` or an explicit
`--flake path:/etc/nixos#nix`. Neither mode makes plaintext safe in the tree.

## Touch-only disk unlock

**Enrollment and boot tests are operator-only and pending until explicitly
performed.** PIV SOPS enrollment does not enroll FIDO2 disk unlock. Keep the
existing passphrase, a tested recovery ISO, and a known-working boot generation.
Never delete/reformat a volume or wipe existing keyslots to add touch support.

For this installed machine the encrypted backing partition is
`/dev/disk/by-uuid/7f0ee47d-3794-4ec0-a006-f8eea8fc471a`, from
`hosts/nix/hardware.nix`; `/dev/mapper/cryptroot` is the **opened** mapping,
not the enrollment target. On another machine use its verified backing UUID.
In an authenticated root shell, after approving enrollment:

```bash
disk=/dev/disk/by-uuid/7f0ee47d-3794-4ec0-a006-f8eea8fc471a
cryptsetup luksDump "$disk"
cryptsetup open --test-passphrase "$disk"
```

Confirm LUKS **version 2**, the correct physical disk, a working passphrase,
and free token/keyslot capacity. Back up the header with `cryptsetup
luksHeaderBackup "$disk" --header-backup-file /mounted-offline-backup/cryptroot.header`,
substituting a real protected external backup location. Keep that backup mode
`0600` or equivalent on encrypted media outside this disk/repo, and verify the
backup is readable. A header backup plus an old valid passphrase can restore
old access: treat it as sensitive and do not casually restore it after revocation.
Do not proceed without passphrase and backup confirmation.

List devices with `systemd-cryptenroll --fido2-device=list` and check installed
`--help`. After confirming the specific compatible `/dev/hidrawN`, enroll:

```bash
systemd-cryptenroll "$disk" --fido2-device=/dev/hidrawN \
  --fido2-with-client-pin=no \
  --fido2-with-user-presence=yes \
  --fido2-with-user-verification=no
```

`/dev/hidrawN` is a placeholder for the freshly verified device; its number can
change. No `--wipe-slot` belongs in initial enrollment. Hardware restrictions
may refuse these policies; do not clear a device PIN to work around them.
Inspect token metadata afterward: UP required, client PIN/UV not required.
If an existing enrollment requires a PIN, plan a replacement enrollment and
test it before targeted retirement; editing its JSON is not re-enrollment.

The systemd initrd enables FIDO2 support and extends only `cryptroot` with
`fido2-device=auto,token-timeout=10s`, retaining discard support. That timeout
bounds token discovery, **not all touch interactions**. Password fallback stays
available; do not enable `headless`. Root unlock cannot depend on a SOPS key
inside the still-locked root filesystem.

Before an approved reboot, inspect the built initrd's crypttab (one root mapping
named `cryptroot`), FIDO2 library/udev support, and USB/HID modules. Inspect
`/boot/limine/limine.conf` to associate the intended generation with its actual
initrd; `readlink /nix/var/nix/profiles/system` identifies the selected system
profile. A successful evaluation/build/switch is not a successful unlock.

At the console, separately test cold boot with token + touch/no PIN, boot
without the token using the retained passphrase, and no-touch/wrong-token
fallback. Record waits and results. Do not garbage-collect the recovery
generation or remove fallback slots until all paths work.

### Limine recovery with a zero timeout

`boot.loader.timeout = 0` means immediate boot without a visible menu. The
locked [Limine 12.9.0 documentation](https://github.com/limine-bootloader/limine/blob/v12.9.0/CONFIG.md)
documents UEFI one-shot timeout override. When the installed bootloader supports
it, an operator-approved `sudo systemctl reboot --boot-loader-menu=30s` requests
a menu on that next reboot; select the known-working generation there. Do not
assume holding Shift/Escape works at timeout zero, or assume a newer checkout
means the installed EFI binary was updated.

For a controlled boot experiment, an alternative is temporarily setting
`boot.loader.timeout = 10`, rebuilding the boot configuration, and verifying the
generated timeout before reboot. If the machine cannot boot or the one-shot
request is unsupported, use the firmware boot menu to start the recovery ISO.
Identify and mount the installed ESP (this machine:
`/dev/disk/by-uuid/612D-84DE`), back up its active `limine/limine.conf`, then edit
its global `timeout: 0` to `timeout: no`. Verify no earlier config candidate
shadows it, following the linked Limine search order. Reboot to the disk and
select the known-working generation. This emergency ESP edit is overwritten
by bootloader regeneration; put any lasting timeout change in Nix.

If no generation unlocks root, the ISO can open the verified backing partition
with its retained passphrase as `cryptroot`; mount root and ESP, enter via
`nixos-enter`, and repair the configuration. Do not format anything. A NixOS
rollback changes boot configuration, not LUKS enrollment or keyslots.

## Touch-only sudo with password fallback

Only PAM services `sudo` and `sudo-i` use U2F as `sufficient`, before the Unix
password path. sudo-rs authorization and `wheelNeedsPassword = true` remain;
this is not a NOPASSWD grant. Touch is requested with `userpresence=1`,
`pinverification=0`, `userverification=0`, and a cue. The central mapping is
`/etc/u2f-mappings`, root-controlled, with origin **and** appid `pam://nix`.
It contains public registration metadata, not an exported private key, and
does not depend on SOPS. Desktop login, autologin, locker, keyring, and polkit
authentication are not part of this setup.

Keep a working authenticated root shell open throughout registration and
testing. As `ri`, check `pamu2fcfg --help`, then register the inspected key to a
protected temporary file outside the checkout, using ordinary non-resident
credentials:

```bash
umask 077
mapping="$(mktemp /run/user/"$(id -u)"/u2f-mapping.XXXXXX)"
pamu2fcfg --username=ri --origin=pam://nix --appid=pam://nix > "$mapping"
```

Do not add `--resident`, `--pin-verification`, `--user-verification`, or
`--no-user-presence`. In the retained root shell, inspect the result privately
and, for **first enrollment only**, install it with
`install -o root -g root -m 0600 /the/verified/temporary/file /etc/u2f-mappings`.
If the file already exists, back it up and merge the new registration into
`ri`'s existing colon-separated entry, preserving every other user/key; do not
overwrite it. Remove the temporary file afterward. Do not reset FIDO or clear
its existing PIN. The [pamu2fcfg manual](https://developers.yubico.com/pam-u2f/Manuals/pamu2fcfg.1.html)
describes registration flags.

Inspect generated `/etc/pam.d/sudo` and `/etc/pam.d/sudo-i`: numeric `=0`
arguments must actually be present, U2F must be `sufficient`, the normal password
and account/session checks must remain, and `nouserok`/`alwaysok` must be absent.
Do not change global PAM enablement or timestamp policy.

After approved activation, run each fresh attempt from a separate **`ri`**
terminal, never from the root shell: `sudo -k; sudo true`, and separately
`sudo -k; sudo -i` (then `exit` the acquired shell). For **both** commands test:

- Enrolled key + touch: succeeds without a PIN.
- Enrolled key without touch: no hardware success; it may wait and fall back
  to a password. Record the wait; do not mistake cached authorization for touch.
- No key + correct account password: succeeds.
- No key + wrong password: fails.
- Unregistered key, and controlled missing/malformed mapping: no
  unconditional success; password fallback still works.

Keep the root shell until the good-password and negative tests pass. If PAM
fails, use it to restore the saved mapping and switch to the known-working
configuration (`nixos-rebuild switch --rollback` when that previous generation
is the intended one); repeat fresh password tests before closing the shell.
Mapping edits are outside Nix generations and need their own restoration.
For a lost token, remove only its reviewed registration after replacement/
fallback tests; separately revoke its SOPS and disk access.
