import { homedir, userInfo } from "node:os";
import type { Usage } from "@earendil-works/pi-ai";
import {
	CustomEditor,
	VERSION,
	type ExtensionAPI,
	type ExtensionContext,
	type KeybindingsManager,
} from "@earendil-works/pi-coding-agent";
import {
	stripTerminalSequences,
	truncateToWidth,
	visibleWidth,
	type EditorTheme,
	type TUI,
} from "@earendil-works/pi-tui";

const MIN_ROUNDED_EDITOR_WIDTH = 12;

type ModeStyle = (text: string, shellMode: boolean) => string;

interface UsageTotals {
	input: number;
	output: number;
	cacheRead: number;
	cacheWrite: number;
	cost: number;
}

function formatHomePath(path: string): string {
	const home = homedir();
	if (path === home) return "~";
	return path.startsWith(`${home}/`) ? `~/${path.slice(home.length + 1)}` : path;
}

function formatTokens(count: number): string {
	if (count < 1000) return count.toString();
	if (count < 10000) return `${(count / 1000).toFixed(1)}k`;
	if (count < 1000000) return `${Math.round(count / 1000)}k`;
	if (count < 10000000) return `${(count / 1000000).toFixed(1)}M`;
	return `${Math.round(count / 1000000)}M`;
}

function addUsage(totals: UsageTotals, usage: Usage): void {
	totals.input += usage.input;
	totals.output += usage.output;
	totals.cacheRead += usage.cacheRead;
	totals.cacheWrite += usage.cacheWrite;
	totals.cost += usage.cost.total;
}

function formatUsageStats(ctx: ExtensionContext): string {
	const totals: UsageTotals = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0 };
	let latestCacheHitRate: number | undefined;

	for (const entry of ctx.sessionManager.getEntries()) {
		if (entry.type === "message" && entry.message.role === "assistant") {
			addUsage(totals, entry.message.usage);
			const promptTokens = entry.message.usage.input
				+ entry.message.usage.cacheRead
				+ entry.message.usage.cacheWrite;
			latestCacheHitRate = promptTokens > 0
				? (entry.message.usage.cacheRead / promptTokens) * 100
				: undefined;
		} else if (entry.type === "message" && entry.message.role === "toolResult" && entry.message.usage) {
			addUsage(totals, entry.message.usage);
		} else if ((entry.type === "branch_summary" || entry.type === "compaction") && entry.usage) {
			addUsage(totals, entry.usage);
		}
	}

	const dim = (text: string) => ctx.ui.theme.fg("dim", text);
	const parts: string[] = [];
	if (totals.input) parts.push(dim(`↑${formatTokens(totals.input)}`));
	if (totals.output) parts.push(dim(`↓${formatTokens(totals.output)}`));
	if (totals.cacheRead) parts.push(dim(`R${formatTokens(totals.cacheRead)}`));
	if (totals.cacheWrite) parts.push(dim(`W${formatTokens(totals.cacheWrite)}`));
	if ((totals.cacheRead || totals.cacheWrite) && latestCacheHitRate !== undefined) {
		parts.push(dim(`CH${latestCacheHitRate.toFixed(1)}%`));
	}

	const model = ctx.model;
	const provider = model ? ctx.modelRegistry.getProvider(model.provider) : undefined;
	const usingSubscription = model
		? model.provider === "kimi-coding"
			|| (ctx.modelRegistry.isUsingOAuth(model) && provider?.auth.oauth?.isSubscription === true)
		: false;
	if (totals.cost || usingSubscription) {
		parts.push(dim(`$${totals.cost.toFixed(3)}${usingSubscription ? " (sub)" : ""}`));
	}

	const contextUsage = ctx.getContextUsage();
	const contextWindow = contextUsage?.contextWindow ?? model?.contextWindow ?? 0;
	const contextPercent = contextUsage?.percent;
	const contextText = contextPercent === null || contextPercent === undefined
		? `?/${formatTokens(contextWindow)} (auto)`
		: `${contextPercent.toFixed(1)}%/${formatTokens(contextWindow)} (auto)`;
	parts.push(
		contextPercent !== null && contextPercent !== undefined && contextPercent > 90
			? ctx.ui.theme.fg("error", contextText)
			: contextPercent !== null && contextPercent !== undefined && contextPercent > 70
				? ctx.ui.theme.fg("warning", contextText)
				: dim(contextText),
	);

	return parts.join(dim(" "));
}

