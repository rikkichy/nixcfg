import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import QtQuick.Window

ComboBox {
    id: control
    implicitHeight: 56
    padding: 16
    spacing: 12
    leftPadding: mirrored ? padding + 24 + spacing : padding
    rightPadding: mirrored ? padding : padding + 24 + spacing
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    font.family: Theme.fontFamily
    font.pixelSize: 16
    font.styleName: "Rounded"

    contentItem: Text {
        text: control.displayText
        font: control.font
        color: Theme.textOnSurface
        opacity: control.enabled ? 1 : 0.38
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    indicator: MaterialIcon {
        width: 24
        height: 24
        x: control.mirrored ? control.padding : control.width - width - control.padding
        y: (control.height - height) / 2
        rotation: control.popup.visible ? 180 : 0
        opacity: control.enabled ? 1 : 0.38
        name: "arrow_drop_down"
        tint: Theme.textOnSurfaceVariant
        Behavior on rotation {
            NumberAnimation {
                duration: Theme.reducedMotion ? 0 : 150
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.31, 0.94, 0.34, 1, 1, 1]
            }
        }
    }
    background: Rectangle {
        radius: height / 2
        color: Theme.surfaceContainerHighest
        border.width: control.visualFocus ? 2 : 0
        border.color: Theme.primary
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Theme.textOnSurface
            opacity: control.down ? 0.1 : control.hovered ? 0.08 : 0
        }
    }
    delegate: ItemDelegate {
        id: option
        required property int index
        readonly property bool selected: control.currentIndex === index
        width: ListView.view.width
        height: 48
        padding: 12
        text: control.textAt(index)
        font: control.font
        highlighted: control.highlightedIndex === index
        hoverEnabled: true
        Accessible.name: text
        Accessible.role: Accessible.ListItem
        Accessible.selected: selected
        contentItem: Item {
            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: control.mirrored ? 0 : option.selected ? 32 : 0
                anchors.rightMargin: control.mirrored && option.selected ? 32 : 0
                anchors.verticalCenter: parent.verticalCenter
                text: option.text
                font: option.font
                color: option.selected ? Theme.textOnTertiaryContainer : Theme.textOnSurface
                elide: Text.ElideRight
            }
            Shape {
                width: 20
                height: 20
                x: control.mirrored ? parent.width - width : 0
                anchors.verticalCenter: parent.verticalCenter
                visible: option.selected
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Theme.textOnTertiaryContainer
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
        background: Rectangle {
            radius: option.selected ? 16 : 4
            topLeftRadius: option.index === 0 ? 20 : radius
            topRightRadius: topLeftRadius
            bottomLeftRadius: option.index === control.count - 1 ? 20 : radius
            bottomRightRadius: bottomLeftRadius
            color: option.selected ? Theme.tertiaryContainer : option.highlighted || option.hovered ? Theme.surfaceContainerHighest : "transparent"
            border.width: option.highlighted ? 1 : 0
            border.color: option.selected ? Theme.textOnTertiaryContainer : Theme.outline
        }
    }
    popup: Popup {
        y: control.height + 4
        width: control.width
        height: Math.min(list.contentHeight + topPadding + bottomPadding, 280, Math.max(0, control.Window.height - 16))
        padding: 8
        margins: 8
        // Stay inside the existing layer surface and its Hyprland focus grab.
        popupType: Popup.Item
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
        contentItem: ListView {
            id: list
            clip: true
            spacing: 2
            model: control.delegateModel
            currentIndex: control.highlightedIndex
            highlightMoveDuration: 0
            boundsBehavior: Flickable.StopAtBounds
            ScrollIndicator.vertical: ScrollIndicator {}
        }
        background: Rectangle {
            radius: 28
            color: Theme.surfaceContainer
            border.width: 1
            border.color: Theme.outlineVariant
        }
        enter: Transition {
            NumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                duration: Theme.reducedMotion ? 0 : 150
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.31, 0.94, 0.34, 1, 1, 1]
            }
        }
        exit: Transition {
            NumberAnimation {
                property: "opacity"
                to: 0
                duration: Theme.reducedMotion ? 0 : 100
            }
        }
    }
}
