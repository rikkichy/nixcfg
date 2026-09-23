# Linux wallpapers and theming

Owner: `hosts/nix/modules/home/matugen.nix`. The built-in image is
`hosts/nix/dotfiles/ricing/default-wallpaper.png`; Quickshell source is
`hosts/nix/dotfiles/ricing/quickshell/` and deployment is in
`hosts/nix/modules/home/quickshell.nix`.

`wpp` is the picker: fuzzel in dmenu mode over `~/Pictures/Wallpapers`.
It draws the still through awww, stops animated playback, then calls private
`theme-apply` for application palettes, including Quickshell's semantic color roles.
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

Quickshell reads and watches `quickshell/colors.json`, but does not own it.
Its deployed QML lives in the read-only `~/.config/quickshell/expressive` directory.
Render `hosts/nix/dotfiles/ricing/matugen/templates/quickshell.json` to a temporary destination
and verify live palette reload in an isolated shell when changing color roles.

Thumbnails are pre-rendered to `~/.cache/wallpaper-picker` with
`gdk-pixbuf-thumbnailer` because fuzzel builds with `+png +svg` only — a JPEG
source draws no thumbnail at all — and because pointing it at originals means
decoding up to 15 MB per row while the menu opens.
Both wallpaper pickers queue only missing, empty or stale thumbnails through
`xargs -0 -n 2 -P 4`. Filename/output pairs are NUL-delimited; four workers bound
CPU use. Thumbnail errors remain nonfatal, and the menu opens after workers finish.

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
