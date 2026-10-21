# The file manager

Ownership: `hosts/nix/modules/system/applications.nix` installs and integrates
Thunar. `hosts/nix/modules/home/applications.nix` declares its bookmarks,
xfconf settings and MIME defaults.

Thunar uses `services.tumbler` for thumbnails and `programs.xfconf` for
settings persistence. Without these services, it draws no previews and remembers
no view state. Neither failure is logged.

The GNOME session services that modern Nautilus assumes are all absent here.
This causes a **25-second stall, not an error**:

- `org.freedesktop.Tracker3.Miner.Files` and Localsearch are not activatable,
  and `org.gnome.Mutter.ServiceChannel` has no owner. Each is reported once at
  startup and each fails in milliseconds. These messages appear immediately
  above the stall but do not cause it.
- The stall itself is the D-Bus default reply timeout. Opening a folder from
  another application uses xdg-desktop-portal, which calls `ShowItems`
  on `org.freedesktop.FileManager1`. This activates the file manager through D-Bus
  under `systemd --user` as `dbus-:1.2-org.freedesktop.FileManager1@N.service`.
  The call returns `Failed to call ShowItems: Timeout was reached` exactly
  25s later, every time. Inside the process, GTK4's synchronous
  `org.freedesktop.portal.Settings` read at startup has the same 25s timeout:
  `Couldn't read the color-scheme setting: Timeout was reached`.

Compare direct file-manager startup with portal activation to distinguish the
two failures. Direct startup takes less than a second. A direct
`FileManager1.ShowItems` call answers in well under a second.
These measurements identify the activation path, not the program, as the cause
of the slow open.

`journalctl --user` shows these events. A terminal only shows the
last message printed before the wait.

Its settings live in two different places, and only one of them is a file:

- **The sidebar bookmarks are `gtk.gtk3.bookmarks`.** Home Manager writes the
  GTK file shared with every GIO browser, not a Thunar format, as a read-only
  store symlink. This disables "Add Bookmark" and dragging a folder onto the
  sidebar. Edit the list through the attribute.
  `xdg.configFile."gtk-3.0/bookmarks".force = true` permits replacing an unmanaged
  bookmarks file created by the application before the first activation.
- **Everything else is xfconf**, declared through `xfconf.settings.thunar`.
  Home Manager applies these values with `xfconf-query` at activation instead
  of managing a file. Each switch reapplies declared values, so GUI changes to
  them do not persist. Undeclared values remain Thunar-owned.
  `hidden-bookmarks` addresses built-in sidebar entries by URI:
  `recent:///`, `trash:///`, `computer:///`, `network:///`, and the desktop directory
  as a `file://` path. These entries have no on-disk form to edit.

`xfconf-query -c thunar -lv` lists the values that have been set.
The full set of recognised property names is only in the binary.
Use `strings .thunar-wrapped | grep -E '^(misc|last|hidden)-'` to find a property.
Thunar's own preferences dialog exposes a fraction of them.
