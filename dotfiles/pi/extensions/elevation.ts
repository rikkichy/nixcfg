import { spawnSync } from "node:child_process";
import { realpath, stat } from "node:fs/promises";
import {
	isToolCallEventType,
	type ExtensionAPI,
} from "@earendil-works/pi-coding-agent";
import { StringEnum } from "@earendil-works/pi-ai";
import { Type } from "typebox";

const SUDO = "/run/wrappers/bin/sudo";
const NIXCFG_FLAKE = "path:/home/ri/nixcfg#nix";
const LEASE_DURATION_MS = 10 * 60 * 1000;

const PROGRAMS = {
	"nixos-rebuild": "/run/current-system/sw/bin/nixos-rebuild",
	"systemctl": "/run/current-system/sw/bin/systemctl",
	"nix-store": "/run/current-system/sw/bin/nix-store",
	"nix-collect-garbage": "/run/current-system/sw/bin/nix-collect-garbage",
} as const;

type Program = keyof typeof PROGRAMS;

const PROGRAM_NAMES = Object.keys(PROGRAMS) as Program[];
const CONTROL_CHARACTER = /[\u0000-\u001f\u007f]/u;
const PRIVILEGE_COMMAND = /(^|[^a-z0-9_-])(sudo(?:-rs)?|doas|pkexec|run0|su)(?=$|[^a-z0-9_-])/iu;
const NIXOS_REBUILD_ACTIONS = new Set(["switch", "boot", "test"]);
const SYSTEMD_ACTIONS = new Set(["start", "stop", "restart", "reload", "try-restart", "reset-failed"]);
const SYSTEMD_UNIT = /^[a-zA-Z0-9_.:@-]+\.service$/u;

interface RunResult {
	status: number | null;
	signal: NodeJS.Signals | null;
	error?: string;
}

interface ElevationState {
	active: boolean;
	expiresAt?: number;
}

