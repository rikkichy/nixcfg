# The file manager

Ownership: `hosts/nix/modules/system/applications.nix` installs and integrates
Thunar; `hosts/nix/modules/home/applications.nix` declares its bookmarks,
xfconf settings and MIME defaults.

Thunar, with `services.tumbler` for thumbnails and `programs.xfconf` for
settings persistence — it draws no previews and remembers no view state
without those two, and neither failure is logged.

The GNOME session services a modern nautilus assumes are all absent here, and
the way that surfaces is a **25-second stall, not an error**:

- `org.freedesktop.Tracker3.Miner.Files` and Localsearch are not activatable,
  and `org.gnome.Mutter.ServiceChannel` has no owner. Each is reported once at
  startup and each fails in milliseconds, so the messages sit immediately
  above the stall while having nothing to do with it.
- The stall itself is the D-Bus default reply timeout. Opening a folder from
  another application goes through xdg-desktop-portal, which calls `ShowItems`
  on `org.freedesktop.FileManager1`; that D-Bus-activates the file manager
  under `systemd --user` as `dbus-:1.2-org.freedesktop.FileManager1@N.service`,
  and the call returns `Failed to call ShowItems: Timeout was reached` exactly
  25s later, every time. The same 25s shows up from inside the process as
  `Couldn't read the color-scheme setting: Timeout was reached` — GTK4's
  synchronous `org.freedesktop.portal.Settings` read at startup.

The measurement that separates the two is starting the file manager
**directly** versus letting the portal activate it: direct is sub-second and
a direct `FileManager1.ShowItems` answers in well under a second, so a slow
open is the activation path and never the program itself.

`journalctl --user` is where all of this is visible; a terminal only shows the
last message printed before the wait.

Its settings live in two different places, and only one of them is a file:

- **The sidebar bookmarks are `xdg.configFile."gtk-3.0/bookmarks"`.** That is
  the GTK file shared with every GIO browser, not a Thunar format. Owning it
  from the flake makes it a read-only store symlink, which is what disables
  "Add Bookmark" and dragging a folder onto the sidebar — the list is editable
  only through the attribute. `force = true` permits replacing an unmanaged
  bookmarks file created by the application before the first activation.
- **Everything else is xfconf**, declared through `xfconf.settings.thunar`.
  home-manager applies these with `xfconf-query` at activation instead of
  managing a file, so a declared value is stamped back on every switch and its
  GUI toggle stops holding, while an undeclared one stays Thunar's. The
  built-in sidebar entries are addressed by URI (`recent:///`, `trash:///`,
  `computer:///`, `network:///`, and the desktop directory as a `file://`
  path) through `hidden-bookmarks`, so they have no on-disk form to edit.

`xfconf-query -c thunar -lv` lists what has actually been set, and the full
set of recognised property names is only in the binary —
`strings .thunar-wrapped | grep -E '^(misc|last|hidden)-'` is how to find one.
Thunar's own preferences dialog exposes a fraction of them.
