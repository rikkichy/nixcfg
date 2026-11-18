import { expect, test } from "bun:test";
import register from "../public-ip.js";

test("deny literal curl lookups before execution, not lookalike hosts or unrelated commands", () => {
  let inspect;
  register({ on(event, handler) { if (event === "tool_call") inspect = handler; } });
  const check = (command) => inspect({ toolName: "bash", input: { command } });
  for (const command of ["curl ifconfig.me", "true && /usr/bin/curl -fsS 'https://API.IPIFY.ORG.:443/?format=json'", "curl --url=https://ns1.google.com"]) {
    const decision = check(command);
    expect(decision?.block).toBe(true);
    expect(decision.reason).toContain("You're strictly forbidden to discover, retrieve, infer, or disclose this machine's public IP address.");
  }
  for (const command of ["curl https://ifconfig.me.example.org", "curl https://example.org/ifconfig.me", "echo 'curl ifconfig.me'", "curl example.org && echo ifconfig.me", "wget ifconfig.me"]) {
    expect(check(command)).toBeUndefined();
  }
});
