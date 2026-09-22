import QtQuick
import QtQuick.Effects

Image {
    id: icon
    required property string name
    property color tint: Theme.primary
    width: 24
    height: 24
    source: name ? Qt.resolvedUrl("icons/" + name + ".svg") : ""
    sourceSize.width: width
    sourceSize.height: height
    fillMode: Image.PreserveAspectFit
    layer.enabled: true
    layer.effect: MultiEffect {
        colorization: 1
        colorizationColor: icon.tint
    }
}
