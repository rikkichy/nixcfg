import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Notifications
import Quickshell.Services.Pipewire

Scope {
    id: root
    required property var shell
    property PanelWindow osdRail: null
    onOsdRailChanged: if (!osdRail)
        osdVisible = false

    property bool dnd: false
    readonly property var entries: items.filter(entry => !entry.notification.transient)
    readonly property int count: entries.length
    property var items: []

    function focusedScreen() {
        const monitor = Hyprland.focusedMonitor;
        return Quickshell.screens.find(screen => monitor && screen.name === monitor.name) || Quickshell.screens[0] || null;
    }

    function remove(entry, userDismissed) {
        if (!entry || entry.removing)
            return;
        entry.removing = true;
        entry.popup = false;
        items = items.filter(item => item !== entry);
        if (entry.active) {
            if (userDismissed)
                entry.notification.dismiss();
            else
                entry.notification.expire();
        }
        entry.destroy();
    }

    function dismiss(value) {
        const entry = items.find(item => item === value || item.notification === value);
        remove(entry, true);
    }

    function dismissAll() {
        for (const entry of items.slice())
            remove(entry, true);
    }

    onDndChanged: {
        if (dnd) {
            for (const entry of items)
                entry.popup = false;
        }
    }

    NotificationServer {
        id: server
        keepOnReload: false
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: false
        bodyHyperlinksSupported: false
        bodyImagesSupported: false
        actionsSupported: true
        actionIconsSupported: false
        imageSupported: true
        inlineReplySupported: false
        onNotification: notification => {
            notification.tracked = true;
            const entry = entryFactory.createObject(root, {
                notification: notification
            });
            root.items = [entry].concat(root.items);
            entry.refresh();
            while (root.items.length > 100)
                root.remove(root.items[root.items.length - 1], false);
        }
    }

    Component {
        id: entryFactory
        Scope {
            id: entry
            required property var notification
            property bool active: true
            property bool popup: false
            property bool removing: false
            property string screenName: ""
            property date receivedAt: new Date()

            function refresh() {
                if (removing || !active)
                    return;
                receivedAt = new Date();
                const screen = root.focusedScreen();
                screenName = screen ? screen.name : "";
                popup = !root.dnd;
                expiration.stop();
                const timeout = notification.expireTimeout;
                if (timeout !== 0 && notification.urgency !== NotificationUrgency.Critical) {
                    expiration.interval = timeout < 0 ? 7000 : Math.max(1, timeout);
                    expiration.start();
                }
            }

            RetainableLock {
                object: entry.notification
                locked: true
            }

            Timer {
                id: expiration
                onTriggered: {
                    if (entry.active)
                        entry.notification.expire();
                }
            }

            Connections {
                target: entry.notification
                function onSummaryChanged() {
                    Qt.callLater(entry.refresh);
                }
                function onBodyChanged() {
                    Qt.callLater(entry.refresh);
                }
                function onAppNameChanged() {
                    Qt.callLater(entry.refresh);
                }
                function onAppIconChanged() {
                    Qt.callLater(entry.refresh);
                }
                function onImageChanged() {
                    Qt.callLater(entry.refresh);
                }
                function onActionsChanged() {
                    Qt.callLater(entry.refresh);
                }
                function onHintsChanged() {
                    Qt.callLater(entry.refresh);
                }
                function onExpireTimeoutChanged() {
                    Qt.callLater(entry.refresh);
                }
                function onUrgencyChanged() {
                    Qt.callLater(entry.refresh);
                }
                function onResidentChanged() {
                    Qt.callLater(entry.refresh);
                }
                function onTransientChanged() {
                    Qt.callLater(entry.refresh);
                }
                function onClosed(reason) {
                    entry.active = false;
                    entry.popup = false;
                    expiration.stop();
                    if (reason !== NotificationCloseReason.Expired || entry.notification.transient)
                        root.remove(entry, false);
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: popupWindow
            required property var modelData
            readonly property var popups: root.items.filter(entry => entry.popup && entry.screenName === modelData.name)
            screen: modelData
            visible: popups.length > 0
            color: "transparent"
            anchors {
                top: true
                right: true
            }
            margins {
                top: 16
                right: 16
            }
            implicitWidth: Math.max(160, Math.min(412, modelData.width - 112))
            implicitHeight: Math.min(popupColumn.implicitHeight, modelData.height - 32)
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "expressive-notification"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            ScrollView {
                anchors.fill: parent
                clip: true
                contentWidth: availableWidth
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                Column {
                    id: popupColumn
                    width: popupWindow.width
                    spacing: 12
                    Repeater {
                        model: popupWindow.popups
                        delegate: NotificationPanel.Card {
                            required property var modelData
                            width: popupColumn.width
                            center: root
                            entry: modelData
                            compact: true
                        }
                    }
                }
            }
        }
    }

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: sink ? sink.audio : null
    property bool audioArmed: false
    property var osdScreen: null
    property bool osdVisible: false
    property rect osdAnchor: Qt.rect(12, 12, 56, 88)
    property real lastVolume: -1
    property bool lastMuted: false
    readonly property bool soundOpen: shell.panel === "sound"
    onSoundOpenChanged: {
        if (soundOpen) {
            osdVisible = false;
            osdTimeout.stop();
        }
    }

    function armAudio() {
        audioArmed = false;
        osdVisible = false;
        if (osdTimeout)
            osdTimeout.stop();
        if (audioSettled)
            audioSettled.restart();
    }

    function showAudioChange() {
        if (!audioArmed || !sink || !sink.ready || !audio)
            return;
        const volume = Math.round(audio.volume * 100);
        if (volume === lastVolume && audio.muted === lastMuted)
            return;
        lastVolume = volume;
        lastMuted = audio.muted;
        if (soundOpen)
            return;
        if (!volumeSlider.pressed) {
            osdScreen = focusedScreen();
            if (!osdRail)
                return;
            const clock = osdRail.triggerForPanel("calendar");
            osdAnchor = clock.mapToItem(osdRail.contentItem, 0, 0, clock.width, clock.height);
        }
        osdVisible = true;
        osdTimeout.restart();
    }

    onSinkChanged: armAudio()
    Component.onCompleted: armAudio()
    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }
    Connections {
        target: root.sink
        function onReadyChanged() {
            root.armAudio();
        }
    }
    Connections {
        target: root.audio
        function onVolumesChanged() {
            root.showAudioChange();
        }
        function onMutedChanged() {
            root.showAudioChange();
        }
    }
    Timer {
        id: audioSettled
        interval: 500
        onTriggered: {
            if (root.sink && root.sink.ready && root.audio) {
                root.lastVolume = Math.round(root.audio.volume * 100);
                root.lastMuted = root.audio.muted;
                root.audioArmed = true;
            }
        }
    }
    Timer {
        id: osdTimeout
        interval: 600
        onTriggered: {
            if (volumeSlider.pressed || muteButton.pressed || settingsButton.pressed)
                restart();
            else
                root.osdVisible = false;
        }
    }

    PanelWindow {
        id: osd
        screen: root.osdScreen
        visible: root.osdVisible && root.osdRail !== null && root.osdScreen !== null
        anchors {
            top: true
            left: true
        }
        implicitWidth: 72
        implicitHeight: Math.min(320, (root.osdScreen ? root.osdScreen.height : 1080) - 24)
        margins.left: Math.max(12, Math.min((root.osdRail ? root.osdRail.width : 80) + 8, (root.osdScreen ? root.osdScreen.width : 1920) - width - 12))
        margins.top: Math.max(12, Math.min(root.osdAnchor.y + root.osdAnchor.height / 2 - height / 2, (root.osdScreen ? root.osdScreen.height : 1080) - height - 12))
        color: "transparent"
        mask: Region {
            item: pill
            radius: Math.round(pill.radius)
        }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: Theme.reducedMotion ? "expressive-osd-static" : "expressive-osd"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        Rectangle {
            id: pill
            anchors.fill: parent
            radius: width / 2
            color: Theme.surface
            Accessible.role: Accessible.Grouping
            Accessible.name: root.lastMuted ? "Volume controls, muted" : "Volume controls"
            focus: true
            Keys.onEscapePressed: {
                root.osdVisible = false;
                osdTimeout.stop();
            }
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8
                ExpressiveButton {
                    id: muteButton
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    prominent: root.lastMuted
                    enabled: !!root.sink && root.sink.ready && !!root.audio
                    description: root.lastMuted ? "Unmute sound" : "Mute sound"
                    onPressedChanged: osdTimeout.restart()
                    onClicked: {
                        root.audio.muted = !root.audio.muted;
                        osdTimeout.restart();
                    }
                    contentItem: Item {
                        MaterialIcon {
                            anchors.centerIn: parent
                            name: root.lastMuted ? "volume_off" : "volume_up"
                            tint: muteButton.prominent ? Theme.textOnPrimary : Theme.primary
                        }
                    }
                }
                ExpressiveSlider {
                    id: volumeSlider
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 56
                    Layout.fillHeight: true
                    orientation: Qt.Vertical
                    handleLength: 56
                    endRadius: Theme.radiusMedium
                    inactiveColor: Theme.surfaceContainerHigh
                    from: 0
                    to: 100
                    stepSize: 1
                    value: Math.max(0, Math.min(100, root.lastVolume))
                    enabled: !!root.sink && root.sink.ready && !!root.audio
                    wheelEnabled: true
                    Accessible.name: "Sound volume"
                    Accessible.description: root.lastMuted ? "Muted" : root.lastVolume + " percent"
                    onPressedChanged: osdTimeout.restart()
                    onMoved: {
                        root.audio.muted = false;
                        root.audio.volume = value / 100;
                        osdTimeout.restart();
                    }
                    MaterialIcon {
                        parent: volumeSlider.inactiveTrack
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: 12
                        name: "music_note"
                        visible: parent !== null && parent.height >= 48
                    }
                }
                ExpressiveButton {
                    id: settingsButton
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    description: "Open sound controls"
                    onPressedChanged: osdTimeout.restart()
                    onClicked: {
                        root.osdVisible = false;
                        osdTimeout.stop();
                        if (root.osdRail)
                            root.shell.togglePanel("sound", root.osdScreen, root.osdRail.triggerForPanel("calendar"));
                    }
                    background: Rectangle {
                        radius: height / 2
                        color: settingsButton.hovered ? Theme.surfaceContainerHigh : "transparent"
                        border.width: settingsButton.visualFocus ? 2 : 0
                        border.color: Theme.primary
                    }
                    contentItem: Item {
                        MaterialIcon {
                            anchors.centerIn: parent
                            name: "tune"
                        }
                    }
                }
            }
        }
    }
}
