import QtQuick
import QtQuick.Controls
import qs.Commons

ScrollView {
  id: root
  property var result: null
  property bool ready: result && (result.status === "success" || result.status === "empty") && result.data
  function units(scope) { return ready ? result.data.units.filter(function(unit) { return unit.scope === scope }) : [] }
  Column { width: root.availableWidth; spacing: Style.spacing.lg
    StateMessage { width: parent.width; visible: !root.ready || root.result.status === "empty"; result: root.result; emptyText: "No failed services observed." }
    Repeater { visible: root.ready && root.result.status !== "empty"; model: ["system", "user"]
      delegate: Column { required property string modelData; width: parent.width; spacing: Style.spacing.sm
        Text { text: modelData === "system" ? "System" : "User"; textFormat: Text.PlainText; color: Color.menu.text; font.family: Style.font.menuFamily; font.pixelSize: Style.font.title }
        Text { visible: root.units(modelData).length === 0; text: "No failed units observed in this scope."; textFormat: Text.PlainText; color: Color.muted; font.family: Style.font.menuFamily; font.pixelSize: Style.font.body }
        Repeater { model: root.units(modelData); delegate: Text { required property var modelData; width: parent.width; wrapMode: Text.Wrap; text: modelData.unit + " — " + modelData.description + " (" + modelData.active + "/" + modelData.sub + ")"; textFormat: Text.PlainText; color: Color.menu.text; font.family: Style.font.menuFamily; font.pixelSize: Style.font.body } }
      }
    }
    Text { visible: root.ready && root.result.completeness === "partial"; text: "Partial result: one or more systemd scopes could not be obtained."; textFormat: Text.PlainText; color: Color.urgent; font.family: Style.font.menuFamily; font.pixelSize: Style.font.body }
  }
}
