const blockedHosts = new Set(`
ifconfig.me ifconfig.co ifconfig.io ifconfig.pro icanhazip.com ipinfo.io ipinfo.app
ipify.org api.ipify.org api64.ipify.org ipv4.icanhazip.com ipv6.icanhazip.com
checkip.amazonaws.com checkip.dyndns.org ipecho.net ident.me v4.ident.me v6.ident.me
ip.sb api.ip.sb ip.seeip.org seeip.org myexternalip.com wgetip.com ip4.me ip6.me
whatismyip.akamai.com whatismyipaddress.com whatismyip.com ip-api.com ipapi.co
ipapi.is ipwho.is ipgeolocation.io ipdata.co ipregistry.co iplocation.net ipchicken.com
curlmyip.net curlmyip.org curlmyip.com eth0.me eth0.me.uk ip.tyk.nu ipv4.wtfismyip.com
wtfismyip.com ipv4bot.whatismyipaddress.com diagnostic.opendns.com resolver1.opendns.com ns1.google.com
`.trim().split(/\s+/));

const ipReason = "You're strictly forbidden to discover, retrieve, infer, or disclose this machine's public IP address. Do not use curl, wget, DNS queries, external APIs, websites, or any other method to determine it, directly or indirectly.";
const vpnReason = "You're strictly forbidden to change VPN state at runtime. Use `vpn status` or `vpn list` for read-only inspection. If a change is needed, ask the operator to make it. Do not bypass this restriction with another tool.";
const vpnReadOnly = new Set(["", "status", "list", "nodes", "subscription", "subscriptions"]);

export default function (pi) {
  pi.on("tool_call", ({ toolName, input }) => {
    if (toolName !== "bash" || !input.command) return;

    // Inspect literal shell words, without executing or expanding the command.
    let executable, vpnAction;
    for (const [raw] of input.command.matchAll(/(?:[^\s;&|()'"\\]+|'[^']*'|"(?:\\.|[^"\\])*"|\\[\s\S])+|[;&|()\n]/g)) {
      if (/^[;&|()\n]$/.test(raw)) {
        executable = undefined;
        vpnAction = undefined;
        continue;
      }
      const word = raw.replace(/\\\n/g, "").replace(/\\(.)|['"]/gs, (_, escaped) => escaped ?? "");
      if (!executable) {
        if (!word || /^(?:command|exec|env|sudo|--)$|^[a-zA-Z_]\w*=/.test(word)) continue;
        executable = word.split("/").pop();
      } else if (executable === "vpn") {
        if (vpnAction === undefined) {
          vpnAction = word;
          if (word === "ip") return { block: true, reason: ipReason };
          if (!vpnReadOnly.has(word)) return { block: true, reason: vpnReason };
        } else if (vpnAction === "subscription" && word) {
          return { block: true, reason: vpnReason };
        }
      } else if (executable === "curl") {
        const target = word.replace(/^--url=/, "");
        if (!target || /^[-/]/.test(target)) continue;
        const url = URL.parse(/^[a-z][a-z\d+.-]*:\/\//i.test(target) ? target : `http://${target}`);
        if (url && blockedHosts.has(url.hostname.toLowerCase().replace(/\.$/, ""))) return { block: true, reason: ipReason };
      }
    }
  });
}
