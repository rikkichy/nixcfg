import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Networking
import Quickshell.Bluetooth

Item {
    id: root
    required property var shell
    required property string section
    implicitWidth: 440
    implicitHeight: Math.min(560, content.implicitHeight)
    property bool showNetworks: true
    property bool showBluetooth: true
    property string networkError: ""
    property string bluetoothError: ""
    readonly property bool hasWifi: Networking.devices.values.some(device => device.type === DeviceType.Wifi)
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var outputs: Pipewire.nodes.values.filter(node => node.audio && node.isSink && !node.isStream)
    readonly property var inputs: Pipewire.nodes.values.filter(node => node.audio && !node.isSink && !node.isStream)

    function launch(command) {
        shell.closePanel();
        Quickshell.execDetached(command);
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource].filter(node => node !== null)
    }

    component Label: Text {
        color: Theme.textOnSurface
        font.family: Theme.fontFamily
        font.styleName: "Rounded"
        font.pixelSize: 14
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        Accessible.role: Accessible.StaticText
        Accessible.name: text
    }

    component GroupButton: ExpressiveButton {
        id: button
        background: Rectangle {
            radius: button.down ? 8 : Theme.radiusSmall
            color: button.prominent ? Theme.primary : button.checked ? Theme.secondaryContainer : button.hovered ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
            border.width: button.visualFocus ? 2 : 0
            border.color: Theme.primary
            Behavior on radius {
                NumberAnimation {
                    duration: Theme.motionDuration
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on color {
                ColorAnimation {
                    duration: Theme.motionDuration
                }
            }
        }
    }

    component PlaybackButton: ExpressiveButton {
        id: button
        required property string iconName
        required property int position
        Layout.fillWidth: true
        Layout.preferredHeight: 56
        scale: 1
        contentItem: Item {
            MaterialIcon {
                anchors.centerIn: parent
                width: 28
                height: 28
                name: button.iconName
                tint: button.prominent ? Theme.textOnPrimary : Theme.textOnSecondaryContainer
            }
        }
        background: Rectangle {
            radius: button.down ? 12 : 8
            topLeftRadius: button.position === 0 ? 28 : radius
            bottomLeftRadius: topLeftRadius
            topRightRadius: button.position === 2 ? 28 : radius
            bottomRightRadius: topRightRadius
            color: button.prominent ? Theme.primary : Theme.secondaryContainer
            border.width: button.visualFocus ? 2 : 0
            border.color: Theme.textOnSurface
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                topLeftRadius: parent.topLeftRadius
                bottomLeftRadius: parent.bottomLeftRadius
                topRightRadius: parent.topRightRadius
                bottomRightRadius: parent.bottomRightRadius
                color: button.prominent ? Theme.textOnPrimary : Theme.textOnSecondaryContainer
                opacity: button.down ? 0.1 : button.hovered ? 0.08 : 0
            }
            Behavior on radius {
                NumberAnimation {
                    duration: Theme.reducedMotion ? 0 : 150
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.31, 0.94, 0.34, 1, 1, 1]
                }
            }
        }
    }

    component VolumeControl: ColumnLayout {
        id: volumeControl
        required property string title
        required property var node
        required property var devices
        required property bool input
        readonly property var audio: node && node.ready ? node.audio : null
        spacing: 4
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            ExpressiveComboBox {
                id: devicePicker
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                enabled: volumeControl.devices.length > 1
                model: volumeControl.devices
                textRole: "description"
                currentIndex: volumeControl.devices.indexOf(volumeControl.node)
                displayText: volumeControl.node ? (volumeControl.node.description || volumeControl.node.nickname || volumeControl.node.name) : (Pipewire.ready ? "No audio device" : "PipeWire unavailable")
                Accessible.name: "Select " + volumeControl.title.toLowerCase() + " device"
                onActivated: index => {
                    if (volumeControl.input)
                        Pipewire.preferredDefaultAudioSource = volumeControl.devices[index];
                    else
                        Pipewire.preferredDefaultAudioSink = volumeControl.devices[index];
                }
            }
            Switch {
                id: audioSwitch
                implicitWidth: 52
                implicitHeight: 48
                padding: 0
                hoverEnabled: true
                focusPolicy: Qt.StrongFocus
                enabled: !!volumeControl.audio
                checked: volumeControl.audio ? !volumeControl.audio.muted : false
                Accessible.name: volumeControl.input ? "Microphone enabled" : "Sound enabled"
                Accessible.description: checked ? "Turn off to mute" : "Turn on to unmute"
                onToggled: if (volumeControl.audio)
                    volumeControl.audio.muted = !checked
                contentItem: null
                background: Rectangle {
                    color: "transparent"
                    radius: 20
                    border.width: audioSwitch.visualFocus ? 2 : 0
                    border.color: Theme.primary
                }
                // Material Switch tokens: 52x32 track; 16/24px thumb, 28px while pressed.
                indicator: Rectangle {
                    implicitWidth: 52
                    implicitHeight: 32
                    x: (audioSwitch.width - width) / 2
                    y: (audioSwitch.height - height) / 2
                    radius: height / 2
                    color: audioSwitch.checked ? Theme.primary : Theme.surfaceContainerHighest
                    border.width: audioSwitch.checked ? 0 : 2
                    border.color: Theme.outline
                    opacity: audioSwitch.enabled ? 1 : 0.38
                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.motionDuration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.2, 0, 0, 1, 1, 1]
                        }
                    }
                    Rectangle {
                        // Fixed thumb geometry adapted from QmlMaterial (MIT; see LICENSE.QmlMaterial).
                        // Fixed geometry keeps position independent of the thumb's visible size.
                        width: 28
                        height: 28
                        radius: 14
                        x: Math.max(2, Math.min(parent.width - 2 - width, audioSwitch.visualPosition * parent.width - width / 2))
                        y: (parent.height - height) / 2
                        color: audioSwitch.checked ? Theme.textOnPrimary : Theme.outline
                        scale: (audioSwitch.pressed ? 28 : audioSwitch.checked ? 24 : 16) / 28
                        Behavior on x {
                            enabled: !Theme.reducedMotion && !audioSwitch.pressed
                            // m3e@2.8.2 showcase fast-spatial timing.
                            NumberAnimation {
                                duration: 350
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: [0.27, 1.06, 0.18, 1, 1, 1]
                            }
                        }
                        Behavior on scale {
                            enabled: !Theme.reducedMotion
                            // m3e@2.8.2 showcase fast-effects timing.
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: [0.31, 0.94, 0.34, 1, 1, 1]
                            }
                        }
                        Behavior on color {
                            ColorAnimation {
                                duration: Theme.motionDuration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: [0.2, 0, 0, 1, 1, 1]
                            }
                        }
                    }
                }
            }
        }
        ExpressiveSlider {
            id: slider
            Layout.fillWidth: true
            Layout.minimumHeight: 56
            enabled: !!volumeControl.audio
            from: 0
            to: 1
            stepSize: 0.01
            value: volumeControl.audio ? volumeControl.audio.volume : 0
            Accessible.name: volumeControl.title + " volume"
            Accessible.description: "Use left and right arrow keys to adjust the volume"
            onMoved: if (volumeControl.audio)
                volumeControl.audio.volume = value
        }
    }

    ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ColumnLayout {
            id: content
            width: scroll.availableWidth
            spacing: 12

            Rectangle {
                visible: root.section === "network" || root.section === "bluetooth"
                Layout.fillWidth: true
                implicitHeight: connectivity.implicitHeight + 24
                radius: Theme.radiusLarge
                color: Theme.surfaceContainer
                ColumnLayout {
                    id: connectivity
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.section === "network"
                        spacing: 10
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            GroupButton {
                                Layout.fillWidth: true
                                text: !root.hasWifi ? "Wi-Fi unavailable" : !Networking.wifiHardwareEnabled ? "Wi-Fi blocked" : Networking.wifiEnabled ? "Wi-Fi on" : "Wi-Fi off"
                                checked: root.hasWifi && Networking.wifiEnabled
                                enabled: root.hasWifi && Networking.wifiHardwareEnabled
                                description: "Toggle Wi-Fi radio"
                                onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                            }
                            GroupButton {
                                Layout.preferredWidth: 88
                                text: root.showNetworks ? "Less" : "Networks"
                                checked: root.showNetworks
                                description: "Show available network connections"
                                onClicked: root.showNetworks = !root.showNetworks
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            color: Theme.textOnSurfaceVariant
                            text: Networking.backend === NetworkBackendType.None ? "Network service unavailable" : Networking.devices.values.length === 0 ? "No network devices available" : "Internet · " + NetworkConnectivity.toString(Networking.connectivity)
                        }
                        Repeater {
                            model: Networking.devices
                            delegate: ColumnLayout {
                                id: networkDevice
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 4
                                Binding {
                                    target: networkDevice.modelData.type === DeviceType.Wifi ? networkDevice.modelData : null
                                    property: "scannerEnabled"
                                    value: root.shell.panel === "network" && root.showNetworks && Networking.wifiEnabled
                                    restoreMode: Binding.RestoreBindingOrValue
                                }
                                Label {
                                    Layout.fillWidth: true
                                    color: Theme.textOnSurfaceVariant
                                    text: networkDevice.modelData.name + " · " + ConnectionState.toString(networkDevice.modelData.state)
                                }
                                Repeater {
                                    model: networkDevice.modelData.networks
                                    delegate: GroupButton {
                                        id: networkButton
                                        required property var modelData
                                        Layout.fillWidth: true
                                        visible: root.showNetworks || modelData.connected
                                        text: (modelData.name || "Unnamed network") + " · " + ConnectionState.toString(modelData.state)
                                        checked: modelData.connected
                                        enabled: !modelData.stateChanging
                                        description: (modelData.connected ? "Disconnect from " : "Connect to ") + (modelData.name || "network")
                                        onClicked: {
                                            root.networkError = "";
                                            if (modelData.connected)
                                                modelData.disconnect();
                                            else if (modelData.known || networkDevice.modelData.type === DeviceType.Wired || modelData.security === WifiSecurityType.Open)
                                                modelData.connect();
                                            else
                                                root.launch(["foot", "-e", "nmtui"]);
                                        }
                                        Connections {
                                            target: networkButton.modelData
                                            function onConnectionFailed(reason) {
                                                root.networkError = (networkButton.modelData.name || "Network") + ": " + ConnectionFailReason.toString(reason) + ". Open network settings to check credentials.";
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            visible: root.networkError.length > 0
                            text: root.networkError
                            color: Theme.error
                        }
                        GroupButton {
                            Layout.fillWidth: true
                            text: "Network settings"
                            description: "Manage networks, passwords and VPNs in nmtui"
                            onClicked: root.launch(["foot", "-e", "nmtui"])
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.section === "bluetooth"
                        spacing: 10
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            GroupButton {
                                Layout.fillWidth: true
                                text: root.adapter ? "Bluetooth · " + BluetoothAdapterState.toString(root.adapter.state) : "Bluetooth unavailable"
                                checked: root.adapter ? root.adapter.enabled : false
                                enabled: root.adapter !== null && root.adapter.state !== BluetoothAdapterState.Blocked && root.adapter.state !== BluetoothAdapterState.Enabling && root.adapter.state !== BluetoothAdapterState.Disabling
                                description: "Toggle Bluetooth adapter"
                                onClicked: root.adapter.enabled = !root.adapter.enabled
                            }
                            GroupButton {
                                Layout.preferredWidth: 88
                                text: root.showBluetooth ? "Less" : "Devices"
                                checked: root.showBluetooth
                                description: "Show Bluetooth devices"
                                onClicked: root.showBluetooth = !root.showBluetooth
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            visible: !root.adapter || root.adapter.state === BluetoothAdapterState.Blocked
                            text: root.adapter ? "Bluetooth is blocked by the hardware radio switch." : "No Bluetooth adapter available"
                            color: root.adapter ? Theme.error : Theme.textOnSurfaceVariant
                        }
                        Repeater {
                            model: Bluetooth.devices
                            delegate: GroupButton {
                                id: bluetoothButton
                                required property var modelData
                                property bool connecting: false
                                Layout.fillWidth: true
                                visible: modelData.connected || (root.showBluetooth && (modelData.paired || modelData.bonded))
                                text: (modelData.name || modelData.address) + " · " + BluetoothDeviceState.toString(modelData.state)
                                checked: modelData.connected
                                enabled: modelData.adapter && modelData.adapter.enabled && modelData.state !== BluetoothDeviceState.Connecting && modelData.state !== BluetoothDeviceState.Disconnecting
                                description: (modelData.connected ? "Disconnect " : "Connect ") + (modelData.name || modelData.address)
                                onClicked: {
                                    root.bluetoothError = "";
                                    if (modelData.connected) {
                                        modelData.disconnect();
                                    } else {
                                        connecting = true;
                                        modelData.connect();
                                    }
                                }
                                Connections {
                                    target: bluetoothButton.modelData
                                    function onStateChanged() {
                                        if (!bluetoothButton.connecting)
                                            return;
                                        if (bluetoothButton.modelData.state === BluetoothDeviceState.Connected)
                                            bluetoothButton.connecting = false;
                                        else if (bluetoothButton.modelData.state === BluetoothDeviceState.Disconnected) {
                                            bluetoothButton.connecting = false;
                                            root.bluetoothError = "Could not connect to " + (bluetoothButton.modelData.name || bluetoothButton.modelData.address) + ". Open Bluetooth settings for details or pairing.";
                                        }
                                    }
                                }
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            visible: root.bluetoothError.length > 0
                            text: root.bluetoothError
                            color: Theme.error
                        }
                        GroupButton {
                            Layout.fillWidth: true
                            text: "Bluetooth settings & pairing"
                            description: "Discover, pair and manage Bluetooth devices in Blueman"
                            onClicked: root.launch(["blueman-manager"])
                        }
                    }
                }
            }

            Rectangle {
                visible: root.section === "microphone" || root.section === "sound"
                Layout.fillWidth: true
                implicitHeight: audioControls.implicitHeight + 32
                radius: Theme.radiusLarge
                color: Theme.surfaceContainer
                ColumnLayout {
                    id: audioControls
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 16
                    VolumeControl {
                        Layout.fillWidth: true
                        title: root.section === "microphone" ? "Input" : "Output"
                        node: root.section === "microphone" ? Pipewire.defaultAudioSource : Pipewire.defaultAudioSink
                        devices: root.section === "microphone" ? root.inputs : root.outputs
                        input: root.section === "microphone"
                    }
                    ExpressiveButton {
                        Layout.fillWidth: true
                        text: "Audio settings"
                        description: "Manage applications, audio devices and profiles"
                        onClicked: root.launch(["pavucontrol"])
                    }
                }
            }

            Label {
                visible: root.section === "sound" && Mpris.players.values.length === 0
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                text: "Nothing playing · Open a media app to see playback controls."
                color: Theme.textOnSurfaceVariant
            }
            Repeater {
                model: root.section === "sound" ? Mpris.players : null
                delegate: Rectangle {
                    id: media
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: mediaContent.implicitHeight + 32
                    radius: Theme.radiusExtraLarge
                    color: Theme.tertiaryContainer
                    ColumnLayout {
                        id: mediaContent
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 12
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            Rectangle {
                                Layout.preferredWidth: 80
                                Layout.preferredHeight: 80
                                radius: Theme.radiusMedium
                                color: Theme.surfaceContainerHigh
                                Image {
                                    id: artwork
                                    // Keep album art; video-shaped thumbnails use the music placeholder.
                                    readonly property bool usableCover: status === Image.Ready && paintedHeight > 0 && paintedWidth < paintedHeight * 1.5
                                    opacity: usableCover ? 1 : 0
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    source: media.modelData.trackArtUrl
                                    sourceSize.width: 144
                                    sourceSize.height: 144
                                    asynchronous: true
                                    fillMode: Image.PreserveAspectFit
                                }
                                MaterialIcon {
                                    anchors.centerIn: parent
                                    visible: !artwork.usableCover
                                    name: "music_note"
                                    width: 36
                                    height: 36
                                    tint: Theme.textOnSurfaceVariant
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Label {
                                    Layout.fillWidth: true
                                    text: media.modelData.identity + " · " + MprisPlaybackState.toString(media.modelData.playbackState)
                                    font.pixelSize: 12
                                    color: Theme.textOnTertiaryContainer
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: media.modelData.trackTitle || "No track title"
                                    font.pixelSize: 21
                                    font.styleName: "Bold Rounded"
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    color: Theme.textOnTertiaryContainer
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: media.modelData.trackArtist || media.modelData.trackAlbum || "Unknown artist"
                                    maximumLineCount: 1
                                    elide: Text.ElideRight
                                    color: Theme.textOnTertiaryContainer
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Accessible.role: Accessible.Grouping
                            Accessible.name: "Playback controls for " + media.modelData.identity
                            PlaybackButton {
                                position: 0
                                iconName: "skip_previous"
                                description: "Previous track in " + media.modelData.identity
                                enabled: media.modelData.canControl && media.modelData.canGoPrevious
                                onClicked: media.modelData.previous()
                            }
                            PlaybackButton {
                                position: 1
                                iconName: media.modelData.isPlaying ? "pause" : "play_arrow"
                                prominent: true
                                description: (media.modelData.isPlaying ? "Pause" : "Play") + " in " + media.modelData.identity
                                enabled: media.modelData.canControl && media.modelData.canTogglePlaying
                                onClicked: media.modelData.togglePlaying()
                            }
                            PlaybackButton {
                                position: 2
                                iconName: "skip_next"
                                description: "Next track in " + media.modelData.identity
                                enabled: media.modelData.canControl && media.modelData.canGoNext
                                onClicked: media.modelData.next()
                            }
                        }
                    }
                }
            }

            Item {
                Layout.preferredHeight: 4
            }
        }
    }
}
