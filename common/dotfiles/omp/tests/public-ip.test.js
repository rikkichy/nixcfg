import { expect, test } from "bun:test";
import register from "../public-ip.js";

function captureHook() {
  let inspect;
  register({ on(event, handler) { if (event === "tool_call") inspect = handler; } });
  return (command) => inspect({ toolName: "bash", input: { command } });
}

test("deny literal curl lookups before execution, not lookalike hosts or unrelated commands", () => {
  const check = captureHook();
  for (const command of ["curl ifconfig.me", "true && /usr/bin/curl -fsS 'https://API.IPIFY.ORG.:443/?format=json'", "curl --url=https://ns1.google.com"]) {
    const decision = check(command);
    expect(decision?.block).toBe(true);
    expect(decision.reason).toContain("You're strictly forbidden to discover, retrieve, infer, or disclose this machine's public IP address.");
  }
  for (const command of ["curl https://ifconfig.me.example.org", "curl https://example.org/ifconfig.me", "echo 'curl ifconfig.me'", "curl example.org && echo ifconfig.me", "wget ifconfig.me"]) {
    expect(check(command)).toBeUndefined();
  }
});

test("block VPN mutations without restricting read-only inspection", () => {
  const check = captureHook();
  for (const command of [
    "vpn off",
    "vpn use Estonia",
    'true && "/run/current-system/sw/bin/vpn" select "node name"',
    "command vpn subscription primary",
    "sudo -- vpn subscription quattro",
    "vpn subscription; v\\pn select node",
  ]) {
    const decision = check(command);
    expect(decision?.block).toBe(true);
    expect(decision.reason).toContain("You're strictly forbidden to change VPN state at runtime.");
    expect(decision.reason).toContain("ask the operator");
  }
  expect(check("vpn ip")?.reason).toContain("public IP address");
  for (const command of [
    "vpn", "vpn status", "vpn list", "vpn nodes", "vpn subscription",
    "vpn subscriptions", "echo 'vpn off'", "vpn-status",
  ]) {
    expect(check(command)).toBeUndefined();
  }
});
