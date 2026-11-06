import { SEGMENTS } from "@oh-my-pi/pi-tui/status-line/segments";

const label = "Claude Mythos 5.5";
const sessions = new Set();
let original;

function setLarp(id, enabled) {
  if (enabled) sessions.add(id);
  else sessions.delete(id);

  // ponytail: OMP has no label hook; replace this adapter when it gains one.
  if (sessions.size && !original) {
    original = SEGMENTS.model;
    const base = original;
    SEGMENTS.model = {
      ...base,
      render(ctx) {
        const result = base.render(ctx);
        if (!sessions.has(ctx.session.sessionManager.getSessionId())) return result;
        const model = ctx.session.state.model;
        const name = (model?.name || model?.id || "no-model").replace(/^Claude /, "");
        return { ...result, content: result.content.replace(name, label) };
      },
      describe(ctx) {
        const view = base.describe(ctx);
        if (!view || !sessions.has(ctx.session.sessionManager.getSessionId())) return view;
        return { ...view, spans: view.spans.map((span, i) => i === 0 ? { ...span, t: label } : span) };
      },
    };
  } else if (!sessions.size && original) {
    SEGMENTS.model = original;
    original = undefined;
  }
}

export default function (pi) {
  pi.registerCommand("larp", {
    description: "Toggle the cosmetic Claude Mythos 5.5 model label",
    handler: async (_args, ctx) => {
      if (!ctx.hasUI) return;
      const id = ctx.sessionManager.getSessionId();
      const enabled = !sessions.has(id);
      setLarp(id, enabled);
      // An empty status invalidates the cached bar without adding visible text.
      ctx.ui.setStatus("larp", enabled ? "" : undefined);
      ctx.ui.notify(enabled ? `${label} label enabled; actual model unchanged.` : "Actual model label restored.", "info");
    },
  });
  pi.on("session_shutdown", (_event, ctx) => {
    setLarp(ctx.sessionManager.getSessionId(), false);
    ctx.ui.setStatus("larp", undefined);
  });
}
