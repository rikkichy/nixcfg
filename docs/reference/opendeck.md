# OpenDeck (Stream Deck MK.2)

Source ownership paths below are repository-relative. The
[session startup](../nix.md#session-application-startup) and
[native plugin](../nix.md#opendeck-vtube-studio-native) operator sections own
lifecycle and installation procedures.

`hosts/nix/modules/system/flatpak.nix` installs OpenDeck as a user Flatpak.
Two sandbox permissions control its integration:
`shared=network` makes `127.0.0.1:9090` reachable from inside.
`org.freedesktop.Flatpak=talk` allows host commands with Unicode preserved.

**A plugin that talks to another program reaches it through the sandbox too.**
The Discord plugin speaks Discord's RPC protocol over a `discord-ipc-N` socket.
A sandbox's runtime directory contains only granted resources.
Without a reachable socket, the plugin reports **"Failed to connect to Discord:
Could not find the IPC pipe"**, although the host can see the socket.
Neither side logs this failure.

A file grant such as `xdg-run/discord-ipc-0` binds the socket inode at sandbox
startup. If Discord starts after OpenDeck, or restarts, the sandbox keeps the dead
inode and every reconnect fails until OpenDeck restarts. The plugin's IPC crate
picks the first *existing* candidate path in hash-set order and never falls back,
so a stale bound socket also shadows any working path.

Instead, the `opendeck` unit revokes that file grant and grants the directory
`xdg-run/app/com.discordapp.Discord`, one of the plugin's candidate paths. The
socket-activated `opendeck-discord-ipc` user unit listens there and
`systemd-socket-proxyd` forwards each connection to the live
`$XDG_RUNTIME_DIR/discord-ipc-0`. The sandbox still reaches only Discord RPC.
When Discord is absent, the relay closes the connection and the plugin retries.
Flatpak bootstrap applies the same grant to Sober, whose manifest also requests
the pinned socket file.
Overrides apply at sandbox start: launch OpenDeck through
`systemctl --user restart opendeck`, not the app menu, after changing them.

Check sandbox visibility with `ls "$XDG_RUNTIME_DIR/app/com.discordapp.Discord"`
under `flatpak run --command=sh me.amankhanna.opendeck`.
The plugin's own descriptors prove a live connection:
`readlink /proc/<pid>/fd/*` yields socket inodes. `ss -x -a -p` pairs one of them
with `systemd-socket-proxyd`, which in turn connects to `/run/user/1000/discord-ipc-0`.

**Its profile JSON is GUI-owned. Do not write it by hand.**
OpenDeck discards a manually written key entry in
`profiles/<serial>/Default.json` on startup. It resets the file to the empty
15-null form without logging either action.
The published source does not contain the on-disk `DiskActionInstance` shape,
so its fields cannot be derived. Create one key in the GUI and copy the exact
shape. Use absent-only seeding if a declarative initial profile is needed.

Two built-in actions exist that no plugin manifest lists: `opendeck.multiaction`
and `opendeck.toggleaction` (the two-state toggle).

A key's command is written plainly: `quickshell -c expressive ipc call desktop toggle vpn`. The Run Command action checks
`FLATPAK_ID`/`CONTAINER_ID`. It wraps commands in `flatpak-spawn --host`
(or `distrobox-host-exec`), so they already run on the host.

Host execution is an operational boundary, not a harmless sandbox probe.
Testing a key or `flatpak-spawn --host` can change the live host; apply the
same approval gate as invoking that host action directly. Read-only sandbox
inspection does not authorize application launches, service restarts or VPN changes.

A shell started in the sandbox does not represent the keys' command environment.
There, `vpn` is absent from PATH and its absolute store path does not resolve.
The sandbox has Flatpak's own `/nix/store`, with roughly 38 entries.
Thus, `ls /nix` does not prove access to the host store.
Test with a full path to a known host binary.
A native plugin executed inside this sandbox cannot rely on the host store.
It must be statically linked or carry its runtime inside the sandbox.

The VTube Studio native plugin, property inspector, tests and static Linux
packaging belong to [rikkichy/vts-opendeck](https://github.com/rikkichy/vts-opendeck).
Edit them upstream; this checkout only pins and exposes the package.
Existing plugins and profiles remain application-owned. NixOS activation must
not install or migrate them; follow the operator runbook for a GUI installation.
