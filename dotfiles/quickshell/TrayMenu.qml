import QtQuick
import QtQuick.Controls
import QtQml.Models
import Quickshell

Menu {
    id: root
    property QsMenuHandle menuHandle
    property QsMenuEntry sourceEntry
    title: sourceEntry ? sourceEntry.text : ""
    enabled: !sourceEntry || sourceEntry.enabled
    width: 288
    height: Math.min(480, contentItem.implicitHeight + topPadding + bottomPadding)
    padding: 8
    margins: 8
    overlap: 4
    popupType: Popup.Window
    font.family: Theme.fontFamily
    font.styleName: "Rounded"
    font.pixelSize: 16
    background: MenuStyle.Surface {}
    enter: MenuStyle.Enter {}
    exit: MenuStyle.Exit {}
    onMenuHandleChanged: {
        if (visible)
            opener.menu = menuHandle;
        if (!menuHandle)
            close();
    }
    onAboutToShow: opener.menu = menuHandle
    onClosed: Qt.callLater(() => {
        if (!visible)
            opener.menu = null;
    })

    QsMenuOpener {
        id: opener
    }
    component Option: MenuItem {
        id: option
        height: 48
        padding: 12
        rightPadding: subMenu ? 40 : 12
        leftPadding: 12
        hoverEnabled: true
        indicator: null
        arrow: MaterialIcon {
            name: "chevron_right"
            tint: Theme.textOnSurface
            visible: option.subMenu !== null
            x: option.width - width - 12
            y: (option.height - height) / 2
        }
        contentItem: MenuStyle.RowContent {
            button: option
            selected: option.checked
            iconSource: option.icon.source
        }
        background: MenuStyle.RowBackground {
            button: option
            selected: option.checked
            first: option === root.itemAt(0)
            last: option === root.itemAt(root.count - 1)
        }
    }
    delegate: Option {}
    contentItem: ListView {
        implicitHeight: contentHeight
        model: root.contentModel
        currentIndex: root.currentIndex
        spacing: 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 0
        ScrollIndicator.vertical: ScrollIndicator {}
    }
    Component {
        id: entryFactory
        Option {
            id: action
            readonly property var entry: modelData
            text: entry.text
            enabled: entry.enabled && !entry.isSeparator
            height: entry.isSeparator ? 10 : 48
            checkable: entry.buttonType !== QsMenuButtonType.None
            checked: entry.checkState !== Qt.Unchecked
            onTriggered: entry.triggered()
            contentItem: MenuStyle.RowContent {
                visible: !action.entry.isSeparator
                button: action
                selected: action.checked
                partial: action.entry.checkState === Qt.PartiallyChecked
                radio: action.entry.buttonType === QsMenuButtonType.RadioButton
                iconSource: action.entry.icon
            }
            background: Item {
                MenuStyle.RowBackground {
                    anchors.fill: parent
                    visible: !action.entry.isSeparator
                    button: action
                    selected: action.checked
                    first: action === root.itemAt(0)
                    last: action === root.itemAt(root.count - 1)
                }
                Rectangle {
                    visible: action.entry.isSeparator
                    anchors.verticalCenter: parent.verticalCenter
                    x: 12
                    width: parent.width - 24
                    height: 1
                    color: Theme.outlineVariant
                }
            }
        }
    }
    Instantiator {
        model: opener.children
        delegate: Loader {
            id: loader
            required property var modelData
            required property int index
            width: root.availableWidth
            height: modelData.isSeparator ? 10 : 48
            property bool insertedAsMenu: false
            function remove() {
                for (let i = 0; i < root.count; ++i) {
                    if ((insertedAsMenu ? root.menuAt(i) : root.itemAt(i)) !== item)
                        continue;
                    if (insertedAsMenu)
                        root.takeMenu(i);
                    else
                        root.takeItem(i);
                    break;
                }
            }
            function loadEntry() {
                remove();
                source = "";
                sourceComponent = null;
                if (modelData.hasChildren)
                    setSource(Qt.resolvedUrl("TrayMenu.qml"), {
                        menuHandle: modelData,
                        sourceEntry: modelData
                    });
                else
                    sourceComponent = entryFactory;
            }
            Component.onCompleted: loadEntry()
            onLoaded: {
                insertedAsMenu = modelData.hasChildren;
                if (insertedAsMenu)
                    root.insertMenu(index, item);
                else
                    root.insertItem(index, item);
            }
            Connections {
                target: loader.modelData
                function onHasChildrenChanged() {
                    loader.loadEntry();
                }
            }
        }
        onObjectRemoved: (index, object) => object.remove()
    }
}
