# OpenDeck (Stream Deck MK.2)

`hosts/nix/modules/system/flatpak.nix` installs OpenDeck as a user Flatpak.
Two sandbox permissions control its integration:
`shared=network` makes `127.0.0.1:9090` reachable from inside.
`org.freedesktop.Flatpak=talk` allows host commands with Unicode preserved.

**A plugin that talks to another program reaches it through the sandbox too.**
The Discord plugin speaks Discord's RPC protocol over
`$XDG_RUNTIME_DIR/discord-ipc-0`. A sandbox's runtime directory contains
only granted resources. `flatpak-bootstrap` grants that one socket.
Without the grant, the plugin reports **"Failed to connect to Discord: Could
not find the IPC pipe"**, although the host can see the socket.
Neither side logs this failure. Check sandbox visibility with
`ls "$XDG_RUNTIME_DIR"` under `flatpak run
--command=sh me.amankhanna.opendeck`.
The grant names the socket file rather than a directory, so binding occurs at
sandbox startup. Discord must already be running. If OpenDeck starts first,
the same error persists until OpenDeck restarts.
The plugin's own descriptors prove a live connection:
`readlink /proc/<pid>/fd/*` yields socket inodes. `ss -x -a` pairs one of them
with the `/run/user/1000/discord-ipc-0` endpoint.

**Its profile JSON is GUI-owned. Do not write it by hand.**
OpenDeck discards a manually written key entry in
`profiles/<serial>/Default.json` on startup. It resets the file to the empty
15-null form without logging either action.
The published source does not contain the on-disk `DiskActionInstance` shape,
so its fields cannot be derived. Create one key in the GUI and copy the exact
shape. Use absent-only seeding if a declarative initial profile is needed.

Two built-in actions exist that no plugin manifest lists: `opendeck.multiaction`
and `opendeck.toggleaction` (the two-state toggle).

A key's command is written plainly: `vpnp`. The Run Command action checks
`FLATPAK_ID`/`CONTAINER_ID`. It wraps commands in `flatpak-spawn --host`
(or `distrobox-host-exec`), so they already run on the host.

A shell started in the sandbox does not represent the keys' command environment.
There, `vpn` is absent from PATH and its absolute store path does not resolve.
The sandbox has Flatpak's own `/nix/store`, with roughly 38 entries.
Thus, `ls /nix` does not prove access to the host store.
Test with a full path to a known host binary.
A native plugin executed inside this sandbox cannot rely on the host store.
It must be statically linked or carry its runtime inside the sandbox.