function quoteArgument(argument: string): string {
	if (/^[a-zA-Z0-9_@%+=:,./#-]+$/u.test(argument)) return argument;
	return `'${argument.replaceAll("'", `'"'"'`)}'`;
}

function formatCommand(executable: string, args: string[]): string {
	return [executable, ...args].map(quoteArgument).join(" ");
}

function validateText(value: string, label: string): void {
	if (CONTROL_CHARACTER.test(value)) {
		throw new Error(`${label} contains a control character`);
	}
}

function validateNixosRebuild(args: string[]): void {
	const [action, ...options] = args;
	if (!NIXOS_REBUILD_ACTIONS.has(action ?? "")) {
		throw new Error("nixos-rebuild elevation permits only switch, boot, or test");
	}

	const knownFlake = options.length === 2 && options[0] === "--flake" && options[1] === NIXCFG_FLAKE;
	const rollback = action === "switch" && options.length === 1 && options[0] === "--rollback";
	if (!knownFlake && !rollback) {
		throw new Error(`nixos-rebuild must use --flake ${NIXCFG_FLAKE}, or switch --rollback`);
	}
}

function validateSystemctl(args: string[]): void {
	if (args.length === 1 && args[0] === "daemon-reload") return;

	const [action, ...units] = args;
	if (!action || !SYSTEMD_ACTIONS.has(action) || units.length === 0) {
		throw new Error("systemctl elevation requires an allowed action and at least one .service unit");
	}
	if (!units.every((unit) => SYSTEMD_UNIT.test(unit))) {
		throw new Error("systemctl elevation accepts service unit names only; options and other unit types are denied");
	}
}

function validateNixStore(args: string[]): void {
	const verify = args.length === 2 && args[0] === "--verify" && args[1] === "--check-contents";
	const repair = args.length === 3
		&& args[0] === "--verify" && args[1] === "--check-contents" && args[2] === "--repair";
	if (!verify && !repair) {
		throw new Error("nix-store elevation permits only --verify --check-contents, optionally followed by --repair");
	}
}

function validateGarbageCollection(args: string[]): void {
	const deleteAllOld = args.length === 1 && args[0] === "-d";
	const deleteByAge = args.length === 2
		&& args[0] === "--delete-older-than"
		&& /^\d+[dhm]$/u.test(args[1] ?? "");
	if (!deleteAllOld && !deleteByAge) {
		throw new Error("nix-collect-garbage elevation permits -d or --delete-older-than <number>[d|h|m]");
	}
}

function validateArguments(program: Program, args: string[]): void {
	for (const [index, argument] of args.entries()) {
		validateText(argument, `argument ${index + 1}`);
	}

	switch (program) {
		case "nixos-rebuild":
			validateNixosRebuild(args);
			break;
		case "systemctl":
			validateSystemctl(args);
			break;
		case "nix-store":
			validateNixStore(args);
			break;
		case "nix-collect-garbage":
			validateGarbageCollection(args);
			break;
	}
}

async function validateSudo(): Promise<void> {
	const metadata = await stat(SUDO);
	if (
		!metadata.isFile() ||
		metadata.uid !== 0 ||
		(metadata.mode & 0o4000) === 0 ||
		(metadata.mode & 0o022) !== 0
	) {
		throw new Error(`${SUDO} is not a protected setuid-root executable`);
	}
}

async function validateExecutable(program: Program): Promise<string> {
	const configuredPath = PROGRAMS[program];
	const resolvedPath = await realpath(configuredPath);
	const metadata = await stat(resolvedPath);

	await validateSudo();
	if (!resolvedPath.startsWith("/nix/store/") || !metadata.isFile()) {
		throw new Error(`${configuredPath} does not resolve to an immutable Nix store executable`);
	}
	if (metadata.uid !== 0 || (metadata.mode & 0o022) !== 0 || (metadata.mode & 0o111) === 0) {
		throw new Error(`${resolvedPath} is not a root-owned, non-writable executable`);
	}
	return resolvedPath;
}

function sudoEnvironment(): NodeJS.ProcessEnv {
	// Root commands receive no Pi/provider credentials or user session variables.
	// sudo applies its own target-user environment policy on top of this minimum.
	return {
		PATH: "/run/wrappers/bin:/run/current-system/sw/bin",
		TERM: process.env.TERM ?? "xterm-256color",
		LANG: process.env.LANG ?? "C.UTF-8",
	};
}

function clearSudoTimestamp(): void {
	spawnSync(SUDO, ["-K"], { env: sudoEnvironment(), stdio: "ignore" });
}

function hasSudoCredential(): boolean {
	const result = spawnSync(SUDO, ["-n", "-v"], {
		env: sudoEnvironment(),
		stdio: "ignore",
	});
	return result.status === 0;
}

export default function (pi: ExtensionAPI) {
	let elevationInProgress = false;
	let leaseExpiresAt = 0;
	let leaseTimer: ReturnType<typeof setTimeout> | undefined;

	const publishState = () => {
		const active = leaseExpiresAt > Date.now();
		const state: ElevationState = active
			? { active: true, expiresAt: leaseExpiresAt }
			: { active: false };
		pi.events.emit("elevation:state", state);
	};

	const lock = () => {
		if (leaseTimer) {
			clearTimeout(leaseTimer);
			leaseTimer = undefined;
		}
		leaseExpiresAt = 0;
		clearSudoTimestamp();
		publishState();
	};

	const armLease = () => {
		if (leaseTimer) clearTimeout(leaseTimer);
		leaseExpiresAt = Date.now() + LEASE_DURATION_MS;
		leaseTimer = setTimeout(lock, LEASE_DURATION_MS);
		leaseTimer.unref?.();
		publishState();
	};

	const leaseIsActive = (): boolean => {
		if (leaseExpiresAt <= Date.now()) {
			if (leaseExpiresAt !== 0) lock();
			return false;
		}
		return true;
	};

	pi.on("session_start", () => {
		lock();
	});
	pi.on("session_shutdown", lock);
	pi.on("agent_start", () => {
		if (!leaseIsActive()) clearSudoTimestamp();
	});
	pi.on("agent_settled", () => {
		if (!leaseIsActive()) clearSudoTimestamp();
	});

	// The agent cannot bypass the approval tool with an ordinary bash call.
	// User-entered ! commands remain under the user's direct control.
	pi.on("tool_call", (event) => {
		if (isToolCallEventType("bash", event) && PRIVILEGE_COMMAND.test(event.input.command)) {
			return {
				block: true,
				reason: "Direct privilege escalation is blocked. Use elevated_exec while the user-controlled lease is active.",
			};
		}
	});

	pi.registerCommand("elevate", {
		description: "Unlock allowlisted root operations for ten minutes of inactivity",
		handler: async (_args, ctx) => {
			if (ctx.mode !== "tui") {
				ctx.ui.notify("Elevation is available only in an interactive TUI", "error");
				return;
			}
			if (typeof process.geteuid === "function" && process.geteuid() === 0) {
				ctx.ui.notify("Pi is already running as root; the elevation lease is disabled", "error");
				return;
			}

			await validateSudo();
			if (leaseIsActive() && hasSudoCredential()) {
				armLease();
				ctx.ui.notify("Root access lease renewed for ten minutes", "info");
				return;
			}
			lock();

			const approved = await ctx.ui.confirm(
				"Unlock root access?",
				"For ten minutes of inactivity, the agent may request allowlisted root commands. Every exact command still needs your confirmation. Direct sudo and shell execution remain blocked.",
			);
			if (!approved) return;

			const result = await ctx.ui.custom<RunResult>((tui, _theme, _keybindings, done) => {
				tui.stop();
				process.stdout.write("\x1b[2J\x1b[H");
				process.stdout.write("Pi root access lease\n\nAuthenticate once to unlock allowlisted commands.\n\n");

				let authentication: RunResult;
				try {
					clearSudoTimestamp();
					const command = spawnSync(
						SUDO,
						["-v", "-p", "Pi elevation password: "],
						{ env: sudoEnvironment(), stdio: "inherit" },
					);
					authentication = {
						status: command.status,
						signal: command.signal,
						error: command.error?.message,
					};
				} catch (error) {
					authentication = {
						status: null,
						signal: null,
						error: error instanceof Error ? error.message : String(error),
					};
				} finally {
					process.stdout.write("\nReturning to Pi...\n");
					tui.start();
					tui.requestRender(true);
				}

				done(authentication);
				return { render: () => [], invalidate: () => {} };
			});

			if (result.error || result.status !== 0 || !hasSudoCredential()) {
				lock();
				ctx.ui.notify(result.error ?? "Authentication failed; root access remains locked", "error");
				return;
			}

			armLease();
			ctx.ui.notify("Root access unlocked for ten minutes of inactivity", "warning");
		},
	});

	pi.registerCommand("elevation-lock", {
		description: "Immediately revoke the root access lease",
		handler: async (_args, ctx) => {
			const wasActive = leaseIsActive();
			lock();
			ctx.ui.notify(wasActive ? "Root access locked" : "Root access was already locked", "info");
		},
	});

	pi.registerTool({
		name: "elevated_exec",
		label: "Elevated Exec",
		description:
			"Run one strictly allowlisted administration command during a user-unlocked root lease. The user confirms the exact argv; commands use no shell, and output is never sent to the model. The lease is opened with /elevate and expires after ten minutes of inactivity. Supported programs: nixos-rebuild, systemctl, nix-store, nix-collect-garbage.",
		promptSnippet: "Request a narrowly scoped root operation during a user-controlled lease",
		promptGuidelines: [
			"Use elevated_exec only when the requested operation genuinely requires root; never use it for inspection or commands that can run as the normal user.",
			"If elevated_exec reports that root access is locked, ask the user to run /elevate; the agent cannot unlock the lease.",
			`For this machine, nixos-rebuild must target --flake ${NIXCFG_FLAKE}.`,
			"Do not attempt sudo, su, doas, pkexec, or run0 through the bash tool; elevated_exec is the only agent-controlled elevation path.",
		],
		parameters: Type.Object({
			program: StringEnum(PROGRAM_NAMES, {
				description: "Allowlisted administration program",
			}),
			args: Type.Array(Type.String({ maxLength: 4096 }), {
				description: "Argument vector; no shell parsing is performed",
				maxItems: 64,
			}),
			reason: Type.String({
				description: "Short explanation shown to the user before approval",
				minLength: 1,
				maxLength: 240,
			}),
		}),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			if (ctx.mode !== "tui") {
				throw new Error("Elevation is available only in an interactive TUI");
			}
			if (typeof process.geteuid === "function" && process.geteuid() === 0) {
				throw new Error("Refusing elevation because Pi is already running as root");
			}
			if (!leaseIsActive() || !hasSudoCredential()) {
				lock();
				throw new Error("Root access is locked. Ask the user to run /elevate, then retry the operation.");
			}
			if (elevationInProgress) {
				throw new Error("Another elevation request is already active");
			}

			elevationInProgress = true;
			try {
				validateText(params.reason, "reason");
				validateArguments(params.program, params.args);
				const executable = await validateExecutable(params.program);
				const displayCommand = formatCommand(PROGRAMS[params.program], params.args);
				if (displayCommand.length > 4096) {
					throw new Error("The displayed command is too long for safe review");
				}

				const approved = await ctx.ui.confirm(
					"Root execution requested",
					`${params.reason}\n\n${displayCommand}\n\nThe command runs without a shell. Its output stays in your terminal and is not sent to the model. Continue?`,
				);
				if (!approved) {
					return {
						content: [{ type: "text", text: "The user declined the root operation." }],
						details: { approved: false, program: params.program, args: params.args },
					};
				}

				const result = await ctx.ui.custom<RunResult>((tui, _theme, _keybindings, done) => {
					tui.stop();
					process.stdout.write("\x1b[2J\x1b[H");
					process.stdout.write(`Pi root execution\n\n${displayCommand}\n\n`);

					let commandResult: RunResult;
					try {
						const command = spawnSync(
							SUDO,
							["-n", "--", PROGRAMS[params.program], ...params.args],
							{
								cwd: ctx.cwd,
								env: sudoEnvironment(),
								stdio: "inherit",
							},
						);
						commandResult = {
							status: command.status,
							signal: command.signal,
							error: command.error?.message,
						};
					} catch (error) {
						commandResult = {
							status: null,
							signal: null,
							error: error instanceof Error ? error.message : String(error),
						};
					} finally {
						process.stdout.write("\nReturning to Pi...\n");
						tui.start();
						tui.requestRender(true);
					}

					done(commandResult);
					return { render: () => [], invalidate: () => {} };
				});

				if (!hasSudoCredential()) {
					lock();
					throw new Error("The sudo credential expired; root access is locked. Run /elevate to unlock it again.");
				}
				armLease();
				if (result.error) throw new Error(`Could not start elevated command: ${result.error}`);
				if (result.status !== 0) {
					throw new Error(
						result.signal
							? `Elevated command ended from signal ${result.signal}; output remained local`
							: `Elevated command exited with status ${result.status ?? "unknown"}; output remained local`,
					);
				}

				return {
					content: [{
						type: "text",
						text: "The approved root operation completed successfully. Its output was displayed only to the user.",
					}],
					details: {
						approved: true,
						program: params.program,
						args: params.args,
						executable,
						exitCode: result.status,
						leaseExpiresAt,
					},
				};
			} finally {
				elevationInProgress = false;
			}
		},
	});
}
