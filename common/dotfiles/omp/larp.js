const labels = ["Mythos 5.5", "Selkie 1.6", "Ivrie 1.6"];
const restore = "Actual model";
// session id -> { ctx, label }
const sessions = new Map();
const patched = new WeakSet();

// ponytail: OMP has no label hook, so a getter swaps the display name of each larping session's model.
// Requests use model ids; replace this with a label hook when OMP gains one.
function patch(model) {
  if (!model || patched.has(model)) return;
  const property = Object.getOwnPropertyDescriptor(model, "name");
  if (property && !property.configurable) return;
  let real = model.name;
  Object.defineProperty(model, "name", {
    configurable: true,
    enumerable: property?.enumerable ?? true,
    get() {
      for (const { ctx, label } of sessions.values()) if (ctx.model === this) return label;
      return real;
    },
    set(value) {
      real = value;
    },
  });
  patched.add(model);
}

export default function (pi) {
  pi.registerCommand("larp", {
    description: "Pick a cosmetic model label",
    handler: async (_args, ctx) => {
      if (!ctx.hasUI) return;
      const id = ctx.sessionManager.getSessionId();
      const label = await ctx.ui.select("Model label", sessions.has(id) ? [...labels, restore] : labels);
      if (!label) return;
      if (label === restore) {
        sessions.delete(id);
      } else {
        sessions.set(id, { ctx, label });
        for (const model of ctx.models.list()) patch(model);
        patch(ctx.model);
      }
      // An empty status invalidates the cached bar without adding visible text.
      ctx.ui.setStatus("larp", sessions.has(id) ? "" : undefined);
      ctx.ui.notify(label === restore ? "Actual model label restored." : `${label} label enabled; actual model unchanged.`, "info");
    },
  });
  pi.on("session_shutdown", (_event, ctx) => {
    sessions.delete(ctx.sessionManager.getSessionId());
    ctx.ui.setStatus("larp", undefined);
  });
}
