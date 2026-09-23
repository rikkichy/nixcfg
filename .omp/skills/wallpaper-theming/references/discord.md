# Discord and its theme

`hosts/nix/modules/system/applications.nix` installs
`discord.override { withEquicord = true; }`;
`hosts/nix/modules/home/matugen.nix` owns the two CSS channels, and
`hosts/nix/modules/home/applications.nix` seeds settings. The injection is part of the
derivation: `app.asar` is moved aside and replaced by a directory whose
`index.js` requires Equicord's patcher, so an update cannot leave a client
half-patched the way patching an installed copy can.

Equicord's data directory is `~/.config/Equicord` — the Electron user data path
with the last component swapped, not something the Discord wrapper sets, and
overridable with `EQUICORD_USER_DATA_DIR`. Under it, `themes/` holds theme
files and `settings/settings.json` holds which of them are on. It is a Vencord
fork and reads Vencord's settings schema, so a settings file carried across
applies; plugins the fork does not know are ignored rather than rejected.

The theme is refact0r's Midnight, pinned in `hosts/nix/pkgs/ricing/midnight-discord.nix`, and it
reaches the client in two halves through two different channels:

- **`themes/wallpaper.theme.css` is static**, and owned by `xdg.configFile` as
  a store symlink. It is a meta block, Midnight from the store, and
  `hosts/nix/dotfiles/ricing/discord/theme.css` — fonts, window shape, animations —
  concatenated at build time.
- **`settings/quickCss.css` is the palette**, rendered by matugen from
  `hosts/nix/dotfiles/ricing/matugen/templates/discord-palette.css` on every wallpaper change.

**That split is what keeps a wallpaper change from flashing the client
unstyled.** A theme is loaded by `@import`, and reloading one drops all of
them:

- The renderer keeps a single `<style>` whose content is one
  `@import url("vencord:///themes/<name>?v=<timestamp>")` per enabled theme,
  and *any* change under `themes/` rewrites that element's entire content with
  a freshly stamped URL. The stamp defeats the cache deliberately, and the
  imports resolve asynchronously over the `vencord://` protocol — so between
  the assignment and the fetch there is no theme applied at all and Discord's
  own colours show through.
- **QuickCSS is the one channel that is not an import.** Its listener assigns
  the file's text directly to a live element — `style.textContent = css` — so
  it swaps inside one frame with nothing to fetch.
- **QuickCSS wins ties.** Both elements are appended to the same root, themes
  first and QuickCSS second, so at equal specificity the palette overrides
  Midnight. `--bg-floating` is the one variable that has to be declared on
  `body` rather than `:root`, because Midnight declares it on `body` and a
  `:root` declaration loses to it on every element inside the document.

Two mechanics constrain how the palette file may be written:

- **The QuickCSS watcher watches the file, the themes watcher watches the
  directory.** `watch(QUICK_CSS_PATH)` follows an inode, and matugen truncates
  and rewrites in place, which keeps it attached. Staging the render elsewhere
  and renaming it into place — the usual way to make a write atomic — would
  fire the watcher once and then never again, since the watched inode is no
  longer the file at that path.
- The QuickCSS read is debounced 50ms after the last event, so a truncate and
  a write coalesce into one swap rather than a flash of empty CSS.

Order is load-bearing inside the theme file. Midnight defines a default for
every variable set after it, so it has to come first; at equal specificity the
last declaration wins. The meta block has to be first of all, since Equicord
reads the theme's name and description from it and otherwise shows the
filename. Both halves are concatenated rather than `@import`ed, because the
renderer refuses a `file://` subresource on a page served from
`https://discord.com` whatever the CSP says — and the URL Midnight's own
install instructions point at is fetched again at every start, which is both a
network dependency and an upstream that can change under the machine.

Colour details that are not free choices:

- The five-step ramps are `color-mix(… black N%)` evaluated by the browser
  rather than darkened at render time, because matugen has no relative
  lightness filter.
- Only the accent and red ramps follow the wallpaper. Green, yellow and purple
  are the same literals the terminal palette uses and for the same reason —
  otherwise a low-chroma wallpaper collapses the status dots into three shades
  of one near-black.

The client runs without animation, which takes two settings that reach
different things:

- **`--animations: off` reaches only what Midnight gates.** Those blocks are
  `@container body style(--animations: on)` and what they carry is movement
  rather than timing: a channel row slides 10px right under the pointer, its
  unread dot slides with it, the home button's moon spins. Midnight's ungated
  transitions and every animation Discord itself ships are untouched by it.
- **The rest is one `*, *::before, *::after` reset** at the end of the theme
  file, and its durations are `0.01ms` rather than `0`. A transition whose
  combined duration is zero never starts and so fires no `transitionend`, and
  Discord waits on that event to unmount things — menus and modals that close
  by transitioning out stay on screen instead. 0.01ms is over inside the frame
  and still fires. `animation-iteration-count: 1` covers the mirror of that:
  an `infinite` animation at 0.01ms would fire `animationiteration` once per
  frame forever.

Three runtime behaviours worth relying on:

- **Equicord watches both files**, so a wallpaper change restyles a running
  Discord with no restart and no flash.
- **A theme file may be a symlink.** `ensureSafePath` normalises the string
  and never resolves it, so it guards against `../` and nothing else; the IPC
  read and the `vencord://` handler both follow the link into the store.
- `settings.json` is Equicord's to write — every GUI toggle rewrites it — so it
  is seeded by an activation script only when absent, which is what enables the
  theme on a machine where Equicord has never run. A partial file is enough; the
  defaults are merged in underneath. Disabling the theme in the UI therefore
  sticks. The palette rides on `useQuickCss`, which defaults on; turned off in
  the UI, the colours fall back to Midnight's own defaults while the rest of
  the theme stays.

**`raw.githubusercontent.com` is unreachable from this machine directly**, so
building `pkgs.midnight-discord` needs the tunnel up — while `cache.nixos.org`
needs it down. `vpn on` with `--option substituters ''` is the combination that
fetches it; once it is in the store neither applies.
