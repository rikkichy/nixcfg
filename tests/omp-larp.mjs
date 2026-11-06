// Run with NODE_PATH pointing at OMP's node_modules: bun tests/omp-larp.mjs
import assert from "node:assert/strict";
import { stripVTControlCharacters } from "node:util";
import { SEGMENTS } from "@oh-my-pi/pi-tui/status-line/segments";
import { initThemeSync } from "@oh-my-pi/pi-tui/theme/theme";
import larp from "../common/dotfiles/omp/larp.js";

initThemeSync();
const original = SEGMENTS.model;
const commands = new Map();
const events = new Map();
larp({ registerCommand: (name, command) => commands.set(name, command), on: (name, handler) => events.set(name, handler) });
const model = Object.freeze({ id: "gpt-test", name: "GPT Test", provider: "openai", thinking: false });
const session = {
  state: { model },
  sessionManager: { getSessionId: () => "main" },
  isFastModeActive: () => false,
};
const segmentContext = { session, options: {}, sessionAccent: false };
const context = {
  hasUI: true,
  sessionManager: session.sessionManager,
  ui: { setStatus() {}, notify() {} },
};
const toggle = () => commands.get("larp").handler("", context);
const text = () => stripVTControlCharacters(SEGMENTS.model.render(segmentContext).content);
const nativeName = () => SEGMENTS.model.describe(segmentContext).spans[0].t;
const before = text();

await toggle();
assert.ok(text().includes("Claude Mythos 5.5"));
assert.equal(nativeName(), "Claude Mythos 5.5");
assert.equal(session.state.model, model);
assert.equal(model.name, "GPT Test");
const other = { ...segmentContext, session: { ...session, sessionManager: { getSessionId: () => "other" } } };
assert.equal(stripVTControlCharacters(SEGMENTS.model.render(other).content), before);
assert.equal(SEGMENTS.model.describe(other).spans[0].t, "GPT Test");

session.state.model = Object.freeze({ ...model, name: "Claude Sonnet Test" });
assert.ok(text().includes("Claude Mythos 5.5"));
assert.equal(nativeName(), "Claude Mythos 5.5");
await toggle();
assert.ok(text().includes("Sonnet Test"));
assert.equal(SEGMENTS.model, original);

await toggle();
const otherContext = { ...context, sessionManager: other.session.sessionManager };
await commands.get("larp").handler("", otherContext);
events.get("session_shutdown")({}, context);
assert.equal(nativeName(), "Sonnet Test");
assert.equal(SEGMENTS.model.describe(other).spans[0].t, "Claude Mythos 5.5");
events.get("session_shutdown")({}, otherContext);
assert.equal(SEGMENTS.model, original);
console.log("PASS: display-only toggle, model changes, session isolation, and shutdown restoration");
