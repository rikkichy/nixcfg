import QtQuick
import QtQuick.Controls
import QtQuick.Window

Slider {
    id: control
    property real handleLength: 52
    property real endRadius: Theme.radiusSmall
    property color inactiveColor: Theme.secondaryContainer
    readonly property bool firstActive: horizontal && !mirrored
    readonly property Item inactiveTrack: firstActive ? afterTrack : beforeTrack
    property bool initialized: false
    property bool dragging: false
    readonly property bool motionAllowed: initialized && visible && Window.window !== null && Window.window.visible && !Theme.reducedMotion && !dragging
    readonly property real targetPosition: visualPosition
    property real displayedPosition: 0
    property real thickness: pressed ? 2 : 4
    focusPolicy: Qt.StrongFocus
    Component.onCompleted: {
        displayedPosition = targetPosition;
        initialized = true;
    }
    onTargetPositionChanged: updatePosition()
    onMotionAllowedChanged: updatePosition()

    function updatePosition() {
        if (!initialized)
            return;
        movement.stop();
        if (motionAllowed) {
            movement.from = displayedPosition;
            movement.to = targetPosition;
            movement.start();
        } else {
            displayedPosition = targetPosition;
        }
    }
    NumberAnimation {
        id: movement
        target: control
        property: "displayedPosition"
        duration: 150
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.31, 0.94, 0.34, 1, 1, 1]
    }
    Behavior on thickness {
        enabled: control.initialized && control.visible && !Theme.reducedMotion
        NumberAnimation {
            duration: 100
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.2, 0, 0, 1, 1, 1]
        }
    }
    // Passive observation preserves native Slider mouse, touch and keyboard input.
    PointHandler {
        target: null
        onActiveChanged: control.dragging = false
        onPointChanged: {
            const distance = control.horizontal ? Math.abs(point.position.x - point.pressPosition.x) : Math.abs(point.position.y - point.pressPosition.y);
            if (active && distance >= Qt.styleHints.startDragDistance)
                control.dragging = true;
        }
    }
    background: Item {
        x: control.horizontal ? control.leftPadding : (control.width - width) / 2
        y: control.vertical ? control.topPadding : (control.height - height) / 2
        width: control.horizontal ? control.availableWidth : 40
        height: control.vertical ? control.availableHeight : 40
        readonly property real extent: control.horizontal ? width : height
        readonly property real split: control.displayedPosition * (extent - 4)
        Segment {
            id: beforeTrack
            index: 0
        }
        Segment {
            id: afterTrack
            index: 1
        }
    }
    component Segment: Rectangle {
        required property int index
        readonly property bool activeSegment: (index === 0) === control.firstActive
        readonly property real offset: index === 0 ? 0 : Math.min(parent.extent, parent.split + 4 + 6)
        readonly property real length: Math.max(0, index === 0 ? parent.split - 6 : parent.extent - offset)
        x: control.horizontal ? offset : 0
        y: control.vertical ? offset : 0
        width: control.horizontal ? length : parent.width
        height: control.vertical ? length : parent.height
        radius: 2
        topLeftRadius: index === 0 ? control.endRadius : 2
        topRightRadius: (control.vertical ? index === 0 : index === 1) ? control.endRadius : 2
        bottomLeftRadius: (control.vertical ? index === 1 : index === 0) ? control.endRadius : 2
        bottomRightRadius: index === 1 ? control.endRadius : 2
        color: control.enabled ? (activeSegment ? Theme.primary : control.inactiveColor) : Theme.textOnSurface
        opacity: control.enabled ? 1 : activeSegment ? 0.38 : 0.12
    }
    // Keep the positioning/hit-test geometry fixed while the visible ink compresses.
    handle: Item {
        x: control.horizontal ? control.leftPadding + control.displayedPosition * (control.availableWidth - width) : control.leftPadding + (control.availableWidth - width) / 2
        y: control.vertical ? control.topPadding + control.displayedPosition * (control.availableHeight - height) : control.topPadding + (control.availableHeight - height) / 2
        width: control.horizontal ? 4 : control.handleLength
        height: control.vertical ? 4 : control.handleLength
        Rectangle {
            anchors.centerIn: parent
            width: control.horizontal ? control.thickness : parent.width
            height: control.vertical ? control.thickness : parent.height
            radius: control.thickness / 2
            color: control.enabled ? Theme.primary : Theme.textOnSurface
            opacity: control.enabled ? 1 : 0.38
            border.width: control.visualFocus ? (control.vertical ? 1 : 2) : 0
            border.color: Theme.textOnSurface
        }
    }
}
