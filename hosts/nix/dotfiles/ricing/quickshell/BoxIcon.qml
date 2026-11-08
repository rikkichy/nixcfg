import QtQuick
import QtQuick.Effects

Item {
    id: icon
    required property string name
    property color tint: Theme.primary
    width: 24
    height: 24
    implicitWidth: image.implicitWidth
    implicitHeight: image.implicitHeight

    // A hidden, stretched Image lets MultiEffect sample its texture directly instead of rendering a layer.
    Image {
        id: image
        anchors.fill: parent
        visible: false
        source: icon.name ? Qt.resolvedUrl("icons/" + icon.name + ".svg") : ""
        sourceSize.width: icon.width
        sourceSize.height: icon.height
    }
    MultiEffect {
        anchors.fill: parent
        visible: image.status === Image.Ready
        source: image
        colorization: 1
        colorizationColor: icon.tint
    }
}
