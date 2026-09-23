# Services and performance — host nix

Sources: `hosts/nix/boot.nix`, `hosts/nix/hardware-policy.nix`,
`hosts/nix/lighting.nix`, `hosts/nix/storage.nix`, and
`hosts/nix/modules/system/{nix,security,session,gaming,flatpak,maintenance}.nix`.
Operator procedures: [docs/nix.md](../../../../docs/nix.md). For validation use
[nixcfg-validation](../../nixcfg-validation/SKILL.md); any activation or disruptive
runtime experiment needs operator approval.

## Polkit subjects under UWSM

`hosts/nix/modules/system/session.nix` starts Hyprland through greetd/UWSM.
The compositor and its children run under the user manager, not greetd's logind
session scope. For those sessionless subjects, an `allow_active` polkit grant
does not apply: login1 falls back to `auth_admin_keep`, and an authentication
agent registered to a session cannot answer on their behalf. A power picker
can close while `systemctl poweroff`, `reboot`, or `suspend` fails with
“Interactive authentication required.” `uwsm stop` is a user-manager logout
operation and is not this authorization path.

`hosts/nix/modules/system/security.nix` grants only the enumerated login1 power
and PC/SC action IDs to `ri`. Do not replace this with a broad authorization
rule. To distinguish policy failure from a broken picker, run
`pkcheck --action-id org.freedesktop.login1.power-off --process PID` against the
actual caller and inspect its unit/session. From the same context, `busctl call
org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager
CanPowerOff` should report `yes`, not `challenge`, when the rule applies.

PC/SC uses the polkit-enabled pcsclite package when polkit is enabled. Both
`org.debian.pcsc-lite.access_pcsc` (context) and
`org.debian.pcsc-lite.access_card` (card) are in the same narrow rule. A refused
client is disconnected: Yubico Authenticator can say the daemon is missing
while pcscd is running. Check the pcscd journal for “Rejected unauthorized
PC/SC client” rather than reinstalling it or changing token credentials.

## Crash resilience

Root is XFS: metadata journaling does not guarantee unflushed file contents
survive an unclean stop. An apparently valid store path can contain a zero-length
or damaged file. Preserve the paired settings in
`hosts/nix/modules/system/nix.nix`:

- `fsync-store-paths = true` flushes paths before registration as valid.
- `auto-optimise-store = false` avoids pooling identical files through hardlinks
  in `/nix/store/.links`, where one corrupt shared file affects multiple paths.

`nix-store --verify --check-contents` detects corrupt contents. A source with no
substituter cannot be repaired by downloading it; it must be re-imported after
safe removal. Do not casually delete referenced store paths or recovery
closures. `hosts/nix/storage.nix` enables XFS scrub timers and error reporting;
scrubbing metadata is not a backup of file contents.

`hosts/nix/boot.nix` syncs journald every 30 seconds, enables a 30-second runtime
watchdog and a three-minute reboot watchdog. Watchdog evidence helps distinguish
a hang from power loss; absence of a final log is not proof of an application
fault. `split_lock_detect=off` avoids system-wide stalls caused by frequent
split-lock traps from affected Steam workloads.

## Scheduling and asymmetric CCDs

`hosts/nix/modules/system/gaming.nix` uses ananicy-cpp with CachyOS rules;
there is no configured sched_ext service. Priority rules are not CPU affinity:
the CachyOS `cpuNN` cgroups are quotas used only by rules explicitly naming them.
Do not infer game placement from a `Game` priority rule.

The 9950X3D CCDs are asymmetric: cores 0–7 have 96 MB L3 and cores 8–15 have
32 MB. CPPC performance rankings alone do not distinguish the cache-rich half.
`hosts/nix/hardware-policy.nix` sets `amd_x3d_mode=cache` through udev with
`DRIVER=="amd_3d_vcache"`. The attribute appears only after driver binding;
keying on the driver waits for that event, unlike a racing tmpfiles/boot write.
Read `amd_x3d_mode` back for confirmation; there is no scheduler log confirming
the preference.

With `amd_pstate=active`, EPP is the bias, not the governor. amd-pstate-epp's
`powersave` governor is dynamic mode, not a fixed low-power mode. The udev rule
sets `cpufreq/energy_performance_preference=performance` on CPU devices. The
`performance` governor instead pins minimum performance at the maximum and
makes EPP inert; do not conflate the two.

