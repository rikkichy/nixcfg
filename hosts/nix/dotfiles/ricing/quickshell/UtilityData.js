function entry(name, icon, action, value) {
    return { name: name, nameKey: name.toLocaleLowerCase(), keywords: "", icon: icon, action: action, value: value };
}

function vpnRows(text, subscriptions) {
    return text.split("\n").filter(line => line !== "").map(line => {
        const tab = line.indexOf("\t");
        if (tab < 1 || tab === line.length - 1)
            throw new Error("Invalid VPN row");
        const key = line.slice(0, tab);
        const name = line.slice(tab + 1);
        if (!subscriptions && !/^\d+$/.test(key))
            throw new Error("Invalid VPN latency");
        return entry(subscriptions ? name : name + " · " + (Number(key) === 0 ? "--" : key + " ms"),
                     subscriptions ? "network-vpn" : "network-server",
                     subscriptions ? "subscription" : "select", subscriptions ? key : name);
    });
}

function emojis(text) {
    const result = [];
    for (const line of text.split("\n")) {
        const match = line.match(/;\s*fully-qualified\s*#\s*(\S+)\s+E[\d.]+\s+(.+)$/);
        if (!match)
            continue;
        const item = entry(match[2], "", "emoji", match[1]);
        item.glyph = match[1];
        item.keywords = match[1] + " " + match[2].toLocaleLowerCase();
        result.push(item);
    }
    if (!result.length)
        throw new Error("No fully-qualified emoji in the Unicode data");
    return result;
}

function succeeded(code, status, output, requireOk) {
    return code === 0 && status === 0 && (!requireOk || output.trim() === "ok");
}

function current(opened, generation, requestGeneration, revision, requestRevision) {
    return opened && generation === requestGeneration && revision === requestRevision;
}
