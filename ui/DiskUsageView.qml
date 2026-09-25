import QtQuick
import QtQuick.Controls
import qs.Commons
import "../presentation/Formatters.js" as Formatters

ScrollView {
  id: root
  property var result: null
  property bool ready: result && result.status === "success" && result.data
  Column { width: root.availableWidth; spacing: Style.spacing.md
    StateMessage { width: parent.width; visible: !root.ready; result: root.result; emptyText: "No real mounted filesystems were observed." }
    Repeater { visible: root.ready; model: root.result.data.filesystems
      delegate: Rectangle { required property var modelData; width: parent.width; height: detail.implicitHeight + Style.spacing.xl * 2; color: Color.menu.selectedBackground; radius: Style.cornerRadius
        Column { id: detail; anchors { left: parent.left; right: parent.right; margins: Style.spacing.xl; verticalCenter: parent.verticalCenter } spacing: Style.spacing.xs
          Text { text: modelData.target + "  ·  " + modelData.fstype; textFormat: Text.PlainText; color: Color.menu.text; font.family: Style.font.menuFamily; font.pixelSize: Style.font.body }
          Text { text: modelData.source; textFormat: Text.PlainText; color: Color.muted; font.family: Style.font.menuFamily; font.pixelSize: Style.font.bodySmall; elide: Text.ElideRight; width: parent.width }
          Text { text: Formatters.bytes(modelData.used) + " used · " + Formatters.bytes(modelData.avail) + " available · " + Formatters.percent(modelData.usePercent); textFormat: Text.PlainText; color: Color.menu.text; font.family: Style.font.menuFamily; font.pixelSize: Style.font.bodySmall }
        }
      }
    }
  }
}
