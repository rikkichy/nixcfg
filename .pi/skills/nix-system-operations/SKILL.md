---
name: nix-system-operations
description: NixOS and Home Manager safety and operations for this machine, including initrd and LUKS, crash resilience, CPU scheduling, hardened_malloc, systemd units, auto-upgrades, polkit, and mihomo VPN. Use when changing configuration.nix, hardware-configuration.nix, flake inputs, boot, services, security, performance, updates, or networking.
---

# Nix System Operations

Detailed engineering reference for this NixOS configuration. Read the relevant section before changing the subsystem; the counterintuitive constraints and verification methods are part of the design.

### boot.initrd — the one place a mistake costs a live USB

`hardware-configuration.nix` already declares the root LUKS device as
`boot.initrd.luks.devices."cryptroot"`, named after the mapping opened during
install, and `fileSystems."/"` mounts `/dev/mapper/cryptroot`.
`configuration.nix` may only *add* to that attribute
(`…devices."cryptroot".allowDiscards = true`). These are attribute names, not
device paths, so a differently-named entry aimed at the same partition defines a
**second mapping** rather than overriding the first. The generated crypttab then
carries two lines, systemd emits one `systemd-cryptsetup@` unit per line, and
they race for the partition; the loser finds it busy, and when the loser is
`cryptroot` the root device never appears. Being a race, it booted three times
before stranding the machine.

Verifying a change here needs care, because the usual signals do not apply:

- **initrd changes take effect only on reboot**, so a successful `switch` proves
  nothing about them. Read the generated crypttab directly:
  `cat $(nix eval --raw '.#…config.boot.initrd.systemd.contents."/etc/crypttab".source')`.
- **Never infer the current generation from `ls`** — it sorts lexically, so
  `system-10-link` lands *above* `system-7-link` and a `tail` silently shows a
  stale one. This produced a confident, wrong "the fix was never applied".
  `readlink /nix/var/nix/profiles/system` is the authority.
- Ground truth for what will actually boot is `/boot/limine/limine.conf`:
  each `//Generation N` block names its own `module_path` initrd, so comparing
  those store hashes shows exactly which generations carry the change.

Two home-manager behaviours that waste time if assumed otherwise:

- **`xdg.desktopEntries` are installed as packages, not files.** They land in
  `/etc/profiles/per-user/ri/share/applications/`, *not*
  `~/.local/share/applications/`, and the module gates only on
  `desktopEntries != {}` — it is unaffected by `xdg.enable` (which is `false`
  here). An empty `~/.local/share/applications` proves nothing.
- **`find` will not traverse symlinks into the store.** Profile directories are
  symlink farms, so `find /etc/profiles/... -name foo.svg` reports nothing for
  files that plainly exist. Use `find -L`. This produces very convincing false
  evidence that a package or icon is missing.

### Power actions and polkit — why a menu entry can be a dead key

`systemctl poweroff`, `reboot` and `suspend` are logind calls and logind asks
polkit, whose shipped policy answers `yes` only on the `allow_active` branch —
which requires the caller to be in a logind session. **Nothing on this desktop
is.** `session-1.scope` holds greetd and the uwsm bootstrap; with `withUWSM`
the compositor is a unit under `user@1000.service`, and so is everything it
spawns, where there is no session at all. Those callers fall to `allow_any`,
`auth_admin_keep`, and hyprpolkitagent cannot answer for them either — an agent
is registered against a session, and a sessionless subject matches none. The
call returns `Interactive authentication required.` on stderr, which from a
keybind or a bar button goes nowhere: the menu takes the click, closes, and the
machine stays up.

`security.polkit.extraConfig` grants those ids to `ri` for that reason. The
measurement that separates this from every other cause is `pkcheck --action-id
org.freedesktop.login1.power-off --process <pid>`: a pid inside
`session-1.scope` comes back authorized and silent, while any pid from the
desktop prints `polkit.result=auth_admin_keep`. `busctl call
org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager
CanPowerOff` says `challenge` from the same place, and `yes` once a rule
applies.

`uwsm stop` is not part of this — logging out is a user-manager operation and
was never gated.

