import QtQuick
import QtQuick.Controls
import qs.Commons

ScrollView {
  id: root
  property var result: null
  property bool ready: result && (result.status === "success" || result.status === "empty") && result.data
  signal anotherRequested()
  function answers(values) { return values && values.length ? values.join("\n") : "No answers" }
  Column {
    width: root.availableWidth
    spacing: Style.spacing.lg
    Button {
      width: parent.width
      text: "Lookup Another Name"
      onClicked: root.anotherRequested()
    }
    StateMessage { width: parent.width; visible: !root.ready; result: root.result; loadingText: "Querying A and AAAA records…" }
    Text { visible: root.ready; width: parent.width; text: root.result.status === "empty" ? root.result.message : "DNS answers for " + root.result.data.name; textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere; color: root.result.status === "empty" ? Color.urgent : Color.menu.text; font.family: Style.font.menuFamily; font.pixelSize: Style.font.title }
    Repeater {
      visible: root.ready
      model: root.ready ? [["IPv4 · A", root.answers(root.result.data.ipv4)], ["IPv6 · AAAA", root.answers(root.result.data.ipv6)]] : []
      delegate: Rectangle {
        required property var modelData
        width: parent.width
        height: detail.implicitHeight + Style.spacing.lg * 2
        radius: Style.cornerRadius
        color: Color.menu.selectedBackground
        Column { id: detail; anchors { left: parent.left; right: parent.right; margins: Style.spacing.lg; verticalCenter: parent.verticalCenter } spacing: Style.spacing.xs
          Text { text: modelData[0]; textFormat: Text.PlainText; color: Color.muted; font.family: Style.font.menuFamily; font.pixelSize: Style.font.bodySmall }
          Text { width: parent.width; text: modelData[1]; textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere; color: Color.menu.text; font.family: Style.font.menuFamily; font.pixelSize: Style.font.body }
        }
      }
    }
    Text { visible: root.ready && root.result.completeness === "partial"; width: parent.width; text: "Partial result: one record family could not be queried."; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Color.urgent; font.family: Style.font.menuFamily; font.pixelSize: Style.font.bodySmall }
    Text { visible: root.ready; text: "Source: resolvectl query · separate fixed A and AAAA requests"; textFormat: Text.PlainText; color: Color.muted; font.family: Style.font.menuFamily; font.pixelSize: Style.font.bodySmall }
  }
}