Do not re-enable scx_lavd as a generic performance tweak. A runnable-task stall
can freeze the whole desktop until the sched_ext watchdog ejects the scheduler;
`Restart=` can repeat that cycle. The named victim may be a game worker,
Vulkan submission, or Chromium thread, not the cause. Diagnose with
`journalctl -b -g 'EXIT:'`, the scheduler service restart count, and samples of
process CPU ticks and `/proc/pressure/{cpu,io,memory}`. Zero victim CPU ticks,
high CPU pressure, low I/O/memory pressure, and no `D` state point toward
starvation rather than a blocked application or busy GPU. Any proposed
sched_ext change needs matched kernel/userspace BPF interfaces and real workload
proof; missing struct_ops members or deprecated direct task-field writes are
compatibility warnings, not evidence that restarting will fix it.

## Allocator and kernel hardening boundaries

`hosts/nix/modules/system/security.nix` selects `graphene-hardened-light` via
`/etc/ld-nix.so.preload`. The light template retains zero-on-free and slab
canaries without quarantines, slot randomization, or per-allocation guard slabs.
Allocator changes can expose latent memory bugs, including use-after-free that
now reads zeroes; an abort need not implicate the most recent application edit.
An approved `provider = "libc"` reproduction is a diagnostic bisect, not a
permanent workaround. Programs using their own allocators, such as Chromium's
PartitionAlloc or a JVM heap, are mostly outside the replaced malloc boundary.

Only processes started after activation see the new allocator; a running
session is mixed until restarted. Use a **verified** known-working generation
for recovery, not an assumption that every older generation used libc.

AppImages wrapped by `appimageTools` run under bwrap with `--tmpfs /etc` and
only the FHS environment's own files bound back. The host preload file is
absent there. A host allocator-provider bisect therefore cannot diagnose those
payloads; inspect the actual wrapper before attributing their crashes to it.
See [desktop-applications](../../desktop-applications/SKILL.md) for package scope.

`hosts/nix/lighting.nix` isolates OpenRGB because its libusb backend uses
`RTLD_DEEPBIND`, conflicting with the global allocator preload. `openrgb-off`
bind-mounts an empty file over the preload source in its private mount namespace.
Do not disable hardened_malloc system-wide for lighting. The bounded root-only
oneshot turns ENE DRAM and the Gainward RTX 3090 Off; MSI's controller uses
Direct/black because it has no Off mode. Elgato/Wooting detection is disabled
and explicit selectors exclude them. No SDK server, GUI, polling, or global
user-device permissions are needed.

`hosts/nix/boot.nix` uses the cached latest kernel with `vsyscall=none`,
`slab_nomerge`, and `page_alloc.shuffle=1`; `init_on_free` is deliberately absent
because of its gaming cost. Do not assume a maintained hardened-kernel/profile
option exists in the locked Nixpkgs. A custom kernel configuration loses cache
coverage and can make daily upgrades build the kernel and out-of-tree NVIDIA
module. Check actual kernel/module compatibility before proposing RANDSTRUCT,
CFI, lockdown, or signing changes; they are not free hardening toggles for this
GPU stack.

## systemd startup and staged updates

Do not put slow **oneshot installation/update work** in `default.target`'s
login path: a blocking job can wedge `nixos-rebuild switch` at user-unit reload.
Use timers, bounded `TimeoutStartSec`, and visible failures rather than
`|| true`. `hosts/nix/modules/system/flatpak.nix` starts bootstrap from a timer
with a ten-minute timeout. Use `dl.flathub.org`, not `flathub.org`, for the remote;
unreachable remote setup can hang instead of failing promptly. This timer rule
is not a blanket ban on ordinary session daemons: the local Telegram proxy in
`hosts/nix/modules/home/applications.nix` is a `default.target` service.

Prefer package-shipped units using `systemd.packages` and an explicit
`wantedBy`: NixOS does not act on a packaged unit's `[Install]`. Inspect package
outputs before inventing `ExecStart`; hyprpolkitagent lives in `libexec`, not
`bin`. `Restart=on-failure` can hide an endless `203/EXEC` loop rather than fix
it. `hosts/nix/modules/system/session.nix` uses the packaged hyprpolkitagent and
hyprsunset units, targeted to `graphical-session.target`.

`hosts/nix/modules/system/maintenance.nix` configures daily auto-upgrades with
`operation = "boot"`: build and stage for next boot, do not disturb the running
session. Compare `/run/booted-system` with `/nix/var/nix/profiles/system` to
identify pending activation. Preserve recovery generations, especially before
boot/authentication changes. See [Auto-updates](../../../../docs/nix.md#auto-updates)
and [boot recovery](boot-auth-secrets.md#boot-evidence-and-recovery).
