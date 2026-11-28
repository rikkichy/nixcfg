// Google's Antigravity backend answers 429 RESOURCE_EXHAUSTED when third-party
// instructions are appended to agy's system prompt, but accepts the same text as
// user-turn context. Pin each injected prompt snapshot in session state so
// earlier user messages stay byte-stable across /restart and antigravity-cli's
// transcriptDigest can restore its SQLite checkpoint instead of replaying history.
const PROVIDER = "antigravity-cli";
const ENTRY_TYPE = "antigravity-context";

function prependInstructions(message, instructions) {
  const content =
    typeof message.content === "string" ? [{ type: "text", text: message.content }] : message.content;
  return {
    ...message,
    content: [
      { type: "text", text: `# Session instructions\n\n${instructions}\n\n---\n\n# User request\n\n` },
      ...content,
    ],
  };
}

function loadPinned(ctx) {
  const branch = ctx.sessionManager?.getBranch?.() ?? [];
  let start = 0;
  for (let i = branch.length - 1; i >= 0; i--) {
    if (branch[i]?.type === "compaction" || branch[i]?.type === "reset_boundary") {
      start = i + 1;
      break;
    }
  }
  const pinned = new Map();
  let lastInstructions = "";
  for (let i = start; i < branch.length; i++) {
    const entry = branch[i];
    if (entry?.type !== "custom" || entry.customType !== ENTRY_TYPE) continue;
    const { userTurn, instructions } = entry.data ?? {};
    if (Number.isInteger(userTurn) && userTurn >= 0 && typeof instructions === "string") {
      pinned.set(userTurn, instructions);
      lastInstructions = instructions;
    }
  }
  return { pinned, lastInstructions };
}

export default function (pi) {
  let currentInstructions = "";

  pi.on("before_agent_start", ({ systemPrompt }, ctx) => {
    if (ctx.model?.provider !== PROVIDER) return;
    currentInstructions = systemPrompt.join("\n\n");
    return { systemPrompt: [] };
  });

  pi.on("context", ({ messages }, ctx) => {
    if (ctx.model?.provider !== PROVIDER || !currentInstructions) return;
    const userIndices = [];
    for (let i = 0; i < messages.length; i++) {
      if (messages[i]?.role === "user") userIndices.push(i);
    }
    if (userIndices.length === 0) return;

    const { pinned, lastInstructions } = loadPinned(ctx);
    if (pinned.size === 0) {
      pinned.set(0, currentInstructions);
      pi.appendEntry?.(ENTRY_TYPE, { userTurn: 0, instructions: currentInstructions });
    } else if (currentInstructions !== lastInstructions) {
      const targetTurn = userIndices.length - 1;
      const targetIndex = userIndices[targetTurn];
      const hasAssistantAfter = messages.slice(targetIndex + 1).some((m) => m?.role === "assistant");
      if (!pinned.has(targetTurn) && !hasAssistantAfter) {
        pinned.set(targetTurn, currentInstructions);
        pi.appendEntry?.(ENTRY_TYPE, { userTurn: targetTurn, instructions: currentInstructions });
      }
    }

    const next = [...messages];
    let changed = false;
    for (const [userTurn, instructions] of pinned) {
      const msgIndex = userIndices[userTurn];
      if (msgIndex === undefined) continue;
      next[msgIndex] = prependInstructions(next[msgIndex], instructions);
      changed = true;
    }
    return changed ? { messages: next } : undefined;
  });
}
