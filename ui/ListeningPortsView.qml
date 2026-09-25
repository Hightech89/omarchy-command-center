import QtQuick
import QtQuick.Controls
import qs.Commons

ScrollView {
  id: root
  property var result: null
  property bool ready: result && (result.status === "success" || result.status === "empty") && result.data
  function endpoint(address, port) {
    var shown = address.indexOf(":") !== -1 ? "[" + address + "]" : address
    return shown + ":" + (port === null ? "*" : String(port))
  }
  function owner(owners) {
    if (!owners || owners.length === 0) return "Owner unavailable (normal without elevated visibility)"
    return owners.map(function(item) { return item.process + " · pid " + item.pid }).join(", ")
  }
  Column {
    width: root.availableWidth
    spacing: Style.spacing.sm
    StateMessage { width: parent.width; visible: !root.ready || root.result.status === "empty"; result: root.result; loadingText: "Checking listening sockets…"; emptyText: "No TCP or UDP listening sockets were reported." }
    Repeater {
      visible: root.ready && root.result.status !== "empty"
      model: root.result.data.sockets
      delegate: Rectangle {
        required property var modelData
        width: parent.width
        height: detail.implicitHeight + Style.spacing.lg * 2
        radius: Style.cornerRadius
        color: Color.menu.selectedBackground
        Column {
          id: detail
          anchors { left: parent.left; right: parent.right; margins: Style.spacing.lg; verticalCenter: parent.verticalCenter }
          spacing: Style.spacing.xs
          Text { width: parent.width; text: modelData.protocol.toUpperCase() + " · " + modelData.state + " · " + root.endpoint(modelData.localAddress, modelData.localPort); textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere; color: Color.menu.text; font.family: Style.font.menuFamily; font.pixelSize: Style.font.body }
          Text { width: parent.width; text: root.owner(modelData.owners); textFormat: Text.PlainText; elide: Text.ElideRight; color: Color.muted; font.family: Style.font.menuFamily; font.pixelSize: Style.font.bodySmall }
        }
      }
    }
    Text { visible: root.ready; text: "Source: ss -H -l -n -t -u -p"; textFormat: Text.PlainText; color: Color.muted; font.family: Style.font.menuFamily; font.pixelSize: Style.font.bodySmall }
  }
}
