import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Networking
import Quickshell.Bluetooth

PanelWindow {
    id: bar

    required property var shell
    required property var modelData
    property bool trayExpanded: false
    onVisibleChanged: if (!visible)
        trayExpanded = false
    screen: modelData
    visible: shell.barsVisible
    anchors {
        left: true
        top: true
        bottom: true
    }
    implicitWidth: 80
    exclusiveZone: 80
    color: "transparent"
    WlrLayershell.namespace: "expressive-bar"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    readonly property var monitor: Hyprland.monitors.values.find(candidate => candidate.name === screen.name) || null
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var outputAudio: sink && sink.ready ? sink.audio : null
    readonly property var inputAudio: source && source.ready ? source.audio : null
    readonly property var networkDevice: Networking.devices.values.find(device => device.connected) || null
    readonly property bool bluetoothEnabled: Bluetooth.adapters.values.some(adapter => adapter.enabled)
    readonly property int bluetoothConnections: Bluetooth.devices.values.filter(device => device.connected).length
    readonly property var activeWorkspace: {
        const specialId = monitor?.lastIpcObject.specialWorkspace?.id;
        return (specialId ? Hyprland.workspaces.values.find(workspace => workspace.id === specialId) : null) || monitor?.activeWorkspace || null;
    }
    readonly property var occupiedWorkspaces: Hyprland.workspaces.values.filter(workspace => workspace.monitor === monitor && workspace.toplevels.values.length > 0).sort((a, b) => a.id - b.id)

    PwObjectTracker {
        objects: [bar.sink, bar.source].filter(node => node !== null)
    }
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    function triggerForPanel(name) {
        return name === "calendar" ? clockButton : name === "notifications" ? notificationsButton : name === "microphone" ? microphoneButton : name === "network" ? networkButton : name === "bluetooth" ? bluetoothButton : volumeButton;
    }

    function changeVolume(delta) {
        if (outputAudio)
            outputAudio.volume = Math.max(0, Math.min(1, outputAudio.volume + delta));
    }

    component RailButton: ExpressiveButton {
        width: 56
        anchors.horizontalCenter: parent.horizontalCenter
        onActiveFocusChanged: {
            if (!activeFocus)
                return;
            const top = mapToItem(rail, 0, 0).y;
            if (top < scroll.contentY)
                scroll.contentY = top;
            else if (top + height > scroll.contentY + scroll.height)
                scroll.contentY = top + height - scroll.height;
        }
    }

    Flickable {
        id: scroll
        anchors.fill: parent
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        clip: true
        contentWidth: width
        contentHeight: rail.height
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        ScrollBar.vertical: ScrollBar {
            policy: scroll.contentHeight > scroll.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        }

        Item {
            id: rail
            width: scroll.width
            height: Math.max(scroll.height, 2 * Math.max(120, lower.height + workspaceButtons.height + 8) + clockButton.height + 24)
            Keys.onEscapePressed: {
                bar.trayExpanded = false;
                trayToggle.forceActiveFocus();
            }

            Column {
                id: workspaceButtons
                width: parent.width
                anchors.top: clockButton.bottom
                anchors.topMargin: 8
                spacing: 4
                Repeater {
                    model: bar.occupiedWorkspaces
                    delegate: RailButton {
                        id: workspaceButton
                        required property var modelData
                        readonly property bool selected: modelData === bar.activeWorkspace
                        readonly property string workspaceIcon: modelData.name === "special:communication" ? "chat" : modelData.name === "special:music" ? "music_note" : modelData.id < 0 ? "layers" : ""
                        implicitHeight: selected ? 56 : 48
                        checked: selected
                        prominent: selected
                        text: workspaceIcon ? "" : String(modelData.id)
                        description: "Workspace " + modelData.name + "\n" + modelData.toplevels.values.map(window => window.title).join("\n")
                        onClicked: modelData.activate()
                        background: Rectangle {
                            radius: workspaceButton.down ? Theme.radiusSmall : height / 2
                            color: workspaceButton.selected ? Theme.primary : workspaceButton.modelData.urgent ? Theme.tertiaryContainer : workspaceButton.hovered ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                            border.width: workspaceButton.visualFocus ? 2 : 0
                            border.color: Theme.outline
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
                        contentItem: Item {
                            Text {
                                anchors.fill: parent
                                visible: !workspaceButton.workspaceIcon
                                text: workspaceButton.text
                                color: workspaceButton.selected ? Theme.textOnPrimary : workspaceButton.modelData.urgent ? Theme.textOnTertiaryContainer : Theme.textOnSurface
                                font.family: Theme.fontFamily
                                font.styleName: workspaceButton.selected ? "Bold Rounded" : "Rounded"
                                font.pixelSize: 18
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            Image {
                                anchors.centerIn: parent
                                visible: workspaceButton.workspaceIcon !== ""
                                width: 24
                                height: 24
                                source: workspaceButton.workspaceIcon ? Qt.resolvedUrl("icons/" + workspaceButton.workspaceIcon + ".svg") : ""
                                sourceSize.width: 24
                                sourceSize.height: 24
                                fillMode: Image.PreserveAspectFit
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    colorization: 1
                                    colorizationColor: workspaceButton.selected ? Theme.textOnPrimary : workspaceButton.modelData.urgent ? Theme.textOnTertiaryContainer : Theme.textOnSurface
                                }
                            }
                        }
                        Behavior on implicitHeight {
                            NumberAnimation {
                                duration: Theme.motionDuration
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: trayCapsule
                property real expansion: bar.trayExpanded ? 1 : 0
                Behavior on expansion {
                    enabled: !Theme.reducedMotion
                    SpringAnimation {
                        spring: 3.04
                        damping: 0.2495
                        mass: 0.5
                        epsilon: 0.001
                    }
                }
                property real inkOpacity: bar.trayExpanded ? 1 : 0
                Behavior on inkOpacity {
                    enabled: !Theme.reducedMotion
                    SpringAnimation {
                        spring: 3.2
                        damping: 0.16
                        mass: 0.125
                        epsilon: 0.001
                    }
                }
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: notificationsButton.top
                anchors.bottomMargin: 8
                width: notificationsButton.width
                height: trayToggle.height + trayViewport.height
                radius: width / 2 - (width / 2 - Theme.radiusMedium) * Math.max(0, Math.min(1, expansion))
                color: Theme.surfaceContainerHigh
                ScrollView {
                    id: trayViewport
                    readonly property real maximumHeight: Math.max(48, notificationsButton.y - trayToggle.height - 24)
                    anchors.top: parent.top
                    width: parent.width
                    height: Math.min(maximumHeight, Math.min(trayIcons.implicitHeight + 8, maximumHeight) * Math.max(0, trayCapsule.expansion))
                    topPadding: 4
                    bottomPadding: 4
                    clip: true
                    enabled: bar.trayExpanded
                    visible: height > 0
                    contentWidth: availableWidth
                    opacity: Math.max(0, Math.min(1, trayCapsule.inkOpacity))
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    Column {
                        id: trayIcons
                        width: trayViewport.availableWidth
                        spacing: 4
                        Repeater {
                            model: SystemTray.items
                            delegate: ExpressiveButton {
                                id: trayButton
                                width: 48
                                anchors.horizontalCenter: parent.horizontalCenter
                                required property var modelData
                                description: modelData.tooltipTitle || modelData.title || modelData.id
                                checked: modelData.status === Status.NeedsAttention
                                onClicked: modelData.onlyMenu && modelData.hasMenu ? trayMenu.open() : modelData.activate()
                                contentItem: Item {
                                    Image {
                                        anchors.centerIn: parent
                                        width: 24
                                        height: 24
                                        source: trayButton.modelData.icon
                                        sourceSize.width: 24
                                        sourceSize.height: 24
                                        fillMode: Image.PreserveAspectFit
                                    }
                                }
                                TrayMenu {
                                    id: trayMenu
                                    menuHandle: trayButton.modelData.menu
                                    x: trayButton.width + 8
                                    y: 0
                                }
                                TapHandler {
                                    acceptedButtons: Qt.RightButton
                                    onTapped: if (trayButton.modelData.hasMenu)
                                        trayMenu.open()
                                }
                                TapHandler {
                                    acceptedButtons: Qt.MiddleButton
                                    onTapped: trayButton.modelData.secondaryActivate()
                                }
                                WheelHandler {
                                    onWheel: event => {
                                        trayButton.modelData.scroll(event.angleDelta.y || event.angleDelta.x, event.angleDelta.y === 0);
                                        event.accepted = true;
                                    }
                                }
                                Keys.onPressed: event => {
                                    if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && event.modifiers & Qt.ShiftModifier)) {
                                        if (modelData.hasMenu)
                                            trayMenu.open();
                                        event.accepted = true;
                                    }
                                }
                            }
                        }
                    }
                }
                RailButton {
                    id: trayToggle
                    anchors.bottom: parent.bottom
                    implicitHeight: notificationsButton.implicitHeight
                    checked: bar.trayExpanded
                    enabled: SystemTray.items.values.length > 0
                    description: (bar.trayExpanded ? "Fold" : "Show") + " system tray · " + SystemTray.items.values.length + " items"
                    onClicked: bar.trayExpanded = !bar.trayExpanded
                    contentItem: Item {
                        MaterialIcon {
                            anchors.centerIn: parent
                            name: "expand_less"
                            tint: trayToggle.checked ? Theme.textOnSecondaryContainer : Theme.textOnSurface
                            rotation: bar.trayExpanded ? 180 : 0
                            Behavior on rotation {
                                enabled: !Theme.reducedMotion
                                SpringAnimation {
                                    spring: 3.2
                                    damping: 0.13576
                                    mass: 0.25
                                    epsilon: 0.05
                                }
                            }
                        }
                    }
                }
            }

            RailButton {
                id: clockButton
                implicitHeight: 88
                anchors.verticalCenter: parent.verticalCenter
                checked: shell.panel === "calendar" && shell.panelScreen === bar.screen
                description: Qt.formatDateTime(clock.date, "dddd, d MMMM yyyy, HH:mm") + ". Open calendar"
                onClicked: shell.togglePanel("calendar", bar.screen, clockButton)
                contentItem: Text {
                    text: Qt.formatDateTime(clock.date, "HH\nmm")
                    color: clockButton.checked ? Theme.textOnSecondaryContainer : Theme.textOnSurface
                    font.family: Theme.fontFamily
                    font.styleName: "Bold Rounded"
                    font.pixelSize: 27
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
            RailButton {
                id: notificationsButton
                anchors.bottom: clockButton.top
                anchors.bottomMargin: 8
                glyph: shell.notifications.dnd ? "󰂛" : "󰂚"
                centerGlyphInk: shell.notifications.dnd
                checked: shell.panel === "notifications" && shell.panelScreen === bar.screen
                description: (shell.notifications.dnd ? "Do not disturb. " : "") + shell.notifications.count + " notifications"
                onClicked: shell.togglePanel("notifications", bar.screen, notificationsButton)
                Rectangle {
                    visible: shell.notifications.count > 0
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: 10
                    anchors.verticalCenterOffset: -10
                    width: Math.max(18, countLabel.implicitWidth + 8)
                    height: 18
                    radius: 9
                    color: Theme.surfaceContainerHighest
                    Text {
                        id: countLabel
                        anchors.centerIn: parent
                        text: shell.notifications.count > 9 ? "9+" : shell.notifications.count
                        color: Theme.textOnSurface
                        font.family: Theme.fontFamily
                        font.styleName: "Rounded"
                        font.pixelSize: 10
                        font.bold: true
                    }
                }
            }

            Column {
                id: lower
                width: parent.width
                anchors.bottom: parent.bottom
                spacing: 4

                RailButton {
                    id: microphoneButton
                    glyph: bar.inputAudio?.muted ? "󰍭" : "󰍬"
                    checked: bar.inputAudio !== null && !bar.inputAudio.muted
                    description: bar.inputAudio ? "Microphone" + (bar.inputAudio.muted ? ", muted" : "") + ". Open input controls; right click to mute" : "Microphone controls; no input device available"
                    onClicked: shell.togglePanel("microphone", bar.screen, microphoneButton)
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: if (bar.inputAudio)
                            bar.inputAudio.muted = !bar.inputAudio.muted
                    }
                }

                RailButton {
                    id: volumeButton
                    glyph: !bar.outputAudio || bar.outputAudio.muted ? "󰖁" : bar.outputAudio.volume < 0.5 ? "󰕿" : "󰕾"
                    description: bar.outputAudio ? "Volume " + Math.round(bar.outputAudio.volume * 100) + "%" + (bar.outputAudio.muted ? ", muted" : "") + ". Open sound controls; scroll to adjust; right click or M to mute" : "Sound controls; no audio output"
                    checked: shell.panel === "sound" && shell.panelTrigger === volumeButton
                    onClicked: shell.togglePanel("sound", bar.screen, volumeButton)
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: if (bar.outputAudio)
                            bar.outputAudio.muted = !bar.outputAudio.muted
                    }
                    WheelHandler {
                        onWheel: event => {
                            bar.changeVolume(event.angleDelta.y / 120 * 0.05);
                            event.accepted = true;
                        }
                    }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_M && bar.outputAudio) {
                            bar.outputAudio.muted = !bar.outputAudio.muted;
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
                            bar.changeVolume(event.key === Qt.Key_Up ? 0.05 : -0.05);
                            event.accepted = true;
                        }
                    }
                }

                RailButton {
                    id: networkButton
                    glyph: !bar.networkDevice ? "󰖪" : Networking.connectivity === NetworkConnectivity.Portal || Networking.connectivity === NetworkConnectivity.Limited ? "󰖫" : bar.networkDevice.type === DeviceType.Wired ? "󰈀" : "󰖩"
                    centerGlyphInk: glyph === "󰈀"
                    description: (bar.networkDevice ? bar.networkDevice.name + ": " + NetworkConnectivity.toString(Networking.connectivity) : "Network disconnected") + ". Open network controls"
                    onClicked: shell.togglePanel("network", bar.screen, networkButton)
                }

                RailButton {
                    id: bluetoothButton
                    glyph: !bar.bluetoothEnabled ? "󰂲" : bar.bluetoothConnections > 0 ? "󰂱" : "󰂯"
                    checked: bar.bluetoothConnections > 0
                    description: (bar.bluetoothEnabled ? "Bluetooth on, " + bar.bluetoothConnections + " connected devices" : "Bluetooth off") + ". Open Bluetooth controls"
                    onClicked: shell.togglePanel("bluetooth", bar.screen, bluetoothButton)
                }
            }
        }
    }
}