function fitRoundedBorder(
	left: string,
	right: string,
	width: number,
	top: boolean,
	border: (text: string) => string,
): string {
	if (width <= 0) return "";
	if (width === 1) return border("─");

	let leftText = left;
	let rightText = right;
	const minimumGap = 1;

	while (
		2 + visibleWidth(leftText) + visibleWidth(rightText) + minimumGap > width &&
		visibleWidth(rightText) > 0
	) {
		rightText = truncateToWidth(rightText, Math.max(0, visibleWidth(rightText) - 1), "");
	}
	while (
		2 + visibleWidth(leftText) + visibleWidth(rightText) + minimumGap > width &&
		visibleWidth(leftText) > 0
	) {
		leftText = truncateToWidth(leftText, Math.max(0, visibleWidth(leftText) - 1), "");
	}

	const gapWidth = Math.max(0, width - 2 - visibleWidth(leftText) - visibleWidth(rightText));
	const leftCorner = top ? "╭" : "╰";
	const rightCorner = top ? "╮" : "╯";
	return `${border(leftCorner)}${leftText}${border("─".repeat(gapWidth))}${rightText}${border(rightCorner)}`;
}

function isEditorBorder(line: string, width: number): boolean {
	const plain = stripTerminalSequences(line);
	return visibleWidth(plain) === width && (/^─+$/.test(plain) || /^─── [↑↓] /.test(plain));
}

function scrollLabel(line: string): string | undefined {
	const match = stripTerminalSequences(line).match(/[↑↓] \d+ more/);
	return match ? ` ${match[0]} ─` : undefined;
}

class RoundedEditor extends CustomEditor {
	constructor(
		tui: TUI,
		theme: EditorTheme,
		keybindings: KeybindingsManager,
		private readonly username: string,
		private readonly getThinkingLevel: () => string,
		private readonly getModelName: () => string,
		private readonly getUsageStats: () => string,
		private readonly rootLeaseIsActive: () => boolean,
		private readonly styleBorder: ModeStyle,
		private readonly styleTitle: (text: string, root: boolean) => string,
		private readonly styleStatus: ModeStyle,
		private readonly styleDanger: (text: string) => string,
	) {
		super(tui, theme, keybindings);
	}

	render(width: number): string[] {
		if (width < MIN_ROUNDED_EDITOR_WIDTH) return super.render(width);

		// The stock editor owns text layout, cursor placement, scrolling and
		// autocomplete. Render it slightly narrower, then replace its horizontal
		// rules with one padded box so none of that behavior has to be duplicated.
		const contentWidth = width - 4;
		const lines = super.render(contentWidth);
		let bottomBorder = -1;
		for (let index = lines.length - 1; index > 0; index--) {
			if (isEditorBorder(lines[index]!, contentWidth)) {
				bottomBorder = index;
				break;
			}
		}
		if (bottomBorder < 0) return super.render(width);

		const shellMode = this.getText().startsWith("!");
		const rootLease = this.rootLeaseIsActive();
		const border = (text: string) =>
			rootLease ? this.styleDanger(text) : this.styleBorder(text, shellMode);
		const title = rootLease
			? this.styleDanger("─ ⚠ Executing as (root) ")
			: this.styleTitle(`─ Executing as (${this.username}) `, this.username === "root");
		const topStatus = scrollLabel(lines[0]!) ?? "";
		const modelStatus = this.styleStatus(
			`─ ${this.getModelName()} · ${shellMode ? "shell" : this.getThinkingLevel()} `,
			shellMode,
		);
		const scrollStatus = scrollLabel(lines[bottomBorder]!);
		const usageStats = this.getUsageStats();
		const bottomStatus = scrollStatus
			? this.styleStatus(scrollStatus, shellMode)
			: usageStats
				? `${this.styleStatus(" ", shellMode)}${usageStats}${this.styleStatus(" ─", shellMode)}`
				: "";
		const wrap = (line: string): string => {
			const fitted = truncateToWidth(line, contentWidth, "");
			const padding = " ".repeat(Math.max(0, contentWidth - visibleWidth(fitted)));
			return `${border("│")} ${fitted}${padding} ${border("│")}`;
		};

		const result = [
			fitRoundedBorder(title, this.styleStatus(topStatus, shellMode), width, true, border),
			...lines.slice(1, bottomBorder).map(wrap),
		];

		const completions = lines.slice(bottomBorder + 1);
		if (completions.length > 0) {
			result.push(border(`├${"─".repeat(width - 2)}┤`));
			result.push(...completions.map(wrap));
		}

		result.push(fitRoundedBorder(modelStatus, bottomStatus, width, false, border));
		return result;
	}
}

