import QtQuick
import QtQuick.Controls
import qs.Commons

ScrollView {
  id: root
  property var result: null
  property bool ready: result && result.status === "success" && result.data
  function stateLabel(state) {
    if (state === "connected-local") return "Connected locally"
    if (state === "no-default-route") return "No default route"
    if (state === "interface-unavailable") return "Interface unavailable"
    if (state === "interface-down") return "Interface is down"
    if (state === "no-usable-address") return "No usable local address"
    return "Unavailable"
  }
  function addresses(values) { return values && values.length ? values.join("\n") : "None observed" }
  function dnsServers(values) { return values && values.length ? values.map(function(item) { return item.address }).join("\n") : "None observed" }
  function domains(values) { return values && values.length ? values.map(function(item) { return (item.routeOnly ? "~" : "") + item.name }).join("\n") : "None observed" }

  Column {
    width: root.availableWidth
    spacing: Style.spacing.md
    StateMessage { width: parent.width; visible: !root.ready; result: root.result; loadingText: "Checking local network state…" }
    Repeater {
      visible: root.ready
      model: root.ready ? [
        ["Connection state", root.stateLabel(root.result.data.connectionState)],
        ["Primary interface", root.result.data.primaryInterface ? root.result.data.primaryInterface.name : "Unavailable"],
        ["Operational state", root.result.data.primaryInterface ? root.result.data.primaryInterface.operationalState : "Unavailable"],
        ["IPv4", root.addresses(root.result.data.ipv4)],
        ["IPv6", root.addresses(root.result.data.ipv6)],
        ["Link-local detail", root.addresses(root.result.data.linkLocal)],
        ["Default gateway", root.result.data.route && root.result.data.route.gateway ? root.result.data.route.gateway : "On-link / not supplied"],
        ["Route metric", root.result.data.route && root.result.data.route.metric !== null ? String(root.result.data.route.metric) : "Not supplied"],
        ["DNS servers", root.dnsServers(root.result.data.dnsServers)],
        ["Search domains", root.domains(root.result.data.searchDomains)]
      ] : []
      delegate: Rectangle {
        required property var modelData
        width: parent.width
        height: row.implicitHeight + Style.spacing.lg * 2
        radius: Style.cornerRadius
        color: Color.menu.selectedBackground
        Row {
          id: row
          anchors { left: parent.left; right: parent.right; margins: Style.spacing.lg; verticalCenter: parent.verticalCenter }
          spacing: Style.spacing.lg
          Text { width: Style.space(105); text: modelData[0]; textFormat: Text.PlainText; color: Color.muted; font.family: Style.font.menuFamily; font.pixelSize: Style.font.bodySmall }
          Text { width: parent.width - Style.space(120); text: modelData[1]; textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere; color: Color.menu.text; font.family: Style.font.menuFamily; font.pixelSize: Style.font.body }
        }
      }
    }
    Text { visible: root.ready && root.result.data.routeSelection.ambiguous; width: parent.width; text: "Multiple equal-metric default routes were observed; the deterministic interface/name ordering selected the displayed route."; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Color.urgent; font.family: Style.font.menuFamily; font.pixelSize: Style.font.bodySmall }
    Text { visible: root.ready && root.result.completeness === "partial"; width: parent.width; text: "Partial result: DNS information could not be fully observed."; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Color.urgent; font.family: Style.font.menuFamily; font.pixelSize: Style.font.bodySmall }
    Text { visible: root.ready; width: parent.width; text: "Sources: ip -j route · ip -j link · ip -j address · resolvectl status\nLocal evidence only; this does not prove internet access."; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Color.muted; font.family: Style.font.menuFamily; font.pixelSize: Style.font.bodySmall }
  }
}
