import QtQuick
import QtQuick.Controls
import qs.Commons
import "../presentation/Formatters.js" as Formatters

ScrollView {
  id: root
  property var result: null
  property bool ready: result && (result.status === "success" || result.status === "empty") && result.data
  clip: true
  Column {
    width: root.availableWidth
    spacing: Style.spacing.md
    StateMessage { width: parent.width; visible: !root.ready; result: root.result }
    Grid {
      visible: root.ready; width: parent.width; columns: width > Style.space(360) ? 2 : 1; spacing: Style.spacing.md
      Repeater {
        model: root.ready ? [
          ["Hostname", root.result.data.hostname ? root.result.data.hostname.value : "Unavailable"],
          ["Operating system", root.result.data.os ? root.result.data.os.displayName : "Unavailable"],
          ["Kernel", root.result.data.kernel ? root.result.data.kernel.displayName : "Unavailable"],
          ["Uptime", root.result.data.uptime ? Formatters.duration(root.result.data.uptime.seconds) : "Unavailable"],
          ["CPU", root.result.data.cpu ? (root.result.data.cpu.model || "Model unavailable") : "Unavailable"],
          ["Logical CPUs", root.result.data.cpu ? String(root.result.data.cpu.logicalProcessors) : "Unavailable"],
          ["CPU utilization", root.result.data.cpu ? Formatters.percent(root.result.data.cpu.usagePercent) : "Unavailable"],
          ["RAM", root.result.data.memory ? Formatters.bytes(root.result.data.memory.total) + " total · " + Formatters.bytes(root.result.data.memory.available) + " available" : "Unavailable"],
          ["Root storage", root.result.data.rootStorage ? Formatters.bytes(root.result.data.rootStorage.used) + " used of " + Formatters.bytes(root.result.data.rootStorage.size) : "Unavailable"],
          ["Load 1 / 5 / 15", root.result.data.load ? Formatters.load(root.result.data.load.one) + " / " + Formatters.load(root.result.data.load.five) + " / " + Formatters.load(root.result.data.load.fifteen) : "Unavailable"]
        ] : []
        delegate: Rectangle { required property var modelData; width: (parent.width - Style.spacing.md) / (parent.columns); height: Style.space(48); color: "transparent"
          Column { anchors.verticalCenter: parent.verticalCenter; width: parent.width; Text { text: modelData[0]; textFormat: Text.PlainText; color: Color.muted; font.family: Style.font.menuFamily; font.pixelSize: Style.font.bodySmall } Text { text: modelData[1]; textFormat: Text.PlainText; color: Color.menu.text; font.family: Style.font.menuFamily; font.pixelSize: Style.font.body; width: parent.width; elide: Text.ElideRight } }
        }
      }
    }
    Text { visible: root.ready && root.result.completeness === "partial"; text: "Partial result: some information could not be obtained."; textFormat: Text.PlainText; color: Color.urgent; font.family: Style.font.menuFamily; font.pixelSize: Style.font.body }
  }
}
