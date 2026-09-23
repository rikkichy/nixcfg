import QtQuick
import QtQuick.Controls
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
        contentItem: MenuStyle.RowContent {
            button: option
            selected: option.selected
        }
        background: MenuStyle.RowBackground {
            button: option
            selected: option.selected
            first: option.index === 0
            last: option.index === control.count - 1
            keyboardFocus: control.visualFocus
        }
    }
    popup: Popup {
        y: control.height + 4
        width: control.width
        height: Math.min(list.contentHeight + topPadding + bottomPadding, 280, Math.max(0, control.Window.height - 16))
        padding: 8
        margins: 8
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
        background: MenuStyle.Surface {}
        enter: MenuStyle.Enter {}
        exit: MenuStyle.Exit {}
    }
}
