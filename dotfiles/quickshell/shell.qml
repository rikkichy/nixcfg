import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

ShellRoot {
    id: desktop
    property string panel: ""
    property string presentedPanel: "calendar"
    property var panelScreen: null
    property PanelWindow panelWindow: null
    property Item panelTrigger: null
    property rect origin: Qt.rect(12, 12, 56, 48)
    property bool barsVisible: true
    property alias notifications: notificationCenter

    onPanelWindowChanged: if (!panelWindow && popover)
        closePanel()
    onPanelTriggerChanged: if (!panelTrigger && popover)
        closePanel()

    function togglePanel(name, targetScreen, trigger) {
        if (!["microphone", "sound", "network", "bluetooth", "notifications", "calendar"].includes(name))
            return;
        const screen = targetScreen || Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) || Quickshell.screens[0];
        const rail = bars.instances.find(instance => instance.screen === screen);
        if (!rail)
            return;
        const button = trigger || rail.triggerForPanel(name);
        if (panel === name && panelTrigger === button) {
            closePanel();
            return;
        }

        origin = button.mapToItem(rail.contentItem, 0, 0, button.width, button.height);
        panelScreen = screen;
        panelWindow = rail;
        panelTrigger = button;
        presentedPanel = name;
        panel = name;
        Qt.callLater(() => {
            if (panel !== "")
                sheet.forceActiveFocus();
        });
    }

    function closePanel() {
        panel = "";
    }

    NotificationCenter {
        id: notificationCenter
        shell: desktop
        osdRail: {
            if (!notificationCenter.osdScreen)
                return null;
            return bars.instances.find(rail => rail.screen === notificationCenter.osdScreen) || null;
        }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activespecial" || event.name === "activespecialv2")
                Hyprland.refreshMonitors();
        }
    }
    Variants {
        id: bars
        model: Quickshell.screens
        Bar {
            shell: desktop
        }
    }
    IpcHandler {
        target: "desktop"
        function toggle(name: string): void {
            desktop.togglePanel(name, null, null);
        }
        function close(): void {
            desktop.closePanel();
        }
        function hide(): void {
            desktop.closePanel();
            desktop.barsVisible = false;
        }
        function reveal(): void {
            desktop.barsVisible = true;
        }
        function dismissAll(): void {
            notificationCenter.dismissAll();
        }
        function dnd(): bool {
            notificationCenter.dnd = !notificationCenter.dnd;
            return notificationCenter.dnd;
        }
        function status(): string {
            return JSON.stringify({
                panel: desktop.panel,
                barsVisible: desktop.barsVisible,
                notifications: notificationCenter.count,
                dnd: notificationCenter.dnd
            });
        }
    }

    HyprlandFocusGrab {
        active: desktop.panel !== "" && popover.backingWindowVisible
        windows: [popover]
        onCleared: desktop.closePanel()
    }
    PanelWindow {
        id: popover
        readonly property real screenWidth: desktop.panelScreen ? desktop.panelScreen.width : 1920
        readonly property real screenHeight: desktop.panelScreen ? desktop.panelScreen.height : 1080
        readonly property real targetWidth: Math.max(1, Math.min(desktop.presentedPanel === "calendar" ? 400 : 420, screenWidth - 104))
        readonly property real contentHeight: desktop.presentedPanel === "calendar" ? calendar.implicitHeight : desktop.presentedPanel === "notifications" ? inbox.implicitHeight : controls.implicitHeight
        readonly property real targetHeight: Math.max(1, Math.min(contentHeight + header.implicitHeight + 56, screenHeight - 24))
        readonly property real targetX: Math.max(12, Math.min((desktop.panelWindow ? desktop.panelWindow.width : 80) + 8, screenWidth - targetWidth - 12))
        readonly property real targetY: Math.max(12, Math.min(desktop.origin.y + desktop.origin.height / 2 - targetHeight / 2, screenHeight - targetHeight - 12))
        visible: desktop.panelWindow !== null && desktop.panel !== ""
        screen: desktop.panelScreen
        anchors {
            top: true
            left: true
        }
        implicitWidth: targetWidth
        implicitHeight: targetHeight
        margins.left: targetX
        margins.top: targetY
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: Theme.reducedMotion ? "expressive-panel-static" : "expressive-panel"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: desktop.panel !== "" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        Rectangle {
            id: sheet
            anchors.fill: parent
            clip: true
            radius: Theme.radiusLarge
            color: Theme.surfaceContainer
            border.width: 1
            border.color: Theme.outlineVariant
            focus: true
            Keys.onEscapePressed: desktop.closePanel()
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 16
                RowLayout {
                    id: header
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: ({
                                microphone: "Microphone",
                                sound: "Sound",
                                network: "Internet",
                                bluetooth: "Bluetooth",
                                calendar: "Calendar",
                                notifications: "Notifications"
                            })[desktop.presentedPanel]
                        color: Theme.textOnSurface
                        font.family: Theme.fontFamily
                        font.styleName: "Bold Rounded"
                        font.pixelSize: 28
                        font.weight: Font.Bold
                    }
                    ExpressiveButton {
                        id: dndButton
                        visible: desktop.presentedPanel === "notifications"
                        implicitWidth: 48
                        description: notificationCenter.dnd ? "Turn off Do not disturb" : "Turn on Do not disturb"
                        checkable: true
                        checked: notificationCenter.dnd
                        onClicked: notificationCenter.dnd = !notificationCenter.dnd
                        background: Rectangle {
                            radius: height / 2
                            color: dndButton.checked || dndButton.hovered ? Theme.surfaceContainerHighest : "transparent"
                            border.width: dndButton.visualFocus ? 2 : 0
                            border.color: Theme.primary
                        }
                        contentItem: Item {
                            MaterialIcon {
                                anchors.centerIn: parent
                                name: notificationCenter.dnd ? "notifications_off" : "notifications_active"
                                tint: dndButton.checked ? Theme.textOnSurface : Theme.textOnSurfaceVariant
                            }
                        }
                    }
                    ExpressiveButton {
                        text: "×"
                        description: "Close panel"
                        onClicked: desktop.closePanel()
                    }
                }
                StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: desktop.presentedPanel === "notifications" ? 1 : desktop.presentedPanel === "calendar" ? 2 : 0
                    ControlCenter {
                        id: controls
                        shell: desktop
                        section: desktop.presentedPanel
                    }
                    NotificationPanel {
                        id: inbox
                        center: notificationCenter
                    }
                    ScrollView {
                        id: calendarScroll
                        contentWidth: availableWidth
                        clip: true
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        CalendarPanel {
                            id: calendar
                            width: calendarScroll.availableWidth
                        }
                    }
                }
            }
        }
    }
}
