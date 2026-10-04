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
    Text { text: "Network Diagnostic"; textFormat: Text.PlainText; color: Color.menu.text; font.family: Style.font.menuFamily; font.pixelSize: Style.font.title }
    Text { width: parent.width; text: root.result && root.result.status === "running" ? "Diagnostic in progress…" : "Overall: " + (root.result ? root.result.status : "unavailable"); textFormat: Text.PlainText; color: Color.menu.text; font.family: Style.font.menuFamily; font.pixelSize: Style.font.body }
    Text { width: parent.width; visible: root.result && !!root.result.stop; text: root.result ? "First issue: " + root.result.stop : ""; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Color.muted; font.family: Style.font.menuFamily; font.pixelSize: Style.font.bodySmall }
    Text { width: parent.width; visible: root.result && root.result.completeness === "unavailable"; text: "Diagnostic incomplete: some source data could not be assessed."; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Color.muted; font.family: Style.font.menuFamily; font.pixelSize: Style.font.bodySmall }
    Text { width: parent.width; text: "Public reachability sends ICMP echo requests to fixed diagnostic endpoints: Cloudflare, Quad9, and Google. Command Center sends no telemetry."; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Color.muted; font.family: Style.font.menuFamily; font.pixelSize: Style.font.bodySmall }
    Repeater { model: root.result && root.result.stages ? root.result.stages : []; delegate: DiagnosticRow { required property var modelData; width: parent.width; item: modelData } }
  }
}
