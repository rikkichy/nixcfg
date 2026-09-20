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

    property bool dnd: false
    // Entries own a RetainableLock: their notification remains readable after expiry.
    // Only active entries may invoke actions. dismiss() accepts an entry or its notification.
    readonly property var entries: items.filter(entry => !entry.notification.transient)
    readonly property int count: entries.length
    property var items: []

    function focusedScreen() {
        const monitor = Hyprland.focusedMonitor;
        return Quickshell.screens.find(screen => monitor && screen.name === monitor.name)
            || Quickshell.screens[0] || null;
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
            const entry = entryFactory.createObject(root, { notification: notification });
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
                // Quickshell 0.3.1 forwards D-Bus milliseconds, despite its header's seconds comment.
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
                // Replacements mutate this same QObject; coalesce the changed fields.
                function onSummaryChanged() { Qt.callLater(entry.refresh); }
                function onBodyChanged() { Qt.callLater(entry.refresh); }
                function onAppNameChanged() { Qt.callLater(entry.refresh); }
                function onAppIconChanged() { Qt.callLater(entry.refresh); }
                function onImageChanged() { Qt.callLater(entry.refresh); }
                function onActionsChanged() { Qt.callLater(entry.refresh); }
                function onHintsChanged() { Qt.callLater(entry.refresh); }
                function onExpireTimeoutChanged() { Qt.callLater(entry.refresh); }
                function onUrgencyChanged() { Qt.callLater(entry.refresh); }
                function onResidentChanged() { Qt.callLater(entry.refresh); }
                function onTransientChanged() { Qt.callLater(entry.refresh); }
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
            anchors { top: true; right: true }
            margins { top: 16; right: 16 }
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
    property real lastVolume: -1
    property bool lastMuted: false

    function armAudio() {
        audioArmed = false;
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
        osdScreen = focusedScreen();
        osdTimeout.restart();
    }

    onSinkChanged: armAudio()
    Component.onCompleted: armAudio()
    PwObjectTracker { objects: root.sink ? [root.sink] : [] }
    Connections {
        target: root.sink
        function onReadyChanged() { root.armAudio(); }
    }
    Connections {
        target: root.audio
        function onVolumesChanged() { root.showAudioChange(); }
        function onMutedChanged() { root.showAudioChange(); }
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
    Timer { id: osdTimeout; interval: 1800 }

    PanelWindow {
        id: osd
        screen: root.osdScreen
        visible: osdTimeout.running && root.osdScreen !== null
        anchors.bottom: true
        margins.bottom: 48
        implicitWidth: 340
        implicitHeight: 100
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "expressive-osd"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusExtraLarge
            color: Theme.secondaryContainer
            Accessible.role: Accessible.ProgressBar
            Accessible.name: root.lastMuted ? "Audio muted" : "Volume " + root.lastVolume + " percent"
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 12
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: root.lastMuted ? "Audio muted" : "Volume"
                        font.family: Theme.fontFamily
                        font.styleName: "Rounded"
                        font.pixelSize: 18
                        font.weight: Font.Medium
                        color: Theme.textOnSecondaryContainer
                        Layout.fillWidth: true
                    }
                    Text {
                        text: root.lastVolume + "%"
                        font.family: Theme.fontFamily
                        font.styleName: "Rounded"
                        font.pixelSize: 18
                        color: Theme.textOnSecondaryContainer
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 10
                    radius: 5
                    color: Theme.surfaceContainerHighest
                    Rectangle {
                        height: parent.height
                        width: parent.width * (root.lastMuted ? 0 : Math.max(0, Math.min(1, root.lastVolume / 100)))
                        radius: 5
                        color: Theme.primary
                        Behavior on width { NumberAnimation { duration: Theme.motionDuration; easing.type: Easing.OutCubic } }
                    }
                }
            }
        }
    }
}
