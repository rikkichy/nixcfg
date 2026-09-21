import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications

Item {
    id: root
    required property var center
    implicitWidth: 440
    implicitHeight: center.count > 0 ? Math.min(480, notificationList.implicitHeight + clearAll.implicitHeight + 16) : emptyState.implicitHeight + 32

    ColumnLayout {
        anchors.fill: parent
        spacing: 16
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            ColumnLayout {
                id: emptyState
                anchors.centerIn: parent
                width: parent.width - 48
                spacing: 12
                visible: root.center.count === 0
                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    name: "notifications_none"
                    width: 64
                    height: 64
                    tint: Theme.textOnSurfaceVariant
                }
                Text {
                    text: "Clean."
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    font.family: Theme.fontFamily
                    font.styleName: "Rounded"
                    font.pixelSize: 24
                    color: Theme.textOnSurface
                }
            }
            ScrollView {
                id: history
                anchors.fill: parent
                visible: root.center.count > 0
                contentWidth: availableWidth
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                Column {
                    id: notificationList
                    width: history.availableWidth
                    spacing: 12
                    Repeater {
                        model: root.center.entries
                        delegate: Card {
                            required property var modelData
                            width: history.availableWidth
                            center: root.center
                            entry: modelData
                        }
                    }
                }
            }
        }
        ExpressiveButton {
            id: clearAll
            Layout.fillWidth: true
            text: "Clear all"
            description: "Dismiss all notifications"
            visible: root.center.count > 0
            onClicked: root.center.dismissAll()
            contentItem: RowLayout {
                spacing: 8
                Item { Layout.fillWidth: true }
                MaterialIcon { name: "done_all"; tint: Theme.textOnSurface }
                Text {
                    text: clearAll.text
                    color: Theme.textOnSurface
                    font.family: Theme.fontFamily
                    font.styleName: "Bold Rounded"
                    font.pixelSize: 15
                }
                Item { Layout.fillWidth: true }
            }
        }
    }

    component Card: Rectangle {
        id: card
        required property var center
        required property var entry
        property bool compact: false
        readonly property var notification: entry ? entry.notification : null
        readonly property bool critical: notification && notification.urgency === NotificationUrgency.Critical
        implicitHeight: cardContent.implicitHeight + 32
        radius: critical ? Theme.radiusMedium : Theme.radiusLarge
        color: critical ? Theme.tertiaryContainer : Theme.surfaceContainerHigh
        border.width: critical ? 1 : 0
        border.color: Theme.tertiary
        Accessible.role: Accessible.Grouping
        Accessible.name: notification ? notification.appName + ": " + notification.summary : "Notification"

        ColumnLayout {
            id: cardContent
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 16
            }
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Image {
                    readonly property string icon: card.notification ? card.notification.appIcon : ""
                    visible: icon !== "" && status !== Image.Error
                    source: icon === "" ? "" : icon.startsWith("/") ? "file://" + icon : icon.startsWith("file:") || icon.startsWith("image:") ? icon : Quickshell.iconPath(icon)
                    sourceSize {
                        width: 32
                        height: 32
                    }
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    fillMode: Image.PreserveAspectFit
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: card.notification ? card.notification.appName || "Notification" : ""
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.styleName: "Rounded"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        color: card.critical ? Theme.textOnTertiaryContainer : Theme.textOnSurfaceVariant
                    }
                    Text {
                        text: (card.critical ? "Important · " : "") + Qt.formatTime(card.entry.receivedAt, "hh:mm")
                        textFormat: Text.PlainText
                        font.family: Theme.fontFamily
                        font.styleName: "Rounded"
                        font.pixelSize: 12
                        color: card.critical ? Theme.textOnTertiaryContainer : Theme.textOnSurfaceVariant
                    }
                }
                ExpressiveButton {
                    implicitWidth: 48
                    text: "×"
                    description: "Dismiss " + (card.notification ? card.notification.summary : "notification")
                    onClicked: card.center.dismiss(card.entry)
                }
            }
            Text {
                Layout.fillWidth: true
                text: card.notification ? card.notification.summary : ""
                visible: text !== ""
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                font.family: Theme.fontFamily
                font.styleName: "Rounded"
                font.pixelSize: 19
                font.weight: Font.Medium
                color: card.critical ? Theme.textOnTertiaryContainer : Theme.textOnSurface
            }
            Text {
                Layout.fillWidth: true
                text: card.notification ? card.notification.body : ""
                visible: text !== ""
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                maximumLineCount: card.compact ? 5 : 2147483647
                elide: card.compact ? Text.ElideRight : Text.ElideNone
                font.family: Theme.fontFamily
                font.styleName: "Rounded"
                font.pixelSize: 14
                color: card.critical ? Theme.textOnTertiaryContainer : Theme.textOnSurfaceVariant
            }
            Image {
                Layout.fillWidth: true
                Layout.preferredHeight: card.compact ? 128 : 180
                visible: source.toString() !== "" && status !== Image.Error
                source: card.notification ? card.notification.image : ""
                sourceSize {
                    width: 768
                    height: 360
                }
                fillMode: Image.PreserveAspectFit
            }
            Flow {
                Layout.fillWidth: true
                spacing: 8
                visible: actionButtons.count > 0
                Repeater {
                    id: actionButtons
                    model: card.entry && card.entry.active && card.notification ? card.notification.actions : []
                    delegate: ExpressiveButton {
                        required property var modelData
                        width: Math.min(implicitWidth, cardContent.width)
                        text: modelData.text || (modelData.identifier === "default" ? "Open" : "Action")
                        description: text
                        prominent: modelData.identifier === "default"
                        onClicked: {
                            if (card.entry.active)
                                modelData.invoke();
                        }
                    }
                }
            }
        }
    }
}
