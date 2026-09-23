import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

ColumnLayout {
    id: calendar
    property date displayed: new Date()
    spacing: 16
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }
    Text {
        text: Qt.formatDateTime(clock.date, "dddd, d MMMM")
        color: Theme.tertiary
        font.family: Theme.fontFamily
        font.pixelSize: 20
    }
    RowLayout {
        Layout.fillWidth: true
        ExpressiveButton {
            contentItem: Item {
                MaterialIcon { anchors.centerIn: parent; name: "chevron_left"; tint: Theme.textOnSurface }
            }
            description: "Previous month"
            onClicked: calendar.displayed = new Date(calendar.displayed.getFullYear(), calendar.displayed.getMonth() - 1, 1)
        }
        Text {
            Layout.fillWidth: true
            text: Qt.formatDate(calendar.displayed, "MMMM yyyy")
            horizontalAlignment: Text.AlignHCenter
            color: Theme.textOnSurface
            font.family: Theme.fontFamily
            font.pixelSize: 22
            font.weight: Font.DemiBold
        }
        ExpressiveButton {
            contentItem: Item {
                MaterialIcon { anchors.centerIn: parent; name: "chevron_right"; tint: Theme.textOnSurface }
            }
            description: "Next month"
            onClicked: calendar.displayed = new Date(calendar.displayed.getFullYear(), calendar.displayed.getMonth() + 1, 1)
        }
    }
    DayOfWeekRow {
        Layout.fillWidth: true
        locale: grid.locale
        delegate: Text {
            required property string shortName
            text: shortName
            color: Theme.textOnSurfaceVariant
            horizontalAlignment: Text.AlignHCenter
            font.family: Theme.fontFamily
            font.pixelSize: 14
        }
    }
    MonthGrid {
        id: grid
        Layout.fillWidth: true
        Layout.preferredHeight: 288
        month: calendar.displayed.getMonth()
        year: calendar.displayed.getFullYear()
        locale: Qt.locale()
        delegate: Rectangle {
            required property var model
            radius: model.today ? 16 : 24
            color: model.today ? Theme.tertiaryContainer : "transparent"
            opacity: model.month === grid.month ? 1 : 0.38
            Text {
                anchors.centerIn: parent
                text: parent.model.day
                color: parent.model.today ? Theme.textOnTertiaryContainer : Theme.textOnSurface
                font.family: Theme.fontFamily
                font.pixelSize: 17
                font.bold: parent.model.today
            }
        }
    }
    ExpressiveButton {
        Layout.fillWidth: true
        text: "Today"
        onClicked: calendar.displayed = new Date()
    }
}
