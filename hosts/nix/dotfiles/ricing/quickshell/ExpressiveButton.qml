import QtQuick
import QtQuick.Controls

AbstractButton {
    id: control
    property bool prominent: false
    property string description: text
    implicitWidth: Math.max(48, label.implicitWidth + 32)
    implicitHeight: 48
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    Accessible.name: description || text
    opacity: enabled ? 1 : 0.38
    scale: down ? 0.96 : 1
    Behavior on scale { enabled: !Theme.reducedMotion; SpringAnimation { spring: 4; damping: 0.65; epsilon: 0.001 } }
    background: Rectangle {
        radius: control.down ? Theme.radiusSmall : (control.checked ? Theme.radiusMedium : height / 2)
        color: control.prominent ? Theme.primary : control.checked ? Theme.secondaryContainer :
               control.hovered ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
        border.width: control.visualFocus ? 2 : 0
        border.color: Theme.primary
        Behavior on radius { enabled: !Theme.reducedMotion; SpringAnimation { spring: 4; damping: 0.8; epsilon: 0.05 } }
        Behavior on color { ColorAnimation { duration: Theme.motionDuration } }
    }
    contentItem: Text {
        id: label
        text: control.text
        color: control.prominent ? Theme.textOnPrimary : control.checked ? Theme.textOnSecondaryContainer : Theme.textOnSurface
        font.family: Theme.fontFamily
        font.styleName: "Bold Rounded"
        font.pixelSize: 15
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        textFormat: Text.PlainText
    }
}
