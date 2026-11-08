# Discord

Both desktop hosts install vanilla Discord from Nixpkgs, without injected client
mods, declarative plugins, custom themes or Matugen palette output.

Source ownership paths are repository-relative:

- Linux: `hosts/nix/modules/system/applications.nix` installs `pkgs.discord`.
- macOS: `hosts/ne/modules/home/discord.nix` retains the legacy-updater selection,
  disables host/module updates and stages pinned native modules for Finder
  launches. See [the Mac guide](../ne.md#discord) for the updater constraint.

Discord owns its writable profile and account data. Package changes do not clear
that profile or delete old client-mod data; vanilla Discord does not load it.
Updates follow the Nixpkgs pin and rebuild, not an external client-mod installer.

For startup diagnosis, use an isolated disposable profile and graphical session,
not the user's signed-in session. Confirm that the login form renders rather than
treating process startup as success. A Linux Xvfb check does not verify Wayland GPU
rendering, signed-in behavior or macOS Finder launches. Those checks remain
operator acceptance after activation.
