# The browser and its web apps

Helium, a Chromium build, from the `helium` flake input. It is the browser
`hosts/nix/dotfiles/ricing/hypr/variables.lua` names, the `x-scheme-handler/*` and `text/html` default in
`hosts/nix/modules/home/applications.nix`, and the runtime behind the Bitwarden and Spotify entries
in `hosts/nix/modules/home/fuzzel.nix`, which are `--app=URL` windows.

**Widevine is not in the package**, and Spotify playback requires it. Without it Spotify loads, searches and browses normally and then
refuses to play any track, with nothing in the UI or the logs naming a missing
decryption module — it presents as broken audio, so the sink and the mute state
get investigated first and are always fine.

A build takes the CDM by one of two routes and this one has only the second:

- **Bundled**, from `WidevineCdm/` beside the binary. That lookup is compiled
  in or it is not — nixpkgs patches `BUNDLE_WIDEVINE_CDM=true` into
  `third_party/widevine/cdm/BUILD.gn` to get it — so dropping the directory
  into a binary release's tree achieves nothing at all.
- **As a component**, from `~/.config/net.imput.helium/WidevineCdm/<version>/`,
  which `hosts/nix/modules/home/applications.nix` seeds from `pkgs.widevine-cdm`. Startup scans that
  directory, registers the highest version whose `manifest.json` agrees with
  the directory name, and records it in `latest-component-updated-widevine-cdm`
  beside it, holding `{"Path": …}`. Registration happens from that hint, so
  **the CDM arrives one start late**: the run that first sees a newly seeded
  directory writes the hint and plays nothing.

`strings` on the two binaries is what separates the routes: `Registering
bundled Widevine ` against `Registering hinted Widevine `, one string each.
Beyond that the entry is a real directory of symlinks (`recursive = true`)
rather than a symlinked directory, because the hint records the path as found —
a symlink resolves to the store and a nixpkgs bump then moves it out from
under the hint.

`programs.chromium` in `hosts/nix/modules/system/applications.nix` installs no browser. It writes
policy JSON, `/etc/chromium/policies/managed/` among other prefixes, and
helium reads that directory as any Chromium build does; `chrome://policy` shows
each one as Platform / Machine / Mandatory once it has been picked up.

Two things make this awkward to verify:

- **`--headless` will not start**, exiting on `Multiple targets are not
  supported in headless mode`. `--ozone-platform=headless` is the way to run it
  without a window, and it takes the ordinary flags —
  `--enable-logging=stderr --v=1` is where the Widevine lines appear. Driving
  such an instance needs the bundled `chromedriver`, which is not patchelfed
  and has to be started through the loader with helium's own `RUNPATH`.
- **EME is a secure-context API.** `navigator.requestMediaKeySystemAccess` is
  simply not a function on `file://` or `about:blank`, which reads as the
  feature being compiled out. `http://localhost` is trustworthy enough for it,
  so the smallest real test is a page served by socat.

The web apps need `settings.StartupWMClass`. An `--app=URL` window carries its
own WM_CLASS — `chrome-<host>__<path>-Default`, the `chrome-` prefix intact
here — which never matches the desktop file id, so without it a running app
falls back to the generic browser icon even though `Icon=` is correct. Read the
real value off `hyprctl clients` with the app running — a wrong string fails
silently.

`StartupWMClass` only affects the icon of a **running window** (bar, alt-tab).
It does nothing for the launcher entry, whose icon comes from `Icon=` resolved
against the icon theme — a separate problem with a separate fix. Establish which
one is actually wrong before changing anything.

The browser is single-instance: `helium --app=URL` hands off to the running
process and the launcher exits immediately. There is no process to `pkill` —
close such a window through the compositor.

GTK apps built on `GApplication` are single-instance too, which makes a
launcher keybind look broken rather than misconfigured: a bare second
invocation activates the existing primary instance instead of opening a
window, so the spawn key appears dead until the first window is closed.
`--new-window` is the usual escape. Expect this from any `GApplication` bound
to a spawn key.
