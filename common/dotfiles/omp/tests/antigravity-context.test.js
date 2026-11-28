import { expect, test } from "bun:test";
import register from "../antigravity-context.js";

function createHarness(branch = []) {
  const handlers = new Map();
  register({
    on(event, handler) {
      handlers.set(event, handler);
    },
    appendEntry(customType, data) {
      branch.push({ type: "custom", customType, data });
    },
  });
  const ctx = {
    model: { provider: "antigravity-cli" },
    sessionManager: { getBranch: () => branch },
  };
  return {
    branch,
    beforeStart(systemPrompt, overrideCtx = ctx) {
      return handlers.get("before_agent_start")({ systemPrompt }, overrideCtx);
    },
    context(messages, overrideCtx = ctx) {
      return handlers.get("context")({ messages }, overrideCtx);
    },
  };
}

test("preserves first user message bytes across /restart when systemPrompt changes", () => {
  const branch = [];
  const beforeRestart = createHarness(branch);

  expect(beforeRestart.beforeStart(["prompt v1"])).toEqual({ systemPrompt: [] });
  const turn1 = beforeRestart.context([{ role: "user", content: "first" }]).messages;
  expect(turn1[0].content[0].text).toContain("prompt v1");

  const turn1Assistant = { role: "assistant", content: [{ type: "text", text: "ok" }] };

  // Simulate /restart: fresh extension instance reading the persisted branch,
  // with a changed systemPrompt (e.g., new extension/rule loaded).
  const afterRestart = createHarness(branch);
  expect(afterRestart.beforeStart(["prompt v2"])).toEqual({ systemPrompt: [] });
  const turn2 = afterRestart.context([
    { role: "user", content: "first" },
    turn1Assistant,
    { role: "user", content: "second" },
  ]).messages;

  // Prefix up through turn1Assistant is byte-identical so antigravity-cli restores its checkpoint.
  expect(turn2.slice(0, 2)).toEqual([...turn1, turn1Assistant]);
  // New instructions ride on the new trailing user message.
  expect(turn2[2].content[0].text).toContain("prompt v2");
  expect(turn2[2].content[1]).toEqual({ type: "text", text: "second" });

  // Subsequent tool-loop call in turn 2 keeps both prefixes stable without duplicate entries.
  const entriesBefore = branch.length;
  const turn2Loop = afterRestart.context([
    { role: "user", content: "first" },
    turn1Assistant,
    { role: "user", content: "second" },
    { role: "assistant", content: [{ type: "text", text: "working" }] },
  ]).messages;
  expect(turn2Loop.slice(0, 3)).toEqual(turn2);
  expect(branch.length).toBe(entriesBefore);
});

test("resets pinned instruction turns after compaction", () => {
  const branch = [];
  const h = createHarness(branch);

  h.beforeStart(["prompt v1"]);
  h.context([{ role: "user", content: "old" }]);

  branch.push({ type: "compaction" });
  h.beforeStart(["prompt v2"]);
  const postCompact = h.context([{ role: "user", content: "summary" }]).messages;

  expect(postCompact[0].content[0].text).toContain("prompt v2");
});

test("ignores non-antigravity providers", () => {
  const h = createHarness();
  const otherCtx = { model: { provider: "anthropic" }, sessionManager: { getBranch: () => [] } };
  expect(h.beforeStart(["prompt v1"], otherCtx)).toBeUndefined();
  expect(h.context([{ role: "user", content: "hi" }], otherCtx)).toBeUndefined();
});
