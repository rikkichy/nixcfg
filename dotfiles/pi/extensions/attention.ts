import { basename } from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const MINIMUM_TASK_MS = 5_000;

export default function (pi: ExtensionAPI) {
	let startedAt = 0;

	function projectName(ctx: ExtensionContext): string {
		return basename(ctx.cwd) || ctx.cwd;
	}

	function idleTitle(ctx: ExtensionContext): string {
		const session = pi.getSessionName();
		return session
			? `Pi Code — ${session} · ${projectName(ctx)}`
			: `Pi Code — ${projectName(ctx)}`;
	}

	function setIdleTitle(ctx: ExtensionContext): void {
		if (ctx.mode === "tui") ctx.ui.setTitle(idleTitle(ctx));
	}

	pi.on("session_start", (_event, ctx) => setIdleTitle(ctx));
	pi.on("session_info_changed", (_event, ctx) => setIdleTitle(ctx));

	pi.on("agent_start", (_event, ctx) => {
		startedAt = Date.now();
		if (ctx.mode === "tui") {
			ctx.ui.setTitle(`● ${idleTitle(ctx)}`);
		}
	});

	pi.on("agent_settled", async (_event, ctx) => {
		setIdleTitle(ctx);
		if (ctx.mode !== "tui" || Date.now() - startedAt < MINIMUM_TASK_MS) return;
		if (!process.env.HYPRLAND_INSTANCE_SIGNATURE || !process.env.DBUS_SESSION_BUS_ADDRESS) return;

		// The extension owns the Foot title. If a Pi terminal is focused, the
		// completion is already visible and a desktop notification is noise.
		const active = await pi.exec("hyprctl", ["activewindow", "-j"], { timeout: 2_000 });
		if (active.code === 0) {
			try {
				const title = (JSON.parse(active.stdout) as { title?: string }).title ?? "";
				if (title.includes("Pi Code")) return;
			} catch {
				// A malformed compositor reply should not suppress the notification.
			}
		}

		await pi.exec(
			"notify-send",
			[
				"-a", "Pi Code",
				"-i", "utilities-terminal",
				"-t", "5000",
				"Pi Code",
				`${projectName(ctx)} is ready for input`,
			],
			{ timeout: 2_000 },
		);
	});
}
