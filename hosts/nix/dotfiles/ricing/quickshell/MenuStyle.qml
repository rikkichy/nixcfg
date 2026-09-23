import QtQuick
import QtQuick.Templates as T
import QtQuick.Shapes

QtObject {
    component Surface: Rectangle {
        radius: 28
        color: Theme.surfaceContainer
        border.width: 1
        border.color: Theme.outlineVariant
    }
    component RowBackground: Rectangle {
        required property T.AbstractButton button
        property bool selected: false
        property bool first: false
        property bool last: false
        property bool keyboardFocus: button.visualFocus
        radius: selected || button.highlighted || button.hovered ? 16 : 4
        topLeftRadius: first ? 20 : radius
        topRightRadius: topLeftRadius
        bottomLeftRadius: last ? 20 : radius
        bottomRightRadius: bottomLeftRadius
        color: button.hovered || button.highlighted && !selected ? Theme.surfaceContainerHighest : selected ? Theme.surfaceContainerHigh : "transparent"
        border.width: keyboardFocus && button.highlighted ? 1 : 0
        border.color: Theme.outline
        opacity: button.enabled ? 1 : 0.38
    }
    component RowContent: Item {
        required property T.AbstractButton button
        property bool selected: false
        property bool partial: false
        property bool radio: false
        property url iconSource
        readonly property bool leading: selected || partial || iconSource.toString() !== ""
        implicitHeight: 24
        implicitWidth: label.implicitWidth + (leading ? 32 : 0)
        opacity: button.enabled ? 1 : 0.38
        Text {
            id: label
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: !button.mirrored && parent.leading ? 32 : 0
            anchors.rightMargin: button.mirrored && parent.leading ? 32 : 0
            anchors.verticalCenter: parent.verticalCenter
            text: button.text
            font: button.font
            color: Theme.textOnSurface
            elide: Text.ElideRight
        }
        Item {
            width: 20
            height: 20
            x: button.mirrored ? parent.width - width : 0
            anchors.verticalCenter: parent.verticalCenter
            Image {
                anchors.fill: parent
                source: iconSource
                visible: !selected && !partial
                sourceSize.width: 20
                sourceSize.height: 20
                fillMode: Image.PreserveAspectFit
            }
            Rectangle {
                anchors.centerIn: parent
                width: partial ? 12 : 8
                height: partial ? 2 : 8
                radius: partial ? 1 : 4
                color: Theme.textOnSurface
                visible: partial || selected && radio
            }
            Shape {
                anchors.fill: parent
                visible: selected && !partial && !radio
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Theme.textOnSurface
                    strokeWidth: 2
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    startX: 4
                    startY: 10
                    PathLine {
                        x: 8
                        y: 14
                    }
                    PathLine {
                        x: 16
                        y: 6
                    }
                }
            }
        }
    }
    component Enter: Transition {
        NumberAnimation {
            property: "scale"
            from: 0.94
            to: 1
            duration: Theme.reducedMotion ? 0 : 150
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.31, 0.94, 0.34, 1, 1, 1]
        }
        NumberAnimation {
            property: "opacity"
            from: 0
            to: 1
            duration: Theme.reducedMotion ? 0 : 150
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.31, 0.94, 0.34, 1, 1, 1]
        }
    }
    component Exit: Transition {
        NumberAnimation {
            property: "scale"
            to: 0.98
            duration: Theme.reducedMotion ? 0 : 100
        }
        NumberAnimation {
            property: "opacity"
            to: 0
            duration: Theme.reducedMotion ? 0 : 100
        }
    }
}