export default function (pi: ExtensionAPI) {
	let rootLeaseActive = false;
	let activeTui: TUI | undefined;

	pi.events.on("elevation:state", (state) => {
		rootLeaseActive = typeof state === "object" && state !== null
			&& "active" in state && state.active === true;
		activeTui?.requestRender();
	});
	pi.on("session_shutdown", () => {
		activeTui = undefined;
	});

	pi.on("session_start", (_event, ctx) => {
		if (ctx.mode !== "tui") return;

		ctx.ui.setHeader((_tui, theme) => ({
			render(width: number): string[] {
				// Color the P and i independently while preserving the reference mark.
				const p = (text: string) => theme.fg("accent", text);
				const i = (text: string) => theme.fg("syntaxKeyword", text);
				const logo = [
					p("██████"),
					p("██  ██"),
					`${p("████")}  ${i("██")}`,
					`${p("██")}    ${i("██")}`,
				];

				const brand = `${theme.bold(theme.fg("text", "Pi"))} ${theme.bold(theme.fg("accent", "Code"))}`;
				const version = theme.fg("dim", `v${VERSION}`);
				const tagline = theme.fg("muted", "Coding Harness");
				const model = theme.fg("syntaxFunction", ctx.model?.id ?? "no model");

				const cwd = formatHomePath(ctx.cwd);
				const toolCount = pi.getActiveTools().length;
				const context = `${theme.fg("muted", `${toolCount} ${toolCount === 1 ? "tool" : "tools"}`)} ${theme.fg("dim", "·")} ${theme.fg("dim", cwd)}`;

				const lines = width >= 32
					? [
						`${logo[0]}     ${brand}  ${version}`,
						`${logo[1]}     ${tagline}`,
						`${logo[2]}   ${model}`,
						`${logo[3]}   ${context}`,
					]
					: [...logo, `${brand}  ${version}`, tagline, model, context];

				return ["", ...lines.map((line) => truncateToWidth(line, width, "")), ""];
			},
			invalidate() {},
		}));

		ctx.ui.setFooter((tui, theme, footerData) => {
			const dispose = footerData.onBranchChange(() => tui.requestRender());
			return {
				dispose,
				invalidate() {},
				render(width: number): string[] {
					let location = formatHomePath(ctx.cwd);
					const branch = footerData.getGitBranch();
					if (branch) location += ` (${branch})`;
					const sessionName = ctx.sessionManager.getSessionName();
					if (sessionName) location += ` · ${sessionName}`;
					return [truncateToWidth(theme.fg("dim", location), width, theme.fg("dim", "..."))];
				},
			};
		});

		ctx.ui.setEditorComponent((tui, theme, keybindings) => {
			activeTui = tui;
			return new RoundedEditor(
				tui,
				theme,
				keybindings,
				userInfo().username,
				() => pi.getThinkingLevel(),
				() => ctx.model?.id ?? "no model",
				() => formatUsageStats(ctx),
				() => rootLeaseActive,
				(text, shellMode) =>
					shellMode ? ctx.ui.theme.fg("bashMode", text) : ctx.ui.theme.fg("accent", text),
				(text, root) =>
					ctx.ui.theme.bold(
						root ? ctx.ui.theme.fg("error", text) : ctx.ui.theme.fg("accent", text),
					),
				(text, shellMode) =>
					shellMode ? ctx.ui.theme.fg("bashMode", text) : ctx.ui.theme.fg("muted", text),
				(text) => ctx.ui.theme.bold(ctx.ui.theme.fg("error", text)),
			);
		});
	});
}
