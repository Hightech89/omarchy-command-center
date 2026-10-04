import QtQuick
import QtQuick.Controls
import qs.Commons

ScrollView {
  id: root
  property var result: null
  clip: true
  Column {
    width: root.availableWidth
    spacing: Style.spacing.md
    Text { text: "System Health"; textFormat: Text.PlainText; color: Color.menu.text; font.family: Style.font.menuFamily; font.pixelSize: Style.font.title }
    Text { width: parent.width; text: root.result && root.result.status === "running" ? "Checking system health…" : "Overall: " + (root.result ? root.result.status : "unavailable"); textFormat: Text.PlainText; color: Color.menu.text; font.family: Style.font.menuFamily; font.pixelSize: Style.font.body }
    Text { width: parent.width; visible: root.result && root.result.completeness !== "complete" && root.result.status !== "running"; text: "Diagnostic incomplete: one or more checks were unavailable or could not be assessed."; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Color.muted; font.family: Style.font.menuFamily; font.pixelSize: Style.font.bodySmall }
    Repeater { model: root.result && root.result.checks ? root.result.checks : []; delegate: DiagnosticRow { required property var modelData; width: parent.width; item: modelData } }
  }
}
