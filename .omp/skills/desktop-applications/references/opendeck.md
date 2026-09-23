# OpenDeck (Stream Deck MK.2)

Installed by `hosts/nix/modules/system/flatpak.nix` as a user Flatpak, so two sandbox permissions decide what is possible:
`shared=network` makes `127.0.0.1:9090` reachable from inside, and
`org.freedesktop.Flatpak=talk` allows host commands, Unicode intact.

**A plugin that talks to another program reaches it through the sandbox too.**
The Discord plugin speaks Discord's RPC protocol over
`$XDG_RUNTIME_DIR/discord-ipc-0`, and a sandbox's runtime directory contains
only what has been granted into it — `flatpak-bootstrap` grants that one
socket. Ungranted, the plugin answers **"Failed to connect to Discord: Could
not find the IPC pipe"** about a socket sitting in plain view on the host,
with nothing logged on either side. `ls "$XDG_RUNTIME_DIR"` under `flatpak run
--command=sh me.amankhanna.opendeck` is what settles which side is wrong. The
grant names the socket file rather than a directory, so the bind happens at
sandbox startup and Discord has to be running by then — OpenDeck started first
gives the same error until it is restarted. Ground truth for a live connection
is the plugin's own descriptors: `readlink /proc/<pid>/fd/*` yields socket
inodes, and `ss -x -a` pairs one of them against the
`/run/user/1000/discord-ipc-0` endpoint.

**Its profile JSON is GUI-owned — do not hand-author it.** A key entry written
by hand into `profiles/<serial>/Default.json` is discarded on startup and the
file reset to the empty 15-null form, with nothing logged either way. The
on-disk `DiskActionInstance` shape is not in the published source, so its
fields cannot be derived — create one key in the GUI and copy the exact shape,
then use absent-only seeding if a declarative initial profile is needed.

Two built-in actions exist that no plugin manifest lists: `opendeck.multiaction`
and `opendeck.toggleaction` (the two-state toggle).

A key's command is written plainly: `vpn toggle`. The Run Command action checks
`FLATPAK_ID`/`CONTAINER_ID` and wraps what it runs in `flatpak-spawn --host`
(or `distrobox-host-exec`), so it lands on the host already.

A shell started in the sandbox behaves differently, and taking it as evidence
gives the wrong answer for the keys: there `vpn` is off PATH and its absolute
store path does not resolve. `/nix/store` exists inside the sandbox — flatpak's
own, roughly 38 entries — so `ls /nix` looks reassuring and proves nothing; test
with a full path to a known host binary. A native plugin executed inside this sandbox cannot rely on the host store;
it must be statically linked or carry its runtime inside the sandbox.
