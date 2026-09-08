import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  function open(payloadJson) {
    root.opened = true
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "community.command-center")
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "community-command-center"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Rectangle {
      width: Math.min(Style.space(300), panel.width - Style.gapsOut * 2)
      height: Math.min(Style.space(120), panel.height - Style.gapsOut * 2)
      anchors.centerIn: parent
      color: Color.menu.background
      border.color: Color.menu.border
      border.width: Math.max(1, Style.space(1))
      radius: Style.cornerRadius

      MouseArea { anchors.fill: parent; onClicked: {} }

      Text {
        anchors.centerIn: parent
        text: "Command Center"
        color: Color.menu.text
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.title
      }

      Keys.onEscapePressed: root.dismiss()
      focus: true
    }
  }
}
