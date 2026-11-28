// Google's Antigravity backend answers 429 RESOURCE_EXHAUSTED when third-party
// instructions are appended to agy's system prompt, but accepts the same text as
// user-turn context. Move omp's system prompt into the first user message.
const PROVIDER = "antigravity-cli";

export default function (pi) {
  let instructions = "";

  pi.on("before_agent_start", ({ systemPrompt }, ctx) => {
    if (ctx.model?.provider !== PROVIDER) return;
    instructions = systemPrompt.join("\n\n");
    return { systemPrompt: [] };
  });

  pi.on("context", ({ messages }, ctx) => {
    if (ctx.model?.provider !== PROVIDER || !instructions) return;
    const index = messages.findIndex((message) => message.role === "user");
    if (index < 0) return;
    const message = messages[index];
    const content =
      typeof message.content === "string" ? [{ type: "text", text: message.content }] : message.content;
    const next = [...messages];
    next[index] = {
      ...message,
      content: [
        { type: "text", text: `# Session instructions\n\n${instructions}\n\n---\n\n# User request\n\n` },
        ...content,
      ],
    };
    return { messages: next };
  });
}
