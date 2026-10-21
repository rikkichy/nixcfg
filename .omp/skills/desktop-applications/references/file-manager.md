# Yazi file manager

`hosts/nix/modules/home/applications.nix` owns native Home Manager Yazi settings,
its Foot launcher, desktop-entry override and folder MIME association.
The Linux desktop guide owns [usage and post-activation checks](../../../../docs/nix.md).

## Launch and palette boundaries

The desktop entry overrides upstream's terminal-dependent launch with an explicit
Foot invocation. Home Manager gives this entry priority over the packaged entry.
Hyprland and desktop folder opening share `yazi-open`. Forward paths as argv,
never interpolate them into shell code. Keep `Terminal=false` because the launcher
creates its own terminal.

The session reads the existing writable OSC sequence file before executing Yazi.
Do not generate another palette or start an interactive shell to initialize it.
A missing palette must not prevent browsing. The native Fish wrapper runs inside
the current terminal and returns the selected directory to Fish.

## Desktop integration limits

Yazi does not own `org.freedesktop.FileManager1`. The desktop portal can fall back
to opening a parent directory, but selection is lost. Direct D-Bus callers without
a fallback may fail. Do not silently retain a GUI file manager or introduce a bridge.
GTK file dialogs and GVFS remain independent of Yazi. File Roller and Catfish
remain available as standalone applications.

`gtk.gtk3.bookmarks` still owns GTK dialog bookmarks as a read-only store symlink.
Its `xdg.configFile."gtk-3.0/bookmarks".force` setting adopts an unmanaged file.
Yazi's quick locations use native keymap entries, not the GTK bookmark file.
