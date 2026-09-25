import QtQuick
import QtQuick.Controls
import qs.Commons
import "../presentation/Formatters.js" as Formatters

ScrollView {
  id: root
  property var result: null
  property bool ready: result && result.status === "success" && result.data
  Column { width: root.availableWidth; spacing: Style.spacing.lg
    StateMessage { width: parent.width; visible: !root.ready; result: root.result }
    Repeater { visible: root.ready; model: root.ready ? [["Total", Formatters.bytes(root.result.data.total)], ["Used", Formatters.bytes(root.result.data.used) + " · " + Formatters.percent(root.result.data.used * 100 / root.result.data.total)], ["Available", Formatters.bytes(root.result.data.available)], ["Swap", root.result.data.swapConfigured === false ? "Not configured" : Formatters.bytes(root.result.data.swapUsed) + " used · " + Formatters.bytes(root.result.data.swapFree) + " free of " + Formatters.bytes(root.result.data.swapTotal)]] : []
      delegate: Row { required property var modelData; width: parent.width; spacing: Style.spacing.lg; Text { width: Style.space(100); text: modelData[0]; textFormat: Text.PlainText; color: Color.muted; font.family: Style.font.menuFamily; font.pixelSize: Style.font.body } Text { width: parent.width - Style.space(120); text: modelData[1]; textFormat: Text.PlainText; color: Color.menu.text; font.family: Style.font.menuFamily; font.pixelSize: Style.font.body; wrapMode: Text.Wrap } }
    }
    Text { visible: root.ready && root.result.completeness === "partial"; text: "Partial result: " + root.result.evidence.join(" "); textFormat: Text.PlainText; color: Color.urgent; font.family: Style.font.menuFamily; font.pixelSize: Style.font.body; wrapMode: Text.Wrap; width: parent.width }
  }
}
