const label = "Claude Mythos 5.5";
// The status line drops a leading "Claude " from model names; a no-break space keeps the full label.
const shown = label.replace(" ", "\u00A0");
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
      for (const ctx of sessions.values()) if (ctx.model === this) return shown;
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
    description: "Toggle the cosmetic Claude Mythos 5.5 model label",
    handler: async (_args, ctx) => {
      if (!ctx.hasUI) return;
      const id = ctx.sessionManager.getSessionId();
      const enabled = !sessions.delete(id);
      if (enabled) {
        sessions.set(id, ctx);
        for (const model of ctx.models.list()) patch(model);
        patch(ctx.model);
      }
      // An empty status invalidates the cached bar without adding visible text.
      ctx.ui.setStatus("larp", enabled ? "" : undefined);
      ctx.ui.notify(enabled ? `${label} label enabled; actual model unchanged.` : "Actual model label restored.", "info");
    },
  });
  pi.on("session_shutdown", (_event, ctx) => {
    sessions.delete(ctx.sessionManager.getSessionId());
    ctx.ui.setStatus("larp", undefined);
  });
}
