pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "UtilityData.js" as UtilityData

Item {
    id: utility
    required property var host
    property var entries: []
    property string page: ""
    property string status: ""
    property int revision: 0
    property bool busy: false
    property var emojiEntries: []
    property string vpnMode: ""
    property string subscription: ""
    property string server: ""
    readonly property string title: host.mode === "night-light" ? "Blue-light filter"
        : host.mode === "power" ? "Power" : host.mode === "emoji" ? "Emoji"
        : page === "subscriptions" ? "VPN subscriptions" : page === "nodes" ? "VPN servers" : "VPN"
    signal resetSearch()

    function report(message) {
        host.errorMessage = host.errorMessage ? host.errorMessage + "\n" + message : message;
        console.warn(message);
    }

    function request(argv, done, requireOk, actionRequest) {
        const worker = utilityCommand.createObject(utility, {
            requestGeneration: host.generation,
            requestRevision: revision,
            callback: done,
            requireOk: !!requireOk,
            actionRequest: !!actionRequest
        });
        worker.exec(argv);
    }

    function vpnEntries() {
        entries = [
            UtilityData.entry("Switch subscription", "network-vpn", "page", "subscriptions"),
            UtilityData.entry("Choose server", "network-server", "page", "nodes"),
            UtilityData.entry(vpnMode ? "Switch to " + (vpnMode === "global" ? "scoped" : "global") : "Mode unavailable", "network-vpn", "mode", vpnMode === "global" ? "scoped" : "global"),
            UtilityData.entry("Edit config", "document-edit", "edit", "")
        ];
    }

    function open(nextPage) {
        revision++;
        page = nextPage || "";
        busy = false;
        entries = [];
        status = "";
        host.errorMessage = "";
        resetSearch();
        if (host.mode === "night-light") {
            entries = [
                UtilityData.entry("Follow the schedule", "preferences-system-time", "sun", ["reset"]),
                UtilityData.entry("Off", "weather-clear", "sun", ["identity", "true"]),
                UtilityData.entry("Warm · 4000 K", "redshift", "sun", ["temperature", "4000"]),
                UtilityData.entry("Warmer · 3400 K", "redshift", "sun", ["temperature", "3400"]),
                UtilityData.entry("Warmest · 2700 K", "redshift", "sun", ["temperature", "2700"])
            ];
            status = "Current temperature: loading…";
            request(["hyprctl", "hyprsunset", "temperature"], output => {
                if (!/^\d+$/.test(output.trim())) {
                    status = "Current temperature: unavailable";
                    report("Could not read the current temperature: " + (output.trim() || "no response"));
                } else {
                    status = "Current temperature: " + output.trim() + " K";
                }
            });
        } else if (host.mode === "power") {
            entries = [UtilityData.entry("Shutdown", "system-shutdown", "power", "poweroff"),
                       UtilityData.entry("Reboot", "system-reboot", "power", "reboot")];
        } else if (host.mode === "emoji") {
            if (emojiEntries.length) {
                entries = emojiEntries;
            } else {
                status = "Loading emoji…";
                if (!Quickshell.env("QS_EMOJI_DATA")) {
                    report("QS_EMOJI_DATA is not configured.");
                    status = "";
                } else if (!emojiData.path) {
                    emojiData.path = Quickshell.env("QS_EMOJI_DATA");
                } else {
                    emojiData.reload();
                }
            }
        } else if (host.mode === "vpn") {
            vpnMode = "";
            subscription = "";
            server = "";
            status = "Loading VPN status…";
            if (!page)
                vpnEntries();
            request(["vpn", "mode"], output => {
                vpnMode = output.trim();
                if (!["global", "scoped"].includes(vpnMode)) {
                    vpnMode = "";
                    report("VPN returned an unknown mode.");
                }
                updateVpnStatus();
                if (!page)
                    vpnEntries();
            });
            request(["vpn", "subscription"], output => { subscription = output.trim(); updateVpnStatus(); });
            request(["vpn", "status"], output => { server = output.trim(); updateVpnStatus(); });
            if (page) {
                request(["vpn", page === "subscriptions" ? "subscriptions" : "nodes"], output => {
                    entries = UtilityData.vpnRows(output, page === "subscriptions");
                });
            }
        }
    }

    function updateVpnStatus() {
        status = "Mode: " + (vpnMode || "unavailable") + " · Subscription: " + (subscription || "unavailable")
            + " · Server: " + (server || "unavailable");
    }

    function activate(entry) {
        if (busy)
            return;
        host.errorMessage = "";
        if (entry.action === "page") {
            open(entry.value);
            return;
        }
        if (entry.action === "mode" && !vpnMode) {
            report("VPN mode is unavailable. Reopen VPN to retry.");
            return;
        }
        busy = true;
        if (entry.action === "sun") {
            request(["hyprctl", "hyprsunset"].concat(entry.value), () => open(""), true, true);
        } else if (entry.action === "power") {
            request(["systemctl", entry.value], () => host.close(), false, true);
        } else if (["subscription", "select", "mode"].includes(entry.action)) {
            request(["vpn", entry.action, entry.value], () => open(""), false, true);
        } else if (entry.action === "edit") {
            const path = Quickshell.env("QS_VPN_CONFIG");
            if (!path || !path.startsWith("/")) {
                busy = false;
                report("QS_VPN_CONFIG is not configured with an absolute path.");
                return;
            }
            request(["zeditor", path], () => host.close(), false, true);
        } else if (entry.action === "emoji") {
            request(["wl-copy", "--", entry.value], () => host.close(), false, true);
        }
    }

    FileView {
        id: emojiData
        preload: true
        printErrors: false
        onLoaded: {
            try {
                utility.emojiEntries = UtilityData.emojis(text());
                if (utility.host.opened && utility.host.mode === "emoji") {
                    utility.entries = utility.emojiEntries;
                    utility.status = "";
                }
            } catch (error) {
                if (utility.host.opened && utility.host.mode === "emoji") {
                    utility.status = "";
                    utility.report(String(error));
                }
            }
        }
        onLoadFailed: error => {
            if (utility.host.opened && utility.host.mode === "emoji") {
                utility.status = "";
                utility.report("Could not load emoji data: " + error);
            }
        }
    }

    Component {
        id: utilityCommand
        Process {
            id: worker
            property int requestGeneration: -1
            property int requestRevision: -1
            property var callback
            property bool requireOk: false
            property bool actionRequest: false
            property bool finished: false
            stdout: StdioCollector { id: output }
            stderr: StdioCollector { id: errors }
            function finish(code, status) {
                if (finished)
                    return;
                finished = true;
                failedStart.stop();
                if (UtilityData.current(utility.host.opened, utility.host.generation, requestGeneration, utility.revision, requestRevision)) {
                    if (UtilityData.succeeded(code, status, output.text, requireOk)) {
                        try {
                            callback(output.text);
                        } catch (error) {
                            if (actionRequest)
                                utility.busy = false;
                            utility.report(String(error));
                        }
                    } else {
                        if (actionRequest)
                            utility.busy = false;
                        utility.status = "";
                        utility.report(command.join(" ") + ": " + (errors.text.trim() || output.text.trim() || "command failed"));
                    }
                }
                destroy();
            }
            onExited: (code, status) => finish(code, status)
            // Failed-to-start processes become stopped without emitting exited.
            onRunningChanged: if (!running && !finished) failedStart.start()
            property Timer failureTimer: Timer {
                id: failedStart
                interval: 0
                onTriggered: worker.finish(-1, -1)
            }
        }
    }
}
