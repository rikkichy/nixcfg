import { homedir } from "node:os";
import { VERSION, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { truncateToWidth } from "@earendil-works/pi-tui";

export default function (pi: ExtensionAPI) {
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

				const home = homedir();
				const cwd = ctx.cwd === home
					? "~"
					: ctx.cwd.startsWith(`${home}/`)
						? `~/${ctx.cwd.slice(home.length + 1)}`
						: ctx.cwd;
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
	});
}
