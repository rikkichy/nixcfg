# Linux wallpapers and theming

Owner: `hosts/nix/modules/home/matugen.nix`. The built-in image is
`hosts/nix/dotfiles/ricing/default-wallpaper.png`. Quickshell source is
`hosts/nix/dotfiles/ricing/quickshell/` and deployment is in
`hosts/nix/modules/home/quickshell.nix`.

`wpp` opens the Quickshell launcher gallery over `~/Pictures/Wallpapers`.
`wpp` and `awpp` use `desktop wallpaper MODE DIRECTORY` IPC, where MODE is
`wallpapers` or `animated-wallpapers`. Their `--list DIRECTORY` mode returns
metadata-only JSON `{name,path,preview,revision}` entries without decoding images
or writing caches. Preview is a fresh cached thumbnail path or an empty string.
Both helpers support `--preview PATH DIRECTORY`, validating and generating one
cached thumbnail and returning JSON `{preview}`. `--apply PATH DIRECTORY` rechecks collection membership before
any side effects. Paths travel as argv and preview URLs are
encoded by QML. Missing still collections offer the built-in default; opening
the gallery never applies it automatically.
Selecting a still displays it through awww and stops animated playback.
It then calls private `theme-apply`, which runs these steps in order:
1. Generate Matugen application palettes, including Quickshell semantic roles.
2. Deliver terminal OSC sequences.
3. Record success.

`wallpaper-restore` also displays its image before calling that helper at login.
Successful application records the image in `~/.local/state/wallpaper/current`.

Home Manager's `services.awww` owns `awww-daemon` independently of Quickshell.
Its extended `ExecStartPost` waits for a successful `awww query`, with a bounded
timeout. `wallpaper-restore.service` requires and starts after that ready service.
Restoration always regenerates all palettes from the recorded image, so template
changes and missing outputs are not hidden by existing Quickshell palette files.
Missing or broken records use the built-in default. State/cache paths follow
Home Manager's configured XDG locations. Collection overrides remain supported.
The checked application steps stay outside Matugen's wallpaper command and hooks:
version 4.2 logs nonzero command exits but returns success.

