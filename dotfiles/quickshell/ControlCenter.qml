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
    implicitWidth: 440
    implicitHeight: 576
    property bool showNetworks: false
    property bool showBluetooth: false
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

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
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
            Label {
                text: volumeControl.title
                font.pixelSize: 18
                font.styleName: "Bold Rounded"
                Layout.fillWidth: true
            }
            Label {
                text: volumeControl.audio ? (volumeControl.audio.muted ? "Muted" : Math.round(volumeControl.audio.volume * 100) + "%") : "Unavailable"
                color: Theme.textOnSurfaceVariant
            }
        }
        Label {
            Layout.fillWidth: true
            text: volumeControl.node ? (volumeControl.node.description || volumeControl.node.nickname || volumeControl.node.name) : (Pipewire.ready ? "No audio device" : "PipeWire unavailable")
            color: Theme.textOnSurfaceVariant
            maximumLineCount: 2
            elide: Text.ElideRight
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            ExpressiveButton {
                Layout.preferredWidth: 72
                enabled: !!volumeControl.audio
                checked: volumeControl.audio ? volumeControl.audio.muted : false
                text: checked ? "Unmute" : "Mute"
                description: (checked ? "Unmute " : "Mute ") + volumeControl.title.toLowerCase()
                onClicked: volumeControl.audio.muted = !volumeControl.audio.muted
            }
            Slider {
                id: slider
                Layout.fillWidth: true
                Layout.minimumHeight: 48
                enabled: !!volumeControl.audio
                from: 0
                to: 1
                stepSize: 0.01
                value: volumeControl.audio ? volumeControl.audio.volume : 0
                focusPolicy: Qt.StrongFocus
                Accessible.name: volumeControl.title + " volume"
                Accessible.description: "Use left and right arrow keys to adjust the volume"
                onMoved: if (volumeControl.audio)
                    volumeControl.audio.volume = value
                background: Rectangle {
                    x: slider.leftPadding
                    y: slider.topPadding + slider.availableHeight / 2 - height / 2
                    width: slider.availableWidth
                    height: 28
                    radius: 14
                    color: Theme.secondaryContainer
                    opacity: slider.enabled ? 1 : 0.38
                    Rectangle {
                        width: slider.visualPosition * parent.width
                        height: parent.height
                        radius: parent.radius
                        color: Theme.primary
                    }
                }
                handle: Rectangle {
                    x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                    y: slider.topPadding + slider.availableHeight / 2 - height / 2
                    width: slider.pressed ? 8 : 6
                    height: 44
                    radius: 3
                    color: Theme.primary
                    border.width: slider.visualFocus ? 2 : 0
                    border.color: Theme.textOnSurface
                    opacity: slider.enabled ? 1 : 0.38
                    Behavior on width {
                        NumberAnimation {
                            duration: Theme.motionDuration
                        }
                    }
                }
            }
        }
        ComboBox {
            id: devicePicker
            Layout.fillWidth: true
            Layout.minimumHeight: 48
            visible: volumeControl.devices.length > 1
            model: volumeControl.devices
            textRole: "description"
            currentIndex: volumeControl.devices.indexOf(volumeControl.node)
            Accessible.name: "Select " + volumeControl.title.toLowerCase() + " device"
            font.family: Theme.fontFamily
            font.styleName: "Rounded"
            font.pixelSize: 14
            palette.button: Theme.surfaceContainerHighest
            palette.buttonText: Theme.textOnSurface
            palette.base: Theme.surfaceContainerHigh
            palette.text: Theme.textOnSurface
            palette.highlight: Theme.secondaryContainer
            palette.highlightedText: Theme.textOnSecondaryContainer
            background: Rectangle {
                radius: Theme.radiusSmall
                color: Theme.surfaceContainerHighest
                border.width: devicePicker.visualFocus ? 2 : 0
                border.color: Theme.primary
            }
            onActivated: index => {
                if (volumeControl.input)
                    Pipewire.preferredDefaultAudioSource = volumeControl.devices[index];
                else
                    Pipewire.preferredDefaultAudioSink = volumeControl.devices[index];
            }
        }
    }

    ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ColumnLayout {
            width: scroll.availableWidth
            spacing: 12
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: headline.implicitHeight + 40
                radius: Theme.radiusExtraLarge
                color: Theme.primaryContainer
                ColumnLayout {
                    id: headline
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 0
                    Label {
                        text: "Your space"
                        font.pixelSize: 22
                        font.styleName: "Bold Rounded"
                        color: Theme.textOnPrimaryContainer
                    }
                    Label {
                        text: Qt.formatDateTime(clock.date, "HH:mm")
                        font.pixelSize: 68
                        font.styleName: "Bold Rounded"
                        font.letterSpacing: -3
                        color: Theme.textOnPrimaryContainer
                    }
                    Label {
                        text: Qt.formatDateTime(clock.date, "dddd, d MMMM")
                        font.pixelSize: 17
                        color: Theme.textOnPrimaryContainer
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: connectivity.implicitHeight + 24
                radius: Theme.radiusLarge
                color: Theme.surfaceContainer
                ColumnLayout {
                    id: connectivity
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10
                    Label {
                        text: "Stay connected"
                        font.pixelSize: 22
                        font.styleName: "Bold Rounded"
                    }
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
                                value: root.visible && root.showNetworks && Networking.wifiEnabled
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

            Rectangle {
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
                        title: "Output"
                        node: Pipewire.defaultAudioSink
                        devices: root.outputs
                        input: false
                    }
                    VolumeControl {
                        Layout.fillWidth: true
                        title: "Microphone"
                        node: Pipewire.defaultAudioSource
                        devices: root.inputs
                        input: true
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
                visible: Mpris.players.values.length === 0
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                text: "Nothing playing · Open a media app to see playback controls."
                color: Theme.textOnSurfaceVariant
            }
            Repeater {
                model: Mpris.players
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
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    source: media.modelData.trackArtUrl
                                    sourceSize.width: 144
                                    sourceSize.height: 144
                                    asynchronous: true
                                    fillMode: Image.PreserveAspectFit
                                }
                                Label {
                                    anchors.centerIn: parent
                                    visible: artwork.status !== Image.Ready
                                    text: "♪"
                                    font.pixelSize: 36
                                    color: Theme.textOnSurfaceVariant
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
                            spacing: 4
                            GroupButton {
                                Layout.fillWidth: true
                                text: "Previous"
                                description: "Previous track in " + media.modelData.identity
                                enabled: media.modelData.canControl && media.modelData.canGoPrevious
                                onClicked: media.modelData.previous()
                            }
                            GroupButton {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 56
                                text: media.modelData.isPlaying ? "Pause" : "Play"
                                prominent: true
                                description: text + " in " + media.modelData.identity
                                enabled: media.modelData.canControl && media.modelData.canTogglePlaying
                                onClicked: media.modelData.togglePlaying()
                            }
                            GroupButton {
                                Layout.fillWidth: true
                                text: "Next"
                                description: "Next track in " + media.modelData.identity
                                enabled: media.modelData.canControl && media.modelData.canGoNext
                                onClicked: media.modelData.next()
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: personal.implicitHeight + 24
                radius: Theme.radiusLarge
                color: Theme.surfaceContainer
                ColumnLayout {
                    id: personal
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8
                    Label {
                        text: "Make it yours"
                        font.pixelSize: 22
                        font.styleName: "Bold Rounded"
                    }
                    GroupButton {
                        Layout.fillWidth: true
                        text: root.shell.notifications.dnd ? "Do Not Disturb · on" : "Do Not Disturb · off"
                        checked: root.shell.notifications.dnd
                        description: "Toggle Do Not Disturb; notifications remain in history"
                        onClicked: root.shell.notifications.dnd = !root.shell.notifications.dnd
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        GroupButton {
                            Layout.fillWidth: true
                            text: "Wallpaper"
                            description: "Choose a still wallpaper and matching colors"
                            onClicked: root.launch(["wpp"])
                        }
                        GroupButton {
                            Layout.fillWidth: true
                            text: "Animated"
                            description: "Choose an animated wallpaper and matching colors"
                            onClicked: root.launch(["awpp"])
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        GroupButton {
                            Layout.fillWidth: true
                            text: "Night light"
                            description: "Configure night light warmth or follow the schedule"
                            onClicked: root.launch(["sunp"])
                        }
                        GroupButton {
                            Layout.fillWidth: true
                            text: "Power"
                            description: "Open session and power actions"
                            onClicked: root.launch(["powermenu"])
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
