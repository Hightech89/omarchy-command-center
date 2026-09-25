import QtQuick
import QtQuick.Controls
import qs.Commons

ScrollView {
  id: root
  property var result: null
  property bool ready: result && result.status === "success" && result.data
  signal anotherRequested()
  Column {
    width: root.availableWidth
    spacing: Style.spacing.lg
    Button {
      width: parent.width
      text: "Ping Another Host"
      onClicked: root.anotherRequested()
    }
    StateMessage { width: parent.width; visible: !root.ready; result: root.result; loadingText: "Pinging validated target…" }
    Text { visible: root.ready; width: parent.width; text: root.result.data.replied ? "Replies received" : "Completed · no replies"; textFormat: Text.PlainText; color: root.result.data.replied ? Color.menu.text : Color.urgent; font.family: Style.font.menuFamily; font.pixelSize: Style.font.title }
    Repeater {
      visible: root.ready
      model: root.ready ? [
        ["Target", root.result.data.target],
        ["Packets", root.result.data.transmitted + " transmitted · " + root.result.data.received + " received"],
        ["Packet loss", root.result.data.packetLossPercent + "%"],
        ["Latency", root.result.data.latency ? root.result.data.latency.minimumMs + " / " + root.result.data.latency.averageMs + " / " + root.result.data.latency.maximumMs + " / " + root.result.data.latency.deviationMs + " ms (min/avg/max/mdev)" : "Unavailable without replies"]
      ] : []
      delegate: Row {
        required property var modelData
        width: parent.width
        spacing: Style.spacing.lg
        Text { width: Style.space(90); text: modelData[0]; textFormat: Text.PlainText; color: Color.muted; font.family: Style.font.menuFamily; font.pixelSize: Style.font.body }
        Text { width: parent.width - Style.space(110); text: modelData[1]; textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere; color: Color.menu.text; font.family: Style.font.menuFamily; font.pixelSize: Style.font.body }
      }
    }
    Text { visible: root.ready; text: "Source: ping · traffic sent only for this explicit request"; textFormat: Text.PlainText; color: Color.muted; font.family: Style.font.menuFamily; font.pixelSize: Style.font.bodySmall }
  }
}