Matugen owns `quickshell/colors.json`.
Follow the [Quickshell writable-consumer contract](../../desktop-shell/references/quickshell.md#palette-and-native-crash-boundary).

Both galleries use bounded 640×360 JPEG thumbnails rather than decoding originals
in Qt. Four workers serve visible rows before one prefetch row; only visible
thumbnails enter Qt's async image loader. Each FFmpeg worker uses one decode,
filter and encode thread. Pending work comes from the current viewport, not an
accumulated queue; in-flight jobs finish naturally.
Still/video thumbnails live under `~/.cache/{wallpaper,animated-wallpaper}/thumbs/v2`,
keyed by collection-directory hash, source basename and mtime/size revision.
Lists return fresh cached paths directly, including after a shell restart.
A bounded 128-entry URL cache retains metadata; Qt owns decoded-image caching.
Failed previews show “Preview unavailable” without blocking selection.

#### awww daemon sandbox

Only `awww.service` is sandboxed. It uses `PrivateUsers=true` so a **user**
unit can apply `ProtectSystem=strict`, `ProtectHome=read-only` and `PrivateTmp`.
Unprivileged user namespaces must remain enabled. Fix namespace setup failures
without disabling the filesystem protections. The host's
systemd 261 supports this combination. `NoNewPrivileges`, empty bounding/ambient
capability sets and `RestrictAddressFamilies=AF_UNIX` apply to the daemon and
readiness client. Wayland and awww IPC both use UNIX sockets.

The writable allowlist is `${config.xdg.cacheHome}/awww` and `%t` (the user
manager's runtime directory, normally `/run/user/UID`), plus private temporary
directories. A trusted store `mkdir -p` in `ExecStartPre` uses the `+` command
prefix. It creates only the cache directory before the mount sandbox exists.
It still runs as the unprivileged user manager's owner.
This avoids relying on the manager's `CacheDirectory` root when Home Manager
customizes `xdg.cacheHome`. It also permits restart after `awww clear-cache`
removes the directory.
The service explicitly sets `XDG_CACHE_HOME` to that configured location.

[awww 0.12.1 cache ownership](https://codeberg.org/LGFae/awww/src/tag/v0.12.1/common/src/cache.rs)
includes versioned subdirectories and deletion of previous versions: do not
limit writes to just the current version. Keep this cache persistent across
daemon restarts. [IPC socket ownership](https://codeberg.org/LGFae/awww/src/tag/v0.12.1/common/src/ipc/socket.rs)
is `$XDG_RUNTIME_DIR/<basename of WAYLAND_DISPLAY>-awww-daemon.sock`. Creation
and removal require the **parent runtime directory** writable. Do not move
the service alone to a private `XDG_RUNTIME_DIR`: every picker/readiness/restore
client must find the same socket. The Wayland socket remains visible and usable.

Home/image collections otherwise remain readable, including custom paths.
[The daemon forks a restore client](https://codeberg.org/LGFae/awww/src/tag/v0.12.1/daemon/src/wallpaper.rs).
That client must read the original image inside the sandbox on startup/output changes.
SSH/GnuPG/SOPS directories, `/run/secrets`, `/run/secrets-for-users` and runtime
GnuPG/keyring directories are inaccessible when present. Do not put wallpaper
collections in those paths or shared `/tmp`/`/var/tmp` (hidden by `PrivateTmp`).
This is write confinement and limited secret-path hiding, **not** full home
confidentiality or isolation from all same-user UNIX services.

Do not copy this sandbox onto `theme-apply`, `wallpaper-restore` or mpvpaper.
Palette generation intentionally writes application-owned config/data,
wallpaper state and terminal devices. Video playback has separate GPU/media
requirements. Those user-state paths remain writable outside awww.

Service previews require a nested compositor/private bus and a uniquely named
transient copy of the evaluated service. Never use the live wallpaper service.
Follow [compositor environment isolation](../../desktop-shell/references/quickshell.md#preview-isolation).
Override the transient cache/runtime paths to disposable directories **outside**
shared `/tmp`/`/var/tmp`, which `PrivateTmp` hides.
Pass the nested Wayland socket as an absolute `WAYLAND_DISPLAY`.
Save the activation-environment snapshot outside the checkout so an interrupted
preview can still restore the live session.
Preserve the actual `ExecStartPre`, sandbox properties and `ExecStartPost`.
Omit session dependencies and automatic restart.
Never open real secrets during a preview.
Stop only the transient unit and nested compositor.
Restore manager/bus environments even on failure, then remove disposable artifacts.

#### Animated wallpapers

`awpp` uses the same picker over `~/Videos/Animated Wallpapers`.
It passes the choice to `awp-apply`. `animated-wallpaper.service` plays the video.
Neither colour engine accepts a video. Private `wallpaper-frame` extracts its
backing still, then `awp-apply` records the video and restarts playback before
theming the still. Playback must not wait for palette generation.
At login, playback is ordered after the compositor and awww, not after
`wallpaper-restore.service`. The bottom layer makes theme restoration independent.
Both current and animated records coexist. `ConditionFileNotEmpty` skips the
service without an animated record. ExecStart also guards missing video files.
Cancellation and frame-extraction failure leave animated state untouched.
A later theme failure is reported but leaves the selected video playing.
`wpp` waits for awww to accept its selected or default still, stops playback,
and deletes the animated record before theming. A failed image leaves playback
untouched. A later theme failure leaves the still selected. Service-stop failures
are fatal and retain the animated record.

- **mpvpaper and awww both default to the `background` layer**.
  Their startup order decides which one is visible. At startup, mpvpaper warns:
  "swww-daemon is running. This may block mpvpaper from being seen".
  `-l bottom` places playback above the still and below every window,
  regardless of creation order.
- `wallpaper-frame VIDEO OUTPUT` extracts the full-resolution backing PNG using
  accurate three-second seeking, retrying empty output from the start.
  `--preview-image` and `--preview-video` select bounded full-range JPEG output;
  video previews use keyframe-only decoding near three seconds and retry from
  the start when no usable frame is produced.
  Nonempty outputs are reused when the source is not newer. Extraction stages
  beside the destination and replaces it only after successful nonempty output.
  Failed regeneration preserves the previous file. Full-frame failures are fatal;
  thumbnail failures remain nonfatal.
- Thumbnail cache paths include a collection hash and source revision; identical
  filenames in different collections cannot collide. Full-frame keys hash the
  absolute source path. Animated labels omit the extension; selection uses the
  complete path.
