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
  property var shell: null
  property var manifest: null
  property bool opened: false
  property real uptimeSeconds: -1
  property bool pendingNetworkRefresh: false
  property bool pendingActionRefresh: false
  property var pendingNetworkInput: null

  SystemService { id: systemService }
  NetworkService { id: networkService }
  CommandCenterController { id: controller; systemService: systemService; networkService: networkService }

  function startDashboard() {
    if (!opened || controller.route !== controller.rootRoute) return
    pendingNetworkRefresh = true
    controller.refreshDashboardCpu()
    controller.refreshDashboardLive()
    controller.refreshDashboardInventory()
    cpuTimer.start(); liveTimer.start(); inventoryTimer.start(); networkTimer.start(); uptimeTimer.start()
  }
  function stopDashboard() {
    cpuTimer.stop(); liveTimer.stop(); inventoryTimer.stop(); networkTimer.stop(); uptimeTimer.stop()
    pendingNetworkRefresh = false
    systemService.cancelDashboardCpuSnapshot(); systemService.cancelDashboardLiveSnapshot(); systemService.cancelDashboardInventorySnapshot()
    networkService.cancelDashboardNetworkSnapshot()
  }
  function tryStartPending() {
    if (!opened || systemService.busy || networkService.busy) return
    if (pendingNetworkInput !== null) {
      var input = pendingNetworkInput
      pendingNetworkInput = null
      if (controller.submitCurrentInput(input)) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      return
    }
    if (pendingActionRefresh) {
      pendingActionRefresh = false
      controller.refreshCurrentAction()
      return
    }
    if (controller.route === controller.rootRoute && pendingNetworkRefresh) {
      pendingNetworkRefresh = false
      controller.refreshDashboardNetwork()
    }
  }
  function open(payloadJson) { opened = true; controller.reset(); startDashboard(); Qt.callLater(function() { keyCatcher.forceActiveFocus() }) }
  function close() { opened = false; stopDashboard(); pendingActionRefresh = false; pendingNetworkInput = null; systemService.cancelAll(); networkService.cancelAll(); uptimeSeconds = -1; controller.reset() }
  function dismiss() { close(); if (shell && typeof shell.hide === "function") shell.hide((manifest && manifest.id) || "community.command-center") }
  function activate(actionId) {
    stopDashboard(); systemService.cancelAll(); networkService.cancelAll()
    if (controller.activateAction(actionId) && controller.route === controller.resultRoute) {
      pendingActionRefresh = true
      tryStartPending()
    }
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  function submitNetworkInput(input) {
    pendingNetworkInput = input
    tryStartPending()
  }
  function backOrDismiss() {
    if (controller.route !== controller.rootRoute) {
      pendingActionRefresh = false; pendingNetworkInput = null
      systemService.cancelAll(); networkService.cancelAll(); controller.back(); startDashboard()
    } else if (!controller.back()) dismiss()
    if (controller.route !== controller.inputRoute)
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  function currentResult() {
    if (controller.currentActionId === "system.overview") return systemService.systemOverviewResult
    if (controller.currentActionId === "system.disk-usage") return systemService.diskUsageResult
    if (controller.currentActionId === "system.memory-usage") return systemService.memoryUsageResult
    if (controller.currentActionId === "system.failed-services") return systemService.failedServicesResult
    if (controller.currentActionId === "network.overview") return networkService.networkOverviewResult
    if (controller.currentActionId === "network.listening-ports") return networkService.listeningPortsResult
    if (controller.currentActionId === "network.ping-host") return networkService.pingResult
    if (controller.currentActionId === "network.dns-lookup") return networkService.dnsResult
    return null
  }

  Connections {
    target: systemService
    function onDashboardLiveSnapshotResultChanged() { var result = systemService.dashboardLiveSnapshotResult; if (result && result.data && result.data.uptime) root.uptimeSeconds = result.data.uptime.seconds }
    function onBusyChanged() {
      root.tryStartPending()
    }
  }
  Connections { target: networkService; function onBusyChanged() { root.tryStartPending() } }
  Timer { id: cpuTimer; interval: 2000; repeat: true; onTriggered: if (root.opened && controller.route === controller.rootRoute && !networkService.busy) controller.refreshDashboardCpu() }
  Timer { id: liveTimer; interval: 5000; repeat: true; onTriggered: if (root.opened && controller.route === controller.rootRoute && !networkService.busy) controller.refreshDashboardLive() }
  Timer { id: inventoryTimer; interval: 30000; repeat: true; onTriggered: if (root.opened && controller.route === controller.rootRoute && !networkService.busy) controller.refreshDashboardInventory() }
  Timer { id: networkTimer; interval: 5500; repeat: true; onTriggered: if (root.opened && controller.route === controller.rootRoute && !systemService.busy && !networkService.busy) controller.refreshDashboardNetwork() }
  Timer { id: uptimeTimer; interval: 1000; repeat: true; onTriggered: if (root.uptimeSeconds >= 0) root.uptimeSeconds += 1 }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "community-command-center"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    Rectangle { anchors.fill: parent; color: Color.menu.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
    BorderSurface {
      width: Math.min(Style.space(440), panel.width - Style.gapsOut * 2)
      height: Math.min(Style.space(460), panel.height - Style.gapsOut * 2)
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: Color.menu.background
      borderSpec: Border.localOrSurfaceSpec("menu", "border", Color.menu.border, Color.menu.border, Math.max(1, Style.normalBorderWidth))
      MouseArea { anchors.fill: parent; onClicked: {} }
      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
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
          anchors.fill: parent
          anchors.margins: Style.spacing.xxl
          spacing: Style.spacing.lg
          Row {
            width: parent.width
            Text { text: controller.route === controller.rootRoute ? "Command Center" : (controller.currentAction ? controller.currentAction.name : "Command Center"); textFormat: Text.PlainText; color: Color.menu.text; font.family: Style.font.menuFamily; font.pixelSize: Style.font.title }
            Text { anchors.right: parent.right; text: controller.route === controller.rootRoute ? "Inspection · diagnostics · learning" : "Esc to return"; textFormat: Text.PlainText; color: Color.muted; font.family: Style.font.menuFamily; font.pixelSize: Style.font.bodySmall }
          }
          DashboardView {
            visible: controller.route === controller.rootRoute
            width: parent.width
            cpuResult: systemService.dashboardCpuSnapshotResult
            liveResult: systemService.dashboardLiveSnapshotResult
            inventoryResult: systemService.dashboardInventorySnapshotResult
            networkResult: networkService.dashboardNetworkSnapshotResult
            localUptimeSeconds: root.uptimeSeconds
          }
          SearchView { id: searchView; visible: controller.route === controller.rootRoute; width: parent.width; height: parent.height - y; controller: controller; onActivate: root.activate(actionId) }
          Item {
            visible: controller.route !== controller.rootRoute
            width: parent.width
            height: parent.height - y
            NetworkInputView { anchors.fill: parent; visible: controller.route === controller.inputRoute; actionId: controller.currentActionId; onSubmit: function(input) { root.submitNetworkInput(input) }; onEscapePressed: root.backOrDismiss() }
            SystemOverviewView { anchors.fill: parent; visible: controller.route === controller.resultRoute && controller.currentActionId === "system.overview"; result: root.currentResult() }
            DiskUsageView { anchors.fill: parent; visible: controller.route === controller.resultRoute && controller.currentActionId === "system.disk-usage"; result: root.currentResult() }
            MemoryUsageView { anchors.fill: parent; visible: controller.route === controller.resultRoute && controller.currentActionId === "system.memory-usage"; result: root.currentResult() }
            FailedServicesView { anchors.fill: parent; visible: controller.route === controller.resultRoute && controller.currentActionId === "system.failed-services"; result: root.currentResult() }
            NetworkOverviewView { anchors.fill: parent; visible: controller.route === controller.resultRoute && controller.currentActionId === "network.overview"; result: root.currentResult() }
            ListeningPortsView { anchors.fill: parent; visible: controller.route === controller.resultRoute && controller.currentActionId === "network.listening-ports"; result: root.currentResult() }
            PingResultView { anchors.fill: parent; visible: controller.route === controller.resultRoute && controller.currentActionId === "network.ping-host"; result: root.currentResult(); onAnotherRequested: root.backOrDismiss() }
            DnsLookupView { anchors.fill: parent; visible: controller.route === controller.resultRoute && controller.currentActionId === "network.dns-lookup"; result: root.currentResult(); onAnotherRequested: root.backOrDismiss() }
            StateMessage { anchors.fill: parent; visible: controller.route === controller.resultRoute && controller.currentActionId.indexOf("diagnostics.") === 0; result: ({ status: "unavailable", message: "Diagnostics are planned for Milestone 7 and do not execute yet." }) }
          }
        }
      }
    }
  }
}