**The sessionless subject reaches further than the power menu.** `services.pcscd`
resolves its package to `pcscliteWithPolkit` whenever `security.polkit.enable`
is on, and that daemon asks polkit about every client — `access_pcsc` to open a
context, `access_card` to reach the card — on the same `allow_active`-only
defaults. A refused client is simply disconnected, so it has no way to tell a
refusal from an absent daemon: Yubico Authenticator reports **"Failed to open
smart card connection: make sure pcscd is installed and running"** while pcscd
is running and `systemctl status pcscd` scrolls `Rejected unauthorized PC/SC
client` for that pid. Those two ids are in the same rule for that reason.

### Crash resilience

Root is XFS, which journals metadata and not contents, so a file written and
not yet flushed comes back **at length zero** after an unclean stop rather than
with its previous contents. Two `nix.settings` follow from that:

- `fsync-store-paths = true` flushes a path before it is registered valid.
  Without it the store can hold an empty file it believes is complete, and a
  build fails pointing at something that looks perfectly normal on disk.
- `auto-optimise-store = false`. Optimisation hardlinks identical files into
  `/nix/store/.links`, so a path is a share in a pool rather than a file: one
  corrupt link takes every path pointing at it. `nix-store --verify
  --check-contents` reports these; flake sources have no substituter and cannot
  be repaired, only deleted and re-imported.

`journald` syncs every 30s rather than the 5-minute default, so an unclean stop
loses seconds of log instead of minutes. The board's SP5100 watchdog is enabled
via `systemd.settings.Manager.RuntimeWatchdogSec`, which recovers a hang and
distinguishes one from a power cut — a hang leaves a watchdog entry, a power
cut leaves nothing at all.

`split_lock_detect=off` is a kernel param because Steam's HTTP thread issues
atomic operations that straddle a cache line at a rate of roughly ninety per
minute, and each trap stalls every core rather than the offending thread.

### Scheduling — the CCDs are asymmetric, and sched_ext is not used

`ananicy-cpp` with the CachyOS rules is the whole of the priority side. `cs2`
matches a rule of type `Game` there, which is `nice -5` and best-effort I/O.
The three `cpuNN` cgroups those rules define are CPU quotas a rule has to ask
for by name, and no game rule does.

**The two CCDs are not interchangeable.** Cores 0–7 sit under 96 MB of L3 and
cores 8–15 under 32 MB, while `acpi_cppc/highest_perf` reads the same sequence
across both — so nothing in the topology tells the scheduler which half a
lightly threaded workload belongs on. `amd_3d_vcache` exposes the one knob for
it, `amd_x3d_mode` on the ACPI device `AMDI0101:00`, and a udev rule in
`configuration.nix` sets it to `cache`, the 96 MB half. Two things about that:

- **The attribute does not exist until the driver binds.** The ACPI device
  appears with nothing under it, udev loads `amd_3d_vcache` from its MODALIAS,
  and the bind event that follows is the first moment there is something to
  write to. Keying the rule on `DRIVER=="amd_x3d_vcache"` is what waits for
  that — the key is empty on `add` and set only on `bind` — where tmpfiles or
  a boot script would race the module load.
- **Reading the attribute back is the only confirmation.** Neither the kernel
  nor the scheduler logs which CCD it is favouring, so `cat` on `amd_x3d_mode`
  is the check — there is no corroborating signal short of pinning a thread
  and measuring cache misses.

**`energy_performance_preference` is the bias, not the governor.**
`amd_pstate=active` selects amd-pstate-epp, which offers only `performance`
and `powersave` and treats `powersave` as its dynamic mode rather than a
low-power one. The driver's own default for EPP is `balance_performance`; the
same udev block sets it to `performance` on every `cpu` device, reached through
the `cpufreq` symlink each one carries into its policy. Selecting the
`performance` governor covers this by pinning `min_perf` to the maximum on all
32 threads, which also makes EPP inert.

`scx_lavd` starves runnable tasks on this kernel. A task goes unscheduled past
the sched_ext watchdog's threshold and the kernel ejects the scheduler:

