import QtQuick 2.2
import QtQuick.Controls.Styles 1.4

import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 2.0 as PlasmaComponents

import QtQuick.Controls 1.3 as QQC

PlasmaComponents.ToolButton {
    id: keyboardButton

    property int currentIndex: -1

    font.family: config.Font || "Noto Sans"
    font.pointSize: root.height/75
    // text: instantiator.objectAt(currentIndex).shortName
    visible: menu.items.length > 1
    anchors.left: parent.left
    anchors.leftMargin:7

    style: ButtonStyle {
        label: Image {
            source: "artwork/character-set.svgz"
            fillMode: Image.PreserveAspectFit
            transform: Translate { y: 1 }
        }
        background: Rectangle {
            radius: 3
            color: keyboardButton.activeFocus ? "white" : "transparent"
            opacity: keyboardButton.activeFocus ? 0.3 : 1
        }
    }

    Component.onCompleted: currentIndex = Qt.binding(function() {return keyboard.currentLayout});

    menu: QQC.Menu {
        id: keyboardMenu
        Instantiator {
            id: instantiator
            model: keyboard.layouts
            onObjectAdded: keyboardMenu.insertItem(index, object)
            onObjectRemoved: keyboardMenu.removeItem( object )
            delegate: QQC.MenuItem {
                text: modelData.longName
                property string shortName: modelData.shortName
                onTriggered: {
                    keyboard.currentLayout = model.index
                }
            }
        }
    }
}
