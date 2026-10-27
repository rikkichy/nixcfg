pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: launcher

    property bool opened: false
    property var visibleIds: new Set()
    property string errorMessage: ""
    readonly property var applications: DesktopEntries.applications.values
        .filter(entry => entry && !entry.noDisplay && visibleIds.has(entry.id + ".desktop"))
        .map(entry => ({
            id: entry.id,
            name: entry.name,
            icon: entry.icon,
            nameKey: entry.name.toLocaleLowerCase(),
            keywords: [entry.id, entry.genericName, entry.execString, ...entry.keywords].join(" ").toLocaleLowerCase()
        }))
        .sort((a, b) => a.name.localeCompare(b.name))
    readonly property string query: search.text.trim().toLocaleLowerCase()
    readonly property var results: {
        if (!query)
            return applications;
        return applications.map(app => ({ app, score: score(app.nameKey, query) || (app.keywords.includes(query) ? 1 : 0) }))
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

    function open(targetScreen) {
        screen = targetScreen;
        search.text = "";
        errorMessage = "";
        grid.currentIndex = results.length ? 0 : -1;
        grid.positionViewAtBeginning();
        opened = true;
        refresh.restart();
        search.forceActiveFocus(Qt.ShortcutFocusReason);
    }

    function close() {
        opened = false;
    }

    function launch(index) {
        const app = results[index];
        if (!opened || launchProcess.running || !app)
            return;
        errorMessage = "";
        launchProcess.exec(["expressive-apps", app.id + ".desktop"]);
    }

    onQueryChanged: {
        grid.currentIndex = results.length ? 0 : -1;
        grid.positionViewAtBeginning();
    }
    onResultsChanged: grid.currentIndex = results.length ? Math.max(0, Math.min(grid.currentIndex, results.length - 1)) : -1
    onBackingWindowVisibleChanged: if (backingWindowVisible)
        search.forceActiveFocus(Qt.ShortcutFocusReason)
    onScreenChanged: if (!screen)
        close()

    Timer {
        id: refresh
        interval: 100
        onTriggered: visibilityProcess.running = true
    }
    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            if (launcher.opened)
                refresh.restart();
        }
    }
    Process {
        id: visibilityProcess
        command: ["expressive-apps"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const ids = JSON.parse(text);
                    if (!Array.isArray(ids) || !ids.every(id => typeof id === "string"))
                        throw new Error("Invalid desktop-entry list");
                    launcher.visibleIds = new Set(ids);
                } catch (error) {
                    launcher.errorMessage = "Could not read installed applications.";
                    console.warn(error);
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 || exitStatus !== 0)
                launcher.errorMessage = "Could not read installed applications.";
        }
    }
    Process {
        id: launchProcess
        stderr: StdioCollector { id: launchErrors }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && exitStatus === 0)
                launcher.close();
            else
                launcher.errorMessage = launchErrors.text.trim() || "The application could not be started.";
        }
    }

    visible: opened
    implicitWidth: Math.max(1, Math.min(820, (screen ? screen.width : 1920) - 112))
    implicitHeight: Math.max(1, Math.min(620, (screen ? screen.height : 1080) - 48))
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
                Text {
                    Layout.fillWidth: true
                    text: "Applications"
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
                placeholderText: "Search applications"
                placeholderTextColor: Theme.textOnSurfaceVariant
                color: Theme.textOnSurface
                selectionColor: Theme.primary
                selectedTextColor: Theme.textOnPrimary
                font.family: Theme.fontFamily
                font.pixelSize: 18
                selectByMouse: true
                Accessible.name: "Search applications"
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
                text: launcher.errorMessage || (launcher.query ? "Search results" : "All apps") + " · " + launcher.results.length
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
                readonly property int columns: Math.max(1, Math.floor(width / 116))
                cellWidth: width / columns
                cellHeight: 116
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
                    width: grid.cellWidth - 8
                    height: grid.cellHeight - 8
                    checked: GridView.isCurrentItem
                    activeFocusOnTab: false
                    description: "Open " + modelData.name
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
                        topPadding: 12
                        Item {
                            width: parent.width
                            height: 48
                            ClippingRectangle {
                                anchors.centerIn: parent
                                width: 48
                                height: 48
                                radius: width / 2
                                color: "transparent"
                                visible: appIcon.status === Image.Ready
                                Image {
                                    id: appIcon
                                    anchors.centerIn: parent
                                    width: 48
                                    height: 48
                                    source: tile.modelData.icon ? Quickshell.iconPath(tile.modelData.icon, true) : ""
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
                                visible: appIcon.status !== Image.Ready
                                name: "boxicons-layers-filled"
                                tint: tile.checked ? Theme.textOnSecondaryContainer : Theme.primary
                            }
                        }
                        Text {
                            width: parent.width
                            text: tile.modelData.name
                            color: tile.checked ? Theme.textOnSecondaryContainer : Theme.textOnSurface
                            font.family: Theme.fontFamily
                            font.styleName: tile.checked ? "Bold Rounded" : "Rounded"
                            font.pixelSize: 13
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                        }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: grid.count === 0
                    text: visibilityProcess.running ? "Loading applications…" : launcher.query ? "No matching applications" : "No applications available"
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
