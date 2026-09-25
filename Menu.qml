import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "controllers"
import "services"
import "ui"

Item {
  id: root
  property var shell: null; property var manifest: null; property bool opened: false; property real uptimeSeconds: -1
  SystemService { id: systemService }
  CommandCenterController { id: controller; systemService: systemService }

  function open(payloadJson) { opened = true; controller.reset(); controller.refreshDashboardCpu(); controller.refreshDashboardLive(); controller.refreshDashboardInventory(); cpuTimer.start(); liveTimer.start(); inventoryTimer.start(); uptimeTimer.start(); Qt.callLater(function() { keyCatcher.forceActiveFocus() }) }
  function close() { opened = false; cpuTimer.stop(); liveTimer.stop(); inventoryTimer.stop(); uptimeTimer.stop(); systemService.cancelAll(); uptimeSeconds = -1; controller.reset() }
  function dismiss() { close(); if (shell && typeof shell.hide === "function") shell.hide((manifest && manifest.id) || "community.command-center") }
  function activate(actionId) { if (controller.activateAction(actionId)) controller.refreshCurrentAction(); Qt.callLater(function() { keyCatcher.forceActiveFocus() }) }
  function backOrDismiss() { if (!controller.back()) dismiss(); Qt.callLater(function() { keyCatcher.forceActiveFocus() }) }
  function currentResult() { if (controller.currentActionId === "system.overview") return systemService.systemOverviewResult; if (controller.currentActionId === "system.disk-usage") return systemService.diskUsageResult; if (controller.currentActionId === "system.memory-usage") return systemService.memoryUsageResult; if (controller.currentActionId === "system.failed-services") return systemService.failedServicesResult; return null }
  Connections { target: systemService; function onDashboardLiveSnapshotResultChanged() { var result = systemService.dashboardLiveSnapshotResult; if (result && result.data && result.data.uptime) root.uptimeSeconds = result.data.uptime.seconds } }
  Timer { id: cpuTimer; interval: 2000; repeat: true; onTriggered: controller.refreshDashboardCpu() }
  Timer { id: liveTimer; interval: 5000; repeat: true; onTriggered: controller.refreshDashboardLive() }
  Timer { id: inventoryTimer; interval: 30000; repeat: true; onTriggered: controller.refreshDashboardInventory() }
  Timer { id: uptimeTimer; interval: 1000; repeat: true; onTriggered: if (root.uptimeSeconds >= 0) root.uptimeSeconds += 1 }

  PanelWindow {
    id: panel; visible: root.opened; anchors { top: true; bottom: true; left: true; right: true } color: "transparent"
    WlrLayershell.namespace: "community-command-center"; WlrLayershell.layer: WlrLayer.Overlay; WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive; exclusionMode: ExclusionMode.Ignore
    Rectangle { anchors.fill: parent; color: Color.menu.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
    BorderSurface {
      width: Math.min(Style.space(440), panel.width - Style.gapsOut * 2); height: Math.min(Style.space(360), panel.height - Style.gapsOut * 2); anchors.centerIn: parent; radius: Style.cornerRadius; color: Color.menu.background; borderSpec: Border.localOrSurfaceSpec("menu", "border", Color.menu.border, Color.menu.border, Math.max(1, Style.normalBorderWidth))
      MouseArea { anchors.fill: parent; onClicked: {} }
      Item {
        id: keyCatcher; anchors.fill: parent; focus: true; Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (controller.route === controller.rootRoute) {
            if (event.key === Qt.Key_Escape) { root.backOrDismiss(); event.accepted = true; return }
            if (event.key === Qt.Key_Up) { controller.moveSelection(-1); searchView.reveal(); event.accepted = true; return }
            if (event.key === Qt.Key_Down) { controller.moveSelection(1); searchView.reveal(); event.accepted = true; return }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { if (controller.selectedIndex >= 0) root.activate(controller.searchResults[controller.selectedIndex].id); event.accepted = true; return }
            if (event.key === Qt.Key_Backspace) { if (controller.searchQuery.length) controller.setSearchQuery(controller.searchQuery.slice(0, -1)); event.accepted = true; return }
            if (event.text && event.text.length === 1 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) { controller.setSearchQuery(controller.searchQuery + event.text); event.accepted = true }
          } else if (event.key === Qt.Key_Escape) { root.backOrDismiss(); event.accepted = true }
        }
        Column {
          anchors.fill: parent; anchors.margins: Style.spacing.xxl; spacing: Style.spacing.lg
          Row { width: parent.width; Text { text: controller.route === controller.rootRoute ? "Command Center" : (controller.currentAction ? controller.currentAction.name : "Command Center"); textFormat: Text.PlainText; color: Color.menu.text; font.family: Style.font.menuFamily; font.pixelSize: Style.font.title } Text { anchors.right: parent.right; text: controller.route === controller.rootRoute ? "Inspection · diagnostics · learning" : "Esc to return"; textFormat: Text.PlainText; color: Color.muted; font.family: Style.font.menuFamily; font.pixelSize: Style.font.bodySmall } }
          DashboardView { visible: controller.route === controller.rootRoute; width: parent.width; cpuResult: systemService.dashboardCpuSnapshotResult; liveResult: systemService.dashboardLiveSnapshotResult; inventoryResult: systemService.dashboardInventorySnapshotResult; localUptimeSeconds: root.uptimeSeconds }
          SearchView { id: searchView; visible: controller.route === controller.rootRoute; width: parent.width; height: parent.height - y; controller: controller; onActivate: root.activate(actionId) }
          Item { visible: controller.route !== controller.rootRoute; width: parent.width; height: parent.height - y
            SystemOverviewView { anchors.fill: parent; visible: controller.currentActionId === "system.overview"; result: root.currentResult() }
            DiskUsageView { anchors.fill: parent; visible: controller.currentActionId === "system.disk-usage"; result: root.currentResult() }
            MemoryUsageView { anchors.fill: parent; visible: controller.currentActionId === "system.memory-usage"; result: root.currentResult() }
            FailedServicesView { anchors.fill: parent; visible: controller.currentActionId === "system.failed-services"; result: root.currentResult() }
            StateMessage { anchors.fill: parent; visible: controller.currentActionId.indexOf("system.") !== 0; result: ({ status: "unavailable", message: "This action is not connected in the current development milestone." }) }
          }
        }
      }
    }
  }
}
