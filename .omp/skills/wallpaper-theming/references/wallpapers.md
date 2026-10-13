# Linux wallpapers and theming

Owner: `hosts/nix/modules/home/matugen.nix`. The built-in image is
`hosts/nix/dotfiles/ricing/default-wallpaper.png`; Quickshell source is
`hosts/nix/dotfiles/ricing/quickshell/` and deployment is in
`hosts/nix/modules/home/quickshell.nix`.

`wpp` is the picker: fuzzel in dmenu mode over `~/Pictures/Wallpapers`.
It draws the still through awww, stops animated playback, then calls private
`theme-apply`: Matugen application palettes (including Quickshell semantic roles) → terminal OSC delivery → cursor rendering, then success recording.
`wallpaper-restore` also displays its image before calling that helper at login.
Successful application records the image in `~/.local/state/wallpaper/current`.

Home Manager's `services.awww` owns `awww-daemon` independently of Quickshell.
Its extended `ExecStartPost` waits for a successful `awww query`, with a bounded
timeout. `wallpaper-restore.service` requires and starts after that ready service.
Restoration always regenerates all palettes from the recorded image, so template
changes and missing outputs are not hidden by existing Fuzzel/Quickshell files.
Missing or broken records use the built-in default. State/cache paths follow
Home Manager's configured XDG locations; collection overrides remain supported.
The checked application steps stay outside Matugen's wallpaper command and hooks:
version 4.2 logs nonzero command exits but returns success.

