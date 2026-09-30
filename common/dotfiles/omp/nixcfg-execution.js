import { existsSync } from "node:fs";

export function executionContext(
  env = process.env,
  hasContainerMarker = existsSync("/.dockerenv") || existsSync("/run/.containerenv"),
) {
  const ssh = Boolean(env.SSH_CONNECTION || env.SSH_CLIENT || env.SSH_TTY);
  const container = Boolean(env.container || hasContainerMarker);
  // ponytail: environment/marker detection; native runtime probes if unmarked containers matter.
  if (container) return ssh ? "container + SSH" : "container";
  return ssh ? "SSH" : "local (no SSH/container indicators detected)";
}

export default function (pi) {
  const context = `# Execution context

- Execution context: ${executionContext()}

This classification uses launch-time environment and container-file indicators,
not connection/authentication proof or a remote tool target. A configured desktop
does not establish an active GUI session.`;
  pi.on("before_agent_start", ({ systemPrompt }) => ({
    systemPrompt: [...systemPrompt, context],
  }));
}
