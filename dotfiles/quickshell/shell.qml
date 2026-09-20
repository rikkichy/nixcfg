import QtQuick
import QtQuick.Controls
import QtQuick.Window
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
    property real originRadius: 24
    property color originColor: Theme.surfaceContainerHigh
    property bool barsVisible: true
    property alias notifications: notificationCenter

    onPanelWindowChanged: if (!panelWindow && popover)
        closePanel()
    onPanelTriggerChanged: if (!panelTrigger && popover)
        closePanel()

    function togglePanel(name, targetScreen, trigger) {
        if (!["controls", "notifications", "calendar"].includes(name))
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

        // A different trigger starts a new container transform; reversing the same one retains velocity.
        const newOrigin = panelTrigger !== button || presentedPanel !== name;
        const needsFirstFrame = newOrigin || !popover.visible;
        if (newOrigin) {
            popover.resetting = true;
            popover.expansion = 0;
            popover.contentPresence = 0;
        }
        origin = button.mapToItem(rail.contentItem, 0, 0, button.width, button.height);
        originRadius = Math.min(button.background.radius, origin.width / 2, origin.height / 2);
        originColor = button.background.color;
        panelScreen = screen;
        panelWindow = rail;
        panelTrigger = button;
        presentedPanel = name;
        popover.waitingForFrame = needsFirstFrame && !Theme.reducedMotion;
        panel = name;
        popover.resetting = false;
        if (!popover.waitingForFrame)
            popover.startOpening();
        Qt.callLater(() => {
            if (panel !== "")
                sheet.forceActiveFocus();
        });
    }

    function closePanel() {
        popover.waitingForFrame = false;
        panel = "";
        popover.expansion = 0;
        popover.contentPresence = 0;
    }

    NotificationCenter {
        id: notificationCenter
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // Quickshell 0.3.1 does not refresh monitor specialWorkspace for these events.
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
        active: desktop.panel !== "" && popover.visible
        windows: desktop.panelWindow ? [popover, desktop.panelWindow] : [popover]
        onCleared: desktop.closePanel()
    }
    PanelWindow {
        id: popover
        property bool resetting: false
        property bool waitingForFrame: false
        property real expansion: 0
        property real contentPresence: 0
        readonly property real progress: Math.max(0, expansion)
        readonly property real ink: Math.max(0, Math.min(1, contentPresence))
        readonly property real screenWidth: desktop.panelScreen ? desktop.panelScreen.width : 1920
        readonly property real screenHeight: desktop.panelScreen ? desktop.panelScreen.height : 1080
        readonly property real targetWidth: Math.max(1, Math.min(desktop.presentedPanel === "calendar" ? 400 : 420, screenWidth - 104))
        readonly property real contentHeight: desktop.presentedPanel === "calendar" ? calendar.implicitHeight : desktop.presentedPanel === "notifications" ? inbox.implicitHeight : controls.implicitHeight
        readonly property real targetHeight: Math.max(1, Math.min(contentHeight + header.implicitHeight + 56, screenHeight - 24))
        readonly property real targetX: Math.max(12, Math.min((desktop.panelWindow ? desktop.panelWindow.width : 80) + 8, screenWidth - targetWidth - 12))
        readonly property real targetY: Math.max(12, Math.min(desktop.origin.y + desktop.origin.height / 2 - targetHeight / 2, screenHeight - targetHeight - 12))
        // Allocate the union of the trigger and destination once; never resize the Wayland surface per frame.
        readonly property real surfaceX: Math.max(0, Math.floor(Math.min(desktop.origin.x, targetX)))
        readonly property real surfaceY: Math.max(0, Math.floor(Math.min(desktop.origin.y, targetY)))
        readonly property real surfaceRight: Math.min(screenWidth, Math.ceil(Math.max(desktop.origin.x + desktop.origin.width, targetX + targetWidth)))
        readonly property real surfaceBottom: Math.min(screenHeight, Math.ceil(Math.max(desktop.origin.y + desktop.origin.height, targetY + targetHeight)))

        function startOpening() {
            if (desktop.panel === "")
                return;
            waitingForFrame = false;
            expansion = 1;
            contentPresence = 1;
        }

        Connections {
            target: sheet.Window.window
            enabled: popover.waitingForFrame
            function onFrameSwapped() {
                // Present the trigger-sized surface before advancing the opening spring.
                if (popover.waitingForFrame)
                    popover.startOpening();
            }
        }

        // M3 default spatial spring; opacity uses the critically damped effects spring.
        Behavior on expansion {
            enabled: !Theme.reducedMotion && !popover.resetting
            SpringAnimation {
                spring: 3.04
                damping: 0.2495
                mass: 0.5
                epsilon: 0.001
            }
        }
        Behavior on contentPresence {
            enabled: !Theme.reducedMotion && !popover.resetting
            SpringAnimation {
                spring: 3.2
                damping: 0.16
                mass: 0.125
                epsilon: 0.001
            }
        }
        visible: desktop.panelWindow !== null && (desktop.panel !== "" || expansion > 0.001)
        screen: desktop.panelScreen
        anchors {
            top: true
            left: true
        }
        implicitWidth: Math.max(1, surfaceRight - surfaceX)
        implicitHeight: Math.max(1, surfaceBottom - surfaceY)
        margins.left: surfaceX
        margins.top: surfaceY
        mask: Region {
            item: sheet
            radius: Math.round(sheet.radius)
        }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "expressive-panel"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: desktop.panel !== "" ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle {
            id: sheet
            x: desktop.origin.x + (popover.targetX - desktop.origin.x) * popover.progress - popover.surfaceX
            y: desktop.origin.y + (popover.targetY - desktop.origin.y) * popover.progress - popover.surfaceY
            width: Math.max(1, desktop.origin.width + (popover.targetWidth - desktop.origin.width) * popover.progress)
            height: Math.max(1, desktop.origin.height + (popover.targetHeight - desktop.origin.height) * popover.progress)
            clip: true
            radius: desktop.originRadius + (Theme.radiusLarge - desktop.originRadius) * Math.min(1, popover.progress)
            color: Qt.rgba(desktop.originColor.r + (Theme.surfaceContainer.r - desktop.originColor.r) * popover.ink, desktop.originColor.g + (Theme.surfaceContainer.g - desktop.originColor.g) * popover.ink, desktop.originColor.b + (Theme.surfaceContainer.b - desktop.originColor.b) * popover.ink, 1)
            border.width: 1
            border.color: Theme.outlineVariant
            focus: true
            Keys.onEscapePressed: desktop.closePanel()
            ColumnLayout {
                // Keep text laid out at its final size while the surface reveals it.
                x: 20
                y: 20
                width: Math.max(1, popover.targetWidth - 40)
                height: Math.max(1, popover.targetHeight - 40)
                spacing: 16
                opacity: popover.ink
                enabled: desktop.panel !== ""
                RowLayout {
                    id: header
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: desktop.presentedPanel === "controls" ? "Quick settings" : desktop.presentedPanel === "calendar" ? "Calendar" : "Inbox"
                        color: Theme.textOnSurface
                        font.family: Theme.fontFamily
                        font.styleName: "Bold Rounded"
                        font.pixelSize: 28
                        font.weight: Font.Bold
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
                    currentIndex: desktop.presentedPanel === "controls" ? 0 : desktop.presentedPanel === "notifications" ? 1 : 2
                    ControlCenter {
                        id: controls
                        shell: desktop
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
