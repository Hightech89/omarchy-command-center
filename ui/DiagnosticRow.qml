import QtQuick
import qs.Commons

Rectangle {
  id: root
  property var item: ({})
  width: parent ? parent.width : 0
  height: Style.space(120)
  radius: Style.cornerRadius
  color: Color.menu.selectedBackground
  Column {
    id: content
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.spacing.lg }
    spacing: Style.spacing.sm
    Row {
      width: parent.width
      spacing: Style.spacing.md
      Text { width: parent.width - statusText.width - Style.spacing.md; text: root.item.name || ""; textFormat: Text.PlainText; elide: Text.ElideRight; color: Color.menu.text; font.family: Style.font.menuFamily; font.pixelSize: Style.font.body }
      Text { id: statusText; text: (root.item.status || "pending").toUpperCase(); textFormat: Text.PlainText; color: root.item.status === "critical" || root.item.status === "error" ? Color.urgent : Color.muted; font.family: Style.font.menuFamily; font.pixelSize: Style.font.bodySmall }
    }
    Text { width: parent.width; text: root.item.observed || "Waiting"; textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere; maximumLineCount: 2; elide: Text.ElideRight; color: Color.menu.text; font.family: Style.font.menuFamily; font.pixelSize: Style.font.body }
    Text { width: parent.width; visible: text.length > 0; text: [root.item.interpretation, root.item.explanation].filter(function(part) { return !!part }).join(" "); textFormat: Text.PlainText; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; color: Color.muted; font.family: Style.font.menuFamily; font.pixelSize: Style.font.bodySmall }
  }
}