```
sched_ext: BPF scheduler "lavd_1.1.3_…" disabled (runnable task stall)
Error: EXIT: runnable task stall (Vulkan Submissi[71729] failed to run for 35.829s)
```

`Restart=` then brings it back into the same failure a minute later, so the
machine takes one 35–45s freeze per cycle for as long as it is enabled. Some
ejections read `runtime error (RCU CPU stall detected!)` instead.

What makes this hard to attribute is that the freeze is **system-wide and
self-healing**. It ends when the watchdog fires, so whatever was on screen
looks like it hung and recovered by itself, and the threads the ejection names
are simply those of whichever process has the most of them — a game's
`Job.Worker`s and `Vulkan Submissi`, a Chromium `VizCompositorTh`. The
scheduler is never the thing that appears to be at fault.

The measurements that name it rather than the program that seems to hang:
`journalctl -b -g 'EXIT:'` gives the starved thread and the duration, and
`systemctl show scx -p NRestarts` counts the cycles. During a stall the suspect
process burns **zero CPU ticks** over a multi-second sample, `/proc/pressure/io`
and `memory` are flat zero and no thread sits in `D`, while `/proc/pressure/cpu`
reads `some avg10=67` — nothing is working and everything is waiting for a CPU.
A GPU at 19% and 31W says the same thing from the other end.

Re-enabling it needs a matched pair, which `scx_full-1.1.3` and this kernel are
not: libbpf logs six struct_ops members it cannot find (`init_cids`,
`cid_shard_size`, `rescue_quantum_us`, …) while the kernel answers that writing
`p->scx.slice`/`dsq_vtime` directly is deprecated. Each is built against an ABI
the other does not have.

### Hardening — read this before debugging a new crash

`environment.memoryAllocator.provider = "graphene-hardened-light"` puts
GrapheneOS hardened_malloc under everything, through `/etc/ld-nix.so.preload`.
The light template keeps zero-on-free and slab canaries and drops the
quarantines, slot randomisation and per-allocation guard slabs.

**This changes what a crash means.** hardened_malloc introduces no bugs; it
stops tolerating ones that were already there. A use-after-free that reads
plausible garbage under glibc reads zeroes here and dereferences NULL, so the
abort lands in the program that was already wrong, often far from any recent
change. Confirm by setting the provider to `libc` and reproducing before
chasing anything else. Programs carrying their own allocator — Chromium's
PartitionAlloc, a JVM heap — are mostly untouched, since the preload only
replaces `malloc`.

The allocator applies to processes started after a `switch`, so a running
session is a mix until things are restarted. It lives in the system closure,
which means an older generation in limine is already free of it.

**An AppImage never sees it.** `appimageTools` runs the payload under bwrap
with `--tmpfs /etc`, and only the FHS environment's own files are bound back
in, so `/etc/ld-nix.so.preload` does not exist inside the sandbox and the
loader finds nothing to preload. `lmstudio`, `nokochat` and `wootility` are on
plain glibc `malloc` however the provider is set, which means the
`provider = "libc"` bisect above cannot tell you anything about a crash in any
of them.

There is **no hardened kernel to switch to**: `linuxPackages_hardened` and
`profiles/hardened` were both removed in 26.05, the kernel for lack of
maintenance and the profile for being "a grab bag of settings" rather than a
policy. Building one here is the wrong trade anyway — a custom config drops out
of the binary cache, so `autoUpgrade` would compile a kernel and the
out-of-tree NVIDIA module daily. Auditing `/proc/config.gz` against KSPP shows
stock already carries the settings worth having (`SLAB_FREELIST_HARDENED`,
`HARDENED_USERCOPY`, `INIT_ON_ALLOC_DEFAULT_ON`, `RANDOMIZE_KSTACK_OFFSET`,
`STRICT_DEVMEM`, and the rest), while `RANDSTRUCT` and `CFI_CLANG` fight the
proprietary GPU module and `SECURITY_LOCKDOWN_LSM` would refuse to load an
unsigned `nvidia.ko` in a kernel built without `CONFIG_MODULE_SIG`.

What is reachable is three kernel parameters, described where they are set.
`init_on_free` is deliberately not among them: it is the most valuable and the
only one that costs measurably, and this machine also runs games.

