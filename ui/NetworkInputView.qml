import QtQuick
import qs.Commons
import qs.Ui
import "../parsers/Validation.js" as Validation

Item {
  id: root
  property string actionId: ""
  property string validationMessage: ""
  property var typedValue: null
  signal submit(var input)
  signal escapePressed()

  function validate() {
    typedValue = actionId === "network.dns-lookup"
      ? Validation.validateDnsName(field.text)
      : Validation.validatePingTarget(field.text)
    validationMessage = typedValue.ok ? "" : typedValue.message
    return typedValue
  }
  function prepare() {
    field.text = ""
    typedValue = null
    validationMessage = ""
    Qt.callLater(function() { field.forceActiveFocus() })
  }
  onVisibleChanged: if (visible) prepare()

  Column {
    anchors { left: parent.left; right: parent.right; top: parent.top }
    spacing: Style.spacing.lg
    Text {
      width: parent.width
      text: root.actionId === "network.dns-lookup"
        ? "Enter an ASCII hostname. Punycode A-labels are supported; raw Unicode and IP literals are not."
        : "Enter a strict IPv4 address, IPv6 address, or ASCII hostname."
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: Color.muted
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.body
    }
    TextField {
      id: field
      width: parent.width
      placeholderText: root.actionId === "network.dns-lookup" ? "example.com" : "127.0.0.1"
      onTextEdited: root.validate()
      onAccepted: {
        var checked = root.validate()
        if (checked.ok) root.submit(checked)
      }
      Keys.onEscapePressed: function(event) { root.escapePressed(); event.accepted = true }
    }
    Text {
      visible: root.validationMessage !== ""
      width: parent.width
      text: root.validationMessage
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: Color.urgent
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.bodySmall
    }
    Text {
      width: parent.width
      text: root.actionId === "network.dns-lookup" ? "Source: resolvectl query (separate A and AAAA requests)" : "Source: ping (4 packets, bounded deadline)"
      textFormat: Text.PlainText
      color: Color.muted
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
