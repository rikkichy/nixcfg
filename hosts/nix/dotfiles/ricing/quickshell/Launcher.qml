pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import QtQml.Models
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: launcher

    property bool opened: false
    property string mode: "apps"
    property string directory: ""
    property int generation: 0
    readonly property bool wallpaperMode: mode === "wallpapers" || mode === "animated-wallpapers"
    readonly property bool utilityMode: ["night-light", "vpn", "power", "emoji"].includes(mode)
    readonly property string wallpaperHelper: mode === "animated-wallpapers" ? "awpp" : "wpp"
    property var wallpapers: []
    property bool wallpaperLoading: false
    property var visibleIds: ({ apps: new Set(), tools: new Set() })
    property bool visibilityDirty: true
    property var previewStates: new Map()
    property var previewCache: new Map()
    property string errorMessage: ""
    readonly property var applications: DesktopEntries.applications.values
        .filter(entry => entry && !entry.noDisplay && visibleIds[mode]?.has(entry.id + ".desktop"))
        .reduce((apps, entry) => {
            const app = {
                id: entry.id,
                action: "",
                name: entry.name,
                icon: entry.icon,
                nameKey: entry.name.toLocaleLowerCase(),
                keywords: [entry.id, entry.genericName, entry.execString, ...entry.keywords].join(" ").toLocaleLowerCase()
            };
            apps.push(app, ...(mode === "tools" ? [...entry.actions].filter(action => action).map(action => ({
                id: app.id,
                keywords: app.keywords,
                action: action.id,
                name: entry.name + " · " + action.name,
                nameKey: (entry.name + " " + action.name).toLocaleLowerCase(),
                icon: action.icon || entry.icon
            })) : []));
            return apps;
        }, [])
        .sort((a, b) => a.name.localeCompare(b.name))
    readonly property string query: search.text.trim().toLocaleLowerCase()
    readonly property var entries: wallpaperMode ? wallpapers : utilityMode ? utilities.entries : applications
    readonly property var results: {
        if (!query)
            return entries;
        return entries.map(app => ({ app, score: score(app.nameKey, query) || (app.keywords.includes(query) ? 1 : 0) }))
            .filter(result => result.score > 0)
            .sort((a, b) => b.score - a.score || a.app.name.localeCompare(b.app.name))
            .map(result => result.app);
    }

    // Prefixes and contiguous matches precede subsequences; metadata is a fallback.
    function score(name, query) {
        const start = name.indexOf(query);
        if (start >= 0)
            return start === 0 ? 1000 : 500 / (start + 1);
        let at = 0;
        for (const character of query) {
            at = name.indexOf(character, at);
            if (at < 0)
                return 0;
            at++;
        }
        return 2;
    }

    function open(targetScreen, targetMode, targetDirectory) {
        generation++;
        previewStates = new Map();
        screen = targetScreen;
        mode = targetMode;
        directory = targetDirectory || "";
        wallpapers = [];
        wallpaperLoading = wallpaperMode;
        search.text = "";
        errorMessage = "";
        grid.currentIndex = results.length ? 0 : -1;
        grid.positionViewAtBeginning();
        opened = true;
        if (wallpaperMode) {
            refresh.stop();
            loadWallpapers();
        } else if (utilityMode) {
            refresh.stop();
            utilities.open("");
        } else {
            loadApplications();
        }
        search.forceActiveFocus(Qt.ShortcutFocusReason);
    }

    function loadWallpapers() {
        if (!opened || !wallpaperMode || wallpaperListProcess.running)
            return;
        wallpaperListProcess.generation = generation;
        wallpaperListProcess.exec([wallpaperHelper, "--list", directory]);
    }

    function fileUrl(path, revision) {
        return "file://" + path.split("/").map(part => encodeURIComponent(part)).join("/")
            + "?revision=" + encodeURIComponent(revision);
    }

    function loadApplications() {
        if (!opened || wallpaperMode || utilityMode || !visibilityDirty || visibilityProcess.running)
            return;
        visibilityDirty = false;
        visibilityProcess.accepted = false;
        visibilityProcess.running = true;
    }

    function invalidateApplications() {
        visibilityDirty = true;
        if (opened && !wallpaperMode && !utilityMode)
            refresh.restart();
    }

    function loadPreviews() {
        if (!opened || mode !== "animated-wallpapers" || grid.height <= 0)
            return;
        // Recompute candidates from the viewport; scrolling never queues offscreen work.
        for (let index = grid.previewStart; index < grid.previewEnd; index++) {
            const entry = results[index];
            if (entry.preview || previewStates.has(entry.path))
                continue;
            const cached = previewCache.get(entry.path);
            if (cached && cached.revision === entry.revision) {
                previewStates.set(entry.path, cached.preview);
                previewStatesChanged();
                continue;
            }
            let worker = null;
            for (let slot = 0; slot < previewWorkers.count; slot++) {
                const candidate = previewWorkers.objectAt(slot);
                if (candidate && !candidate.path && !candidate.running) {
                    worker = candidate;
                    break;
                }
            }
            if (!worker)
                break;
            previewStates.set(entry.path, "");
            worker.path = entry.path;
            worker.revision = entry.revision;
            worker.generation = generation;
            worker.preview = "";
            worker.exec(["awpp", "--preview", entry.path, directory]);
        }
    }

    function close() {
        if (opened)
            generation++;
        opened = false;
    }

    function launch(index) {
        const app = results[index];
        if (!opened || !app || (wallpaperMode && wallpaperLoading))
            return;
        if (utilityMode) {
            utilities.activate(app);
            return;
        }
        const utilityTool = !app.action && ({ sunp: "night-light", vpnp: "vpn", bemoji: "emoji", reboot: "power", shutdown: "power" })[app.id];
        if (mode === "tools" && utilityTool) {
            open(screen, utilityTool);
            return;
        }
        if (launchProcess.running)
            return;
        errorMessage = "";
        launchProcess.generation = generation;
        const wallpaperTool = !wallpaperMode && !app.action && (app.id === "wpp" || app.id === "awpp");
        launchProcess.closeOnSuccess = !wallpaperTool;
        if (wallpaperMode)
            launchProcess.exec([wallpaperHelper, "--apply", app.path, directory]);
        else if (wallpaperTool)
            launchProcess.exec([app.id]);
        else
            launchProcess.exec(["expressive-apps", mode, app.id + ".desktop", ...(app.action ? [app.action] : [])]);
    }

    onQueryChanged: {
        grid.currentIndex = results.length ? 0 : -1;
        grid.positionViewAtBeginning();
    }
    onResultsChanged: {
        grid.currentIndex = results.length ? Math.max(0, Math.min(grid.currentIndex, results.length - 1)) : -1;
        Qt.callLater(loadPreviews);
    }
    onBackingWindowVisibleChanged: if (backingWindowVisible)
        search.forceActiveFocus(Qt.ShortcutFocusReason)
    onScreenChanged: if (!screen)
        close()

    UtilityPicker {
        id: utilities
        host: launcher
        onResetSearch: {
            search.text = "";
            grid.currentIndex = 0;
            grid.positionViewAtBeginning();
            search.forceActiveFocus(Qt.ShortcutFocusReason);
        }
    }

    Timer {
        id: refresh
        interval: 100
        onTriggered: launcher.loadApplications()
    }
    Connections {
        target: DesktopEntries
        function onApplicationsChanged() { launcher.invalidateApplications(); }
    }
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { launcher.invalidateApplications(); }
    }
    Process {
        id: visibilityProcess
        property bool accepted: false
        command: ["expressive-apps"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const ids = JSON.parse(text);
                    if (!ids || !["apps", "tools"].every(mode => Array.isArray(ids[mode]) && ids[mode].every(id => typeof id === "string")))
                        throw new Error("Invalid desktop-entry lists");
                    launcher.visibleIds = { apps: new Set(ids.apps), tools: new Set(ids.tools) };
                    visibilityProcess.accepted = true;
                } catch (error) {
                    launcher.visibilityDirty = true;
                    if (launcher.opened && !launcher.wallpaperMode && !launcher.utilityMode)
                        launcher.errorMessage = "Could not read installed applications.";
                    console.warn(error);
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 || exitStatus !== 0) {
                launcher.visibilityDirty = true;
                if (launcher.opened && !launcher.wallpaperMode && !launcher.utilityMode)
                    launcher.errorMessage = "Could not read installed applications.";
            } else if (launcher.visibilityDirty && accepted) {
                refresh.restart();
            }
        }
    }
    Process {
        id: wallpaperListProcess
        property int generation: -1
        stdout: StdioCollector {
            onStreamFinished: {
                if (!launcher.opened || wallpaperListProcess.generation !== launcher.generation || !launcher.wallpaperMode)
                    return;
                try {
                    const entries = JSON.parse(text);
                    if (!Array.isArray(entries) || !entries.every(entry => entry
                            && typeof entry.name === "string"
                            && typeof entry.path === "string" && entry.path.startsWith("/")
                            && typeof entry.preview === "string"
                            && (entry.preview.startsWith("/") || (launcher.mode === "animated-wallpapers" && entry.preview === ""))
                            && typeof entry.revision === "string"))
                        throw new Error("Invalid wallpaper list");
                    launcher.wallpapers = entries.map(entry => ({
                        name: entry.name,
                        nameKey: entry.name.toLocaleLowerCase(),
                        keywords: "",
                        path: entry.path,
                        revision: entry.revision,
                        preview: entry.preview ? launcher.fileUrl(entry.preview, entry.revision) : ""
                    }));
                } catch (error) {
                    launcher.errorMessage = "Could not read wallpapers.";
                    console.warn(error);
                }
            }
        }
        stderr: StdioCollector { id: wallpaperListErrors }
        onExited: (exitCode, exitStatus) => {
            if (!launcher.opened || generation !== launcher.generation) {
                Qt.callLater(() => launcher.loadWallpapers());
                return;
            }
            launcher.wallpaperLoading = false;
            if (exitCode !== 0 || exitStatus !== 0)
                launcher.errorMessage = wallpaperListErrors.text.trim() || "Could not read wallpapers.";
        }
    }
    Instantiator {
        id: previewWorkers
        model: 4
        delegate: Process {
            id: previewWorker
            property string path: ""
            property string revision: ""
            property int generation: -1
            property string preview: ""
            stdout: StdioCollector {
                onStreamFinished: {
                    if (!launcher.opened || previewWorker.generation !== launcher.generation)
                        return;
                    try {
                        const result = JSON.parse(text);
                        if (!result || typeof result.preview !== "string" || !result.preview.startsWith("/"))
                            throw new Error("Invalid wallpaper preview");
                        previewWorker.preview = launcher.fileUrl(result.preview, previewWorker.revision);
                    } catch (error) {
                        console.warn(error);
                    }
                }
            }
            stderr: StdioCollector { id: previewErrors }
            onExited: (exitCode, exitStatus) => {
                if (launcher.opened && generation === launcher.generation) {
                    const success = exitCode === 0 && exitStatus === 0 && preview;
                    launcher.previewStates.set(path, success ? preview : null);
                    if (success) {
                        launcher.previewCache.delete(path);
                        launcher.previewCache.set(path, { revision, preview });
                        // Retain only small URL metadata; decoded images use Qt's bounded cache.
                        if (launcher.previewCache.size > 128)
                            launcher.previewCache.delete(launcher.previewCache.keys().next().value);
                    } else {
                        launcher.previewCache.delete(path);
                        console.warn(previewErrors.text.trim() || "Wallpaper preview unavailable: " + path);
                    }
                    launcher.previewStatesChanged();
                }
                path = "";
                Qt.callLater(launcher.loadPreviews);
            }
        }
    }
    Process {
        id: launchProcess
        property int generation: -1
        property bool closeOnSuccess: true
        stderr: StdioCollector { id: launchErrors }
        onExited: (exitCode, exitStatus) => {
            if (!launcher.opened || generation !== launcher.generation)
                return;
            if (exitCode === 0 && exitStatus === 0) {
                if (closeOnSuccess)
                    launcher.close();
            } else {
                launcher.errorMessage = launchErrors.text.trim() || (launcher.wallpaperMode ? "The wallpaper could not be applied." : "The application could not be started.");
            }
        }
    }

    visible: opened
    implicitWidth: Math.max(1, Math.min(wallpaperMode ? 1120 : 820, (screen ? screen.width : 1920) - 112))
    implicitHeight: Math.max(1, Math.min(wallpaperMode ? 780 : 620, (screen ? screen.height : 1080) - 48))
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: Theme.reducedMotion ? "expressive-panel-static" : "expressive-panel"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    HyprlandFocusGrab {
        active: launcher.opened && launcher.backingWindowVisible
        windows: [launcher]
        onCleared: launcher.close()
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusExtraLarge
        color: Theme.surfaceContainer
        border.width: 1
        border.color: Theme.outlineVariant
        clip: true
        Keys.onEscapePressed: launcher.close()

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                ExpressiveButton {
                    visible: launcher.wallpaperMode || launcher.utilityMode
                    text: "Settings"
                    description: "Back to Settings"
                    onClicked: launcher.open(launcher.screen, "tools")
                }
                ExpressiveButton {
                    visible: launcher.mode === "vpn" && utilities.page !== ""
                    text: "VPN"
                    description: "Back to VPN"
                    onClicked: utilities.open("")
                }
                Text {
                    Layout.fillWidth: true
                    text: launcher.utilityMode ? utilities.title : launcher.wallpaperMode ? (launcher.mode === "animated-wallpapers" ? "Animated wallpapers" : "Wallpapers") : launcher.mode === "tools" ? "Settings" : "Applications"
                    color: Theme.textOnSurface
                    font.family: Theme.fontFamily
                    font.styleName: "Bold Rounded"
                    font.pixelSize: 32
                    elide: Text.ElideRight
                }
                ExpressiveButton {
                    implicitWidth: 48
                    description: "Close launcher"
                    onClicked: launcher.close()
                    contentItem: Item {
                        BoxIcon {
                            anchors.centerIn: parent
                            name: "boxicons-x-filled"
                            tint: Theme.textOnSurface
                        }
                    }
                }
            }

            // Material search: 56px pill, surface-container-high and body text.
            TextField {
                id: search
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                leftPadding: 24
                rightPadding: clearSearch.visible ? 64 : 24
                placeholderText: launcher.utilityMode ? (launcher.mode === "emoji" ? "Search emoji to copy" : "Search " + utilities.title.toLocaleLowerCase()) : launcher.wallpaperMode ? "Search wallpapers" : launcher.mode === "tools" ? "Search desktop tools" : "Execute.."
                placeholderTextColor: Theme.textOnSurfaceVariant
                color: Theme.textOnSurface
                selectionColor: Theme.primary
                selectedTextColor: Theme.textOnPrimary
                font.family: Theme.fontFamily
                font.pixelSize: 18
                selectByMouse: true
                Accessible.name: placeholderText
                background: Rectangle {
                    radius: height / 2
                    color: Theme.surfaceContainerHigh
                    border.width: search.activeFocus && [Qt.TabFocusReason, Qt.BacktabFocusReason, Qt.ShortcutFocusReason].includes(search.focusReason) ? 2 : 0
                    border.color: Theme.primary
                }
                onTextEdited: forceActiveFocus(Qt.OtherFocusReason)
                onAccepted: launcher.launch(grid.currentIndex)
                Keys.onDownPressed: {
                    if (grid.count)
                        grid.forceActiveFocus(Qt.TabFocusReason);
                }
                ExpressiveButton {
                    id: clearSearch
                    visible: search.text.length > 0
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    width: 48
                    height: 48
                    description: "Clear search"
                    onClicked: {
                        search.clear();
                        search.forceActiveFocus(Qt.TabFocusReason);
                    }
                    contentItem: Item {
                        BoxIcon {
                            anchors.centerIn: parent
                            name: "boxicons-x-filled"
                            tint: Theme.textOnSurfaceVariant
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: launcher.errorMessage || (launcher.utilityMode ? (utilities.busy ? "Working…" : utilities.status || launcher.results.length + " entries") : launcher.wallpaperMode && launchProcess.running ? "Applying wallpaper…" : launcher.wallpaperLoading ? "Loading wallpapers…" : (launcher.query ? "Search results" : launcher.wallpaperMode ? "All wallpapers" : launcher.mode === "tools" ? "All tools" : "All apps") + " · " + launcher.results.length)
                color: launcher.errorMessage ? Theme.error : Theme.textOnSurfaceVariant
                font.family: Theme.fontFamily
                font.pixelSize: 14
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                Accessible.role: Accessible.StaticText
            }

            GridView {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                readonly property int columns: Math.max(1, Math.floor(width / (launcher.wallpaperMode ? 300 : launcher.utilityMode && launcher.mode !== "emoji" ? 220 : 116)))
                cellWidth: width / columns
                cellHeight: launcher.wallpaperMode ? (cellWidth - 32) * 9 / 16 + 64 : 116
                readonly property int previewStart: Math.max(0, Math.floor((contentY - originY) / cellHeight)) * columns
                readonly property int previewEnd: Math.min(count, (Math.ceil((contentY - originY + height) / cellHeight) + 1) * columns)
                onPreviewStartChanged: Qt.callLater(launcher.loadPreviews)
                onPreviewEndChanged: Qt.callLater(launcher.loadPreviews)
                model: launcher.results
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                keyNavigationEnabled: true
                activeFocusOnTab: true
                highlightMoveDuration: 0
                ScrollBar.vertical: ScrollBar { }
                Keys.priority: Keys.AfterItem
                Keys.forwardTo: [search]
                Keys.onReturnPressed: launcher.launch(currentIndex)
                Keys.onEnterPressed: launcher.launch(currentIndex)
                Keys.onEscapePressed: launcher.close()

                delegate: ExpressiveButton {
                    id: tile
                    required property var modelData
                    required property int index
                    readonly property var previewState: launcher.previewStates.get(modelData.path)
                    width: grid.cellWidth - 8
                    height: grid.cellHeight - 8
                    checked: GridView.isCurrentItem
                    activeFocusOnTab: false
                    enabled: launcher.utilityMode ? !utilities.busy : !launcher.wallpaperMode || !launchProcess.running
                    description: (launcher.mode === "emoji" ? "Copy emoji " : launcher.wallpaperMode ? "Apply wallpaper " : "Open ") + modelData.name
                        + (launcher.wallpaperMode && (previewState === null || wallpaperPreview.status === Image.Error) ? ". Preview unavailable" : "")
                    onClicked: {
                        grid.currentIndex = index;
                        launcher.launch(index);
                    }
                    background: Rectangle {
                        radius: tile.down ? Theme.radiusSmall : tile.checked ? Theme.radiusLarge : Theme.radiusMedium
                        color: tile.checked ? Theme.secondaryContainer : tile.hovered ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                        border.width: tile.visualFocus || (grid.activeFocus && tile.checked) ? 2 : 0
                        border.color: Theme.primary
                        Behavior on radius { enabled: !Theme.reducedMotion; SpringAnimation { spring: 4; damping: 0.8; epsilon: 0.05 } }
                        Behavior on color { ColorAnimation { duration: Theme.motionDuration } }
                    }
                    contentItem: Column {
                        spacing: 8
                        topPadding: launcher.wallpaperMode ? 4 : 12
                        Item {
                            width: parent.width
                            height: launcher.wallpaperMode ? width * 9 / 16 : 48
                            ClippingRectangle {
                                anchors.fill: parent
                                visible: launcher.wallpaperMode
                                radius: Theme.radiusSmall
                                color: Theme.surfaceContainerHighest
                                Image {
                                    id: wallpaperPreview
                                    anchors.fill: parent
                                    Binding {
                                        target: wallpaperPreview
                                        property: "source"
                                        value: launcher.wallpaperMode && tile.index >= grid.previewStart && tile.index < grid.previewEnd
                                            ? tile.modelData.preview || tile.previewState || "" : ""
                                        when: launcher.opened
                                        // Keep the presented image for the compositor's closing snapshot.
                                        restoreMode: Binding.RestoreNone
                                    }
                                    sourceSize: Qt.size(640, 360)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    autoTransform: true
                                    onStatusChanged: {
                                        if (status === Image.Error && launcher.opened && launcher.mode === "animated-wallpapers") {
                                            launcher.previewCache.delete(tile.modelData.path);
                                            launcher.previewStates.set(tile.modelData.path, null);
                                            launcher.previewStatesChanged();
                                        }
                                    }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: wallpaperPreview.status !== Image.Ready
                                    text: tile.previewState === null || wallpaperPreview.status === Image.Error ? "Preview unavailable" : "Loading preview…"
                                    color: Theme.textOnSurfaceVariant
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 14
                                }
                            }
                            ClippingRectangle {
                                anchors.centerIn: parent
                                width: 48
                                height: 48
                                radius: width / 2
                                color: "transparent"
                                visible: !launcher.wallpaperMode && appIcon.status === Image.Ready
                                Image {
                                    id: appIcon
                                    anchors.centerIn: parent
                                    width: 48
                                    height: 48
                                    source: !launcher.wallpaperMode && tile.modelData.icon ? Quickshell.iconPath(tile.modelData.icon, true) : ""
                                    sourceSize: Qt.size(48, 48)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    layer.enabled: visible && status === Image.Ready
                                    layer.effect: MultiEffect {
                                        colorization: 1
                                        colorizationColor: tile.checked ? Theme.textOnSecondaryContainer : Theme.primary
                                    }
                                }
                            }
                            BoxIcon {
                                anchors.centerIn: parent
                                width: 40
                                height: 40
                                visible: !launcher.wallpaperMode && !tile.modelData.glyph && appIcon.status !== Image.Ready
                                name: "boxicons-layers-filled"
                                tint: tile.checked ? Theme.textOnSecondaryContainer : Theme.primary
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !!tile.modelData.glyph
                                text: tile.modelData.glyph || ""
                                font.pixelSize: 36
                            }
                        }
                        Text {
                            width: parent.width
                            text: tile.modelData.name
                            color: tile.checked ? Theme.textOnSecondaryContainer : Theme.textOnSurface
                            font.family: Theme.fontFamily
                            font.styleName: tile.checked ? "Bold Rounded" : "Rounded"
                            font.pixelSize: launcher.wallpaperMode ? 15 : 13
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: launcher.utilityMode ? Text.Wrap : Text.NoWrap
                            maximumLineCount: launcher.utilityMode ? 2 : 1
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                        }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: grid.count === 0
                    text: launcher.utilityMode ? (launcher.errorMessage ? "Entries unavailable" : utilities.status.startsWith("Loading") ? utilities.status : launcher.query ? "No matching entries" : "No entries available") : launcher.wallpaperMode ? (launcher.wallpaperLoading ? "Loading wallpapers…" : launcher.errorMessage ? "Wallpapers could not be loaded" : launcher.query ? "No matching wallpapers" : "No wallpapers in this directory") : visibilityProcess.running ? "Loading…" : launcher.query ? "No matching entries" : "No entries available"
                    color: Theme.textOnSurfaceVariant
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }
            }
        }
    }
}