### systemd units in `configuration.nix`

Keep long-running or network-dependent **user** units off `default.target` and
drive them from a timer. Anything in the login target sits in the path of
`reloading user units for ri` during `nixos-rebuild switch`, and a unit that
blocks wedges the entire switch with no indication of why —
`flatpak-bootstrap` did exactly this. Bound them with `TimeoutStartSec` and let
them fail visibly rather than `|| true`, which produces green units that did
nothing.

Prefer a unit the package already ships (`systemd.packages = [ pkg ]`, plus an
explicit `wantedBy` — NixOS does not act on a packaged unit's `[Install]`) over
hand-writing one with an interpolated `ExecStart`. A local copy of
hyprpolkitagent's unit pointed at `$out/bin/hyprpolkitagent`; the binary lives in
`$out/libexec` and the package ships no `bin/` at all, so it failed `203/EXEC`
and restarted **2673 times** without anything surfacing. Check `$out` before
interpolating a path, and treat `Restart=on-failure` as something that hides
this class of bug rather than mitigating it.

Network note: `flathub.org` is unreachable from this machine and `flatpak
remote-add` hangs on it indefinitely rather than failing; use `dl.flathub.org`.
`tg-ws-proxy` exists for similar reasons.

`system.autoUpgrade` builds daily and **stages for next boot**
(`operation = "boot"`), so upgrades never disturb a running session.

### The VPN (mihomo) — failures here all look like "the internet is broken"

`services.mihomo` is a `DynamicUser` unit whose only privilege is
`CAP_NET_ADMIN`, granted by `tunMode`. Config is `dotfiles/mihomo.yaml` with two
placeholders spliced in at boot from `/etc/mihomo/` — the subscription URL is a
credential and the repo is public, so **it must never be committed, quoted in a
commit message, or pasted into this file**.

Three things here produce no log line anywhere:

- **The panel gates on device id, and failure is silent and valid.** Without an
  `x-hwid` header the subscription answers `200 OK` with a well-formed 1.4 KB
  profile containing a single node named `App not supported` pointed at
  `0.0.0.0:1`. mihomo starts happily, `MATCH,PROXY` selects it, and every
  connection dies with `connection refused` — so the *internet* looks broken
  while the subscription looks healthy. With the header the same URL returns 46
  nodes. User-Agent is a different axis entirely: it controls response *format*
  (`clash.meta` → YAML, generic → base64), not access. Chasing the UA is a dead
  end; check `x-hwid` first.
- **mihomo fetches its own subscription through its own tunnel** unless the
  provider carries `proxy: DIRECT`. `MATCH,PROXY` routes the update into the
  very nodes it is trying to download, so a bad update can never repair itself.
  It works exactly once, on first start, by racing the routing rules into
  place, and then surfaces as a bare `EOF`.
- **Node latency needs two endpoints merged.** `/proxies/PROXY` knows which
  nodes the group offers but holds no history for them — only the nine
  built-ins (`DIRECT`, `AUTO`, `REJECT`, …) are top-level entries in
  `/proxies`. `/providers/proxies` holds the health-check history but not group
  membership. Reading either alone gives a complete-looking, wrong answer.

**Run `vpn off` before any network-heavy work.** Through a node, `nixos-rebuild`
hangs on substituter fetches until it is killed and `git push` fails with a TLS
`unexpected eof`. Neither failure names the tunnel, and the rebuild one reads
convincingly as a broken derivation.

The off switch is `DIRECT` as an explicit member of the `PROXY` select group,
not stopping the unit — stopping mihomo also drops the DNS hijack.
`profile.store-selected` makes the choice survive reboot, cached in `cache.db`
under the unit's `StateDirectory`. Without it the group silently resets to its
first member on every start, which reads as the VPN switching itself back on.

`vpn` is a `writeShellApplication` in `environment.systemPackages`, deliberately
not a shell alias: the same command has to work from fish, from the Hyprland
keybind, and from the Stream Deck. It selects nodes by
regex against live group membership (`vpn use 🇸🇪`) rather than by literal name,
because node names carry numbering and suffixes the provider changes without
notice — and because a second subscription would name things differently again.
