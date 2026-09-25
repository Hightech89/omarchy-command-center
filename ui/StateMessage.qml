import QtQuick
import qs.Commons

Item {
  id: root
  property var result: null
  property string emptyText: "No observations were returned."
  property string loadingText: "Checking system data…"
  implicitHeight: message.implicitHeight + Style.spacing.xxl * 2

  Text {
    id: message
    anchors.centerIn: parent
    width: parent.width - Style.spacing.xxl * 2
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    textFormat: Text.PlainText
    color: root.result && (root.result.status === "error" || root.result.status === "timeout") ? Color.urgent : Color.muted
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.body
    text: !root.result || root.result.status === "loading" ? root.loadingText
      : root.result.status === "empty" ? root.emptyText
      : root.result.status === "unavailable" ? "Unavailable: " + (root.result.message || "This source could not be observed.")
      : root.result.status === "timeout" ? "Timed out: " + (root.result.message || "The observation did not finish in time.")
      : root.result.status === "canceled" ? "Canceled."
      : root.result.message || "Unable to show this result."
  }
}