Matugen owns `quickshell/colors.json`; render `hosts/nix/dotfiles/ricing/matugen/templates/quickshell.json` to a temporary destination when changing roles.
Follow the [Quickshell writable-consumer and isolated-verification contract](../../desktop-shell/references/quickshell.md#palette-and-native-crash-boundary) to prove live reload without touching the running shell.

Thumbnails are pre-rendered to `~/.cache/wallpaper-picker` with
`gdk-pixbuf-thumbnailer` because fuzzel builds with `+png +svg` only — a JPEG
source draws no thumbnail at all — and because pointing it at originals means
decoding up to 15 MB per row while the menu opens.
Both wallpaper pickers queue only missing, empty or stale thumbnails through
`xargs -0 -n 2 -P 4`. Filename/output pairs are NUL-delimited; four workers bound
CPU use. Thumbnail errors remain nonfatal, and the menu opens after workers finish.

#### awww daemon sandbox

Only `awww.service` is sandboxed. It uses `PrivateUsers=true` so a **user**
unit can apply `ProtectSystem=strict`, `ProtectHome=read-only` and `PrivateTmp`.
Unprivileged user namespaces must remain enabled; a namespace setup failure
must be fixed, not hidden by disabling the filesystem protections. The host's
systemd 261 supports this combination. `NoNewPrivileges`, empty bounding/ambient
capability sets and `RestrictAddressFamilies=AF_UNIX` apply to the daemon and
readiness client. Wayland and awww IPC both use UNIX sockets.

The writable allowlist is `${config.xdg.cacheHome}/awww` and `%t` (the user
manager's runtime directory, normally `/run/user/UID`), plus private temporary
directories. A trusted store `mkdir -p` in `ExecStartPre` uses the `+` command
prefix to create just the cache directory before the mount sandbox exists;
it still runs as the unprivileged user manager's owner. This avoids relying on
the manager's `CacheDirectory` root when Home Manager customizes `xdg.cacheHome`,
and permits restart after `awww clear-cache` removes the directory.
The service explicitly sets `XDG_CACHE_HOME` to that configured location.

[awww 0.12.1 cache ownership](https://codeberg.org/LGFae/awww/src/tag/v0.12.1/common/src/cache.rs)
includes versioned subdirectories and deletion of previous versions: do not
limit writes to just the current version. Keep this cache persistent across
daemon restarts. [IPC socket ownership](https://codeberg.org/LGFae/awww/src/tag/v0.12.1/common/src/ipc/socket.rs)
is `$XDG_RUNTIME_DIR/<basename of WAYLAND_DISPLAY>-awww-daemon.sock`; creation
and removal require the **parent runtime directory** writable. Do not move
the service alone to a private `XDG_RUNTIME_DIR`: every picker/readiness/restore
client must find the same socket. The Wayland socket remains visible and usable.

Home/image collections otherwise remain readable, including custom paths:
[the daemon forks a restore client](https://codeberg.org/LGFae/awww/src/tag/v0.12.1/daemon/src/wallpaper.rs)
which must read the original image inside the sandbox on startup/output changes.
SSH/GnuPG/SOPS directories, `/run/secrets`, `/run/secrets-for-users` and runtime
GnuPG/keyring directories are inaccessible when present. Do not put wallpaper
collections in those paths or shared `/tmp`/`/var/tmp` (hidden by `PrivateTmp`).
This is write confinement and limited secret-path hiding, **not** full home
confidentiality or isolation from all same-user UNIX services.

Do not copy this sandbox onto `theme-apply`, `wallpaper-restore` or mpvpaper.
Palette/cursor generation intentionally writes application-owned config/data,
wallpaper state and terminal devices; video playback has separate GPU/media
requirements. Those user-state paths remain writable outside awww.

For runtime proof use a nested compositor/private bus and a uniquely named
transient copy of the evaluated service, never the live wallpaper service.
Follow [compositor environment isolation](../../desktop-shell/references/quickshell.md#isolated-verification),
override the transient cache/runtime paths to disposable directories **outside**
shared `/tmp`/`/var/tmp`, which `PrivateTmp` hides, and pass the nested Wayland
socket as an absolute `WAYLAND_DISPLAY`. Save the activation-environment snapshot
outside the checkout so an interrupted smoke can still restore the live session.
Preserve the actual `ExecStartPre`, sandbox properties and `ExecStartPost`; omit session dependencies
and automatic restart. Prove query readiness, image display from a custom path
with spaces, cache restoration after transient restart, socket cleanup, and
read-only home/system plus writable cache/runtime using dummy files. Check
secret-path denial without opening real secrets. Stop only the transient unit
and nested compositor, restore manager/bus environments even on failure, then
remove disposable artifacts. Evaluation alone is not runtime sandbox proof.

#### Animated wallpapers

`awpp` is the same picker over `~/Videos/Animated Wallpapers`, handing the
choice to `awp-apply`, and `animated-wallpaper.service` is what plays it.
Neither colour engine accepts a video. Private `wallpaper-frame` extracts its
backing still, then `awp-apply` records the video and restarts playback before
theming the still. Playback must not wait for palette or cursor generation.
At login, playback is ordered after the compositor and awww, not after
`wallpaper-restore.service`; the bottom layer makes the theme restore independent.
Both current and animated records coexist. `ConditionFileNotEmpty` skips the
service without an animated record; ExecStart also guards missing video files.
Cancellation and frame-extraction failure leave animated state untouched.
A later theme failure is reported but leaves the selected video playing.
`wpp` waits for awww to accept its selected or default still, stops playback,
and deletes the animated record before theming. A failed image leaves playback
untouched; a later theme failure leaves the still selected. Service-stop failures
are fatal and retain the animated record.

- **mpvpaper and awww both default to the `background` layer**, where the
  order they happened to start in decides which one is visible. mpvpaper warns
  about exactly this at startup — "swww-daemon is running. This may block
  mpvpaper from being seen" — and `-l bottom` settles it: above the still,
  below every window, regardless of creation order.
- `wallpaper-frame VIDEO OUTPUT [FFMPEG_OUTPUT_ARGUMENT ...]` seeks three seconds
  past opening fades and retries empty output from the start for short videos.
  It reuses nonempty output when the source is not newer, stages into a temporary
  PNG beside the destination, and replaces the cache only after successful
  nonempty extraction. Failed regeneration preserves an existing usable frame.
  Full-frame failures are fatal; thumbnail failures remain nonfatal.
- The thumbnail cache is keyed on the full filename including extension, for
  the reason `wpp`'s is; only the fuzzel label drops it, because these names
  are sentences.
