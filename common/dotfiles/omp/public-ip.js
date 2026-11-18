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

const reason = "You're strictly forbidden to discover, retrieve, infer, or disclose this machine's public IP address. Do not use curl, wget, DNS queries, external APIs, websites, or any other method to determine it, directly or indirectly.";

export default function (pi) {
  pi.on("tool_call", ({ toolName, input }) => {
    if (toolName !== "bash" || !input.command?.includes("curl")) return;

    // Inspect literal shell words, without executing or expanding the command.
    let executable;
    for (const [raw] of input.command.matchAll(/(?:[^\s;&|()'"\\]+|'[^']*'|"(?:\\.|[^"\\])*"|\\[\s\S])+|[;&|()\n]/g)) {
      if (/^[;&|()\n]$/.test(raw)) {
        executable = undefined;
        continue;
      }
      const word = raw.replace(/\\\n/g, "").replace(/['"]/g, "");
      if (!executable) {
        if (!word || /^(?:command|exec|env)$|^[a-zA-Z_]\w*=/.test(word)) continue;
        executable = word.split("/").pop();
      } else if (executable === "curl") {
        const target = word.replace(/^--url=/, "");
        if (!target || /^[-/]/.test(target)) continue;
        const url = URL.parse(/^[a-z][a-z\d+.-]*:\/\//i.test(target) ? target : `http://${target}`);
        if (url && blockedHosts.has(url.hostname.toLowerCase().replace(/\.$/, ""))) return { block: true, reason };
      }
    }
  });
}
