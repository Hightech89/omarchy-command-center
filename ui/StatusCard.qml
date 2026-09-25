import QtQuick
import qs.Commons
import qs.Ui

BorderSurface {
  id: root
  property string title: ""
  property string value: "Unavailable"
  property string detail: ""
  property bool alert: false
  radius: Style.cornerRadius
  color: Color.menu.background
  borderSpec: Border.localOrSurfaceSpec("menu", "border", Color.menu.border, Color.menu.border, Math.max(1, Style.normalBorderWidth))
  implicitHeight: column.implicitHeight + Style.spacing.xl * 2
  Column {
    id: column
    anchors { left: parent.left; right: parent.right; margins: Style.spacing.xl; verticalCenter: parent.verticalCenter }
    spacing: Style.spacing.xs
    Text { text: root.title; textFormat: Text.PlainText; color: Color.muted; font.family: Style.font.menuFamily; font.pixelSize: Style.font.bodySmall }
    Text { text: root.value; textFormat: Text.PlainText; color: root.alert ? Color.urgent : Color.menu.text; font.family: Style.font.menuFamily; font.pixelSize: Style.font.title; elide: Text.ElideRight; width: parent.width }
    Text { visible: root.detail !== ""; text: root.detail; textFormat: Text.PlainText; color: Color.muted; font.family: Style.font.menuFamily; font.pixelSize: Style.font.bodySmall; elide: Text.ElideRight; width: parent.width }
  }
}
