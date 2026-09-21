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
            Label {
                text: volumeControl.node ? (volumeControl.node.description || volumeControl.node.nickname || volumeControl.node.name) : (Pipewire.ready ? "No audio device" : "PipeWire unavailable")
                font.pixelSize: 18
                font.styleName: "Bold Rounded"
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                wrapMode: Text.NoWrap
                maximumLineCount: 1
                elide: Text.ElideRight
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
                        }
                    }
                    Rectangle {
                        id: switchThumb
                        width: 16
                        height: width
                        radius: width / 2
                        x: audioSwitch.mirrored ? parent.width - 24 : 8
                        y: (parent.height - height) / 2
                        color: audioSwitch.checked ? Theme.textOnPrimary : Theme.outline
                        state: audioSwitch.down ? "pressed" : audioSwitch.checked ? "on" : "off"
                        states: [
                            State {
                                name: "pressed"
                                PropertyChanges {
                                    target: switchThumb
                                    width: 28
                                    x: 2 + (audioSwitch.indicator.width - 32) * audioSwitch.visualPosition
                                }
                            },
                            State {
                                name: "on"
                                PropertyChanges {
                                    target: switchThumb
                                    width: 24
                                    x: audioSwitch.mirrored ? 4 : audioSwitch.indicator.width - 28
                                }
                            },
                            State {
                                name: "off"
                                PropertyChanges {
                                    target: switchThumb
                                    width: 16
                                    x: audioSwitch.mirrored ? audioSwitch.indicator.width - 24 : 8
                                }
                            }
                        ]
                        // Material snaps the pressed shape, then springs size/offset to fixed endpoints.
                        transitions: [
                            Transition {
                                to: "pressed"
                                PropertyAction {
                                    properties: "x,width"
                                }
                            },
                            Transition {
                                enabled: !Theme.reducedMotion
                                SpringAnimation {
                                    properties: "x,width"
                                    spring: 3.2
                                    damping: 0.13576
                                    mass: 0.25
                                    epsilon: 0.05
                                }
                            }
                        ]
                        Behavior on color {
                            ColorAnimation {
                                duration: Theme.motionDuration
                            }
                        }
                    }
                }
            }
        }
        Slider {
            id: slider
            Layout.fillWidth: true
            Layout.minimumHeight: 56
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
            background: Item {
                x: slider.leftPadding
                y: slider.topPadding + slider.availableHeight / 2 - height / 2
                width: slider.availableWidth
                height: 40
                // Separate tracks leave the Material 6px gap on both sides of the handle.
                Rectangle {
                    width: Math.max(0, slider.handle.x - slider.leftPadding - 6)
                    height: parent.height
                    radius: 2
                    topLeftRadius: Theme.radiusSmall
                    bottomLeftRadius: Theme.radiusSmall
                    color: slider.enabled ? (slider.mirrored ? Theme.secondaryContainer : Theme.primary) : Theme.textOnSurface
                    opacity: slider.enabled ? 1 : slider.mirrored ? 0.12 : 0.38
                }
                Rectangle {
                    x: Math.min(parent.width, slider.handle.x - slider.leftPadding + slider.handle.width + 6)
                    width: Math.max(0, parent.width - x)
                    height: parent.height
                    radius: 2
                    topRightRadius: Theme.radiusSmall
                    bottomRightRadius: Theme.radiusSmall
                    color: slider.enabled ? (slider.mirrored ? Theme.primary : Theme.secondaryContainer) : Theme.textOnSurface
                    opacity: slider.enabled ? 1 : slider.mirrored ? 0.38 : 0.12
                }
            }
            handle: Rectangle {
                x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                y: slider.topPadding + slider.availableHeight / 2 - height / 2
                width: slider.pressed ? 2 : 4
                height: 52
                radius: width / 2
                color: slider.enabled ? Theme.primary : Theme.textOnSurface
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

            Item {
                Layout.preferredHeight: 4
            }
        }
    }
}
