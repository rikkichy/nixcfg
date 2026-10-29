// Run with: node hosts/nix/dotfiles/ricing/quickshell/launcher-previews.test.cjs
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const qml = fs.readFileSync(path.join(__dirname, "Launcher.qml"), "utf8");
const functions = ["previewKey", "fileUrl", "loadPreviews"].map(name => {
    const match = qml.match(new RegExp("^    function " + name + "\\([^]*?^    }", "m"));
    assert.ok(match, name);
    return match[0];
}).join("\n");
const exitBody = qml.split("id: previewWorkers")[1]
    .split("onExited: (exitCode, exitStatus) => {")[1].split("\n            }")[0];

function gallery(mode = "wallpapers") {
    const jobs = [];
    const workers = Array.from({ length: 4 }, () => ({
        key: "", path: "", running: false,
        exec(argv) { this.running = true; jobs.push(Array.from(argv)); }
    }));
    const host = {
        mode, opened: true, wallpaperMode: true, generation: 1,
        wallpaperHelper: mode === "wallpapers" ? "wpp" : "awpp",
        directory: "/wall papers", previewStates: new Map(), previewCache: new Map(),
        grid: { height: 500, previewStart: 0, visibleEnd: 6, previewEnd: 9 },
        previewWorkers: { count: workers.length, objectAt: index => workers[index] },
        previewStatesChanged() {}
    };
    vm.runInNewContext(functions, host);
    host.results = Array.from({ length: 15 }, (_, index) => {
        const path = "/wall papers/" + index + " #\n.jpg";
        return { path, revision: "revision", preview: "", previewKey: host.previewKey(path, "revision") };
    });
    function finish(worker, exitCode = 0, preview = "file:///cached.jpg") {
        worker.running = false;
        worker.preview = preview;
        Object.assign(worker, {
            launcher: host, exitCode, exitStatus: 0, previewErrors: { text: "" },
            Qt: { callLater() {} }, console: { warn() {} }
        });
        vm.runInNewContext(exitBody, worker);
        host.loadPreviews();
    }
    return { host, workers, jobs, finish };
}

for (const mode of ["wallpapers", "animated-wallpapers"]) {
    const { host, workers, jobs, finish } = gallery(mode);
    host.loadPreviews();
    assert.deepEqual(jobs.map(job => job[2]), host.results.slice(0, 4).map(entry => entry.path));
    finish(workers[0]);
    finish(workers[1]);
    assert.equal(jobs.length, 6);
    finish(workers[2]);
    finish(workers[3]);
    finish(workers[0]);
    assert.equal(jobs.length, 6, "prefetch waits for the final visible thumbnail");
    finish(workers[1]);
    assert.deepEqual(jobs.slice(6).map(job => job[2]), host.results.slice(6, 9).map(entry => entry.path));
}

{
    const { host, workers, jobs, finish } = gallery();
    host.loadPreviews();
    host.grid.previewStart = 9;
    host.grid.visibleEnd = 12;
    host.grid.previewEnd = 15;
    host.loadPreviews();
    assert.equal(jobs.length, 4, "at most four in flight");
    const completedKey = workers[0].key;
    finish(workers[0]);
    assert.equal(jobs[4][2], host.results[9].path, "scrolling selects current rows, not an old queue");
    assert.equal(host.previewCache.get(completedKey), "file:///cached.jpg", "completed scroll work remains reusable");
    host.generation++;
    host.previewStates = new Map();
    const staleKey = workers[1].key;
    finish(workers[1], 1, "");
    assert.equal(host.previewStates.get(staleKey), undefined, "stale failures cannot poison the new view");
    assert.equal(host.previewCache.has(staleKey), false);
    host.opened = false;
    const before = jobs.length;
    finish(workers[2]);
    assert.equal(jobs.length, before, "closed galleries do not schedule previews");
}

{
    const { host, jobs } = gallery();
    for (const entry of host.results.slice(0, 6)) entry.preview = "file:///cached.jpg";
    host.loadPreviews();
    assert.deepEqual(jobs.map(job => job[2]), host.results.slice(6, 9).map(entry => entry.path));
    const key = host.previewKey("/name\n#?[]", "revision");
    assert.notEqual(key, host.previewKey("/name\n#?[]", "new revision"));
    assert.notEqual(host.previewKey("/a,b", "c"), host.previewKey("/a", "b,c"));
    host.mode = "animated-wallpapers";
    assert.notEqual(key, host.previewKey("/name\n#?[]", "revision"));
    assert.equal(host.fileUrl("/name #?\n.jpg", "a?b"), "file:///name%20%23%3F%0A.jpg?revision=a%3Fb");
}

console.log("Wallpaper preview scheduling, cache identity and stale completion checks passed.");
