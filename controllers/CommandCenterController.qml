import QtQml

import "../catalog/CommandCatalog.js" as CommandCatalog
import "../catalog/Search.js" as Search
import "CommandCenterState.js" as State

// Typed controller. It maps stable action IDs to explicit service methods and
// exposes no process-definition boundary.
QtObject {
  id: root

  readonly property string rootRoute: State.Route.Root
  readonly property string inputRoute: State.Route.Input
  readonly property string resultRoute: State.Route.Result
  readonly property var catalog: CommandCatalog.Actions
  property var systemService: null
  property var networkService: null

  property string currentActionId: ""
  property string route: State.Route.Root
  property string searchQuery: ""
  property int selectedIndex: 0
  property string activationError: ""
  property var searchResults: CommandCatalog.allActions()

  readonly property var currentAction: CommandCatalog.actionById(currentActionId)

  function setSearchQuery(query) {
    searchQuery = typeof query === "string" ? query : ""
    searchResults = Search.search(catalog, searchQuery)
    selectedIndex = searchResults.length > 0 ? 0 : -1
  }

  function setSelectedIndex(index) {
    if (searchResults.length === 0) {
      selectedIndex = -1
      return false
    }
    if (typeof index !== "number" || !Number.isInteger(index))
      return false
    selectedIndex = Math.max(0, Math.min(index, searchResults.length - 1))
    return true
  }

  function moveSelection(delta) {
    if (searchResults.length === 0) return false
    selectedIndex = (selectedIndex + delta + searchResults.length) % searchResults.length
    return true
  }

  function activateAction(actionId) {
    var activation = State.activationFor(catalog, actionId)
    if (!activation.ok) {
      activationError = activation.reason
      return false
    }

    currentActionId = activation.action.id
    route = activation.route
    activationError = ""
    return true
  }

  function activateSelectedAction() {
    if (selectedIndex < 0 || selectedIndex >= searchResults.length)
      return false
    return activateAction(searchResults[selectedIndex].id)
  }

  // The UI only submits stable action IDs; this is the trusted service switch.
  function refreshCurrentAction() {
    if (currentActionId === "system.overview" && systemService) { systemService.refreshSystemOverview(); return true }
    if (currentActionId === "system.disk-usage" && systemService) { systemService.refreshDiskUsage(); return true }
    if (currentActionId === "system.memory-usage" && systemService) { systemService.refreshMemoryUsage(); return true }
    if (currentActionId === "system.failed-services" && systemService) { systemService.refreshFailedServices(); return true }
    if (currentActionId === "network.overview" && networkService) { networkService.refreshNetworkOverview(); return true }
    if (currentActionId === "network.listening-ports" && networkService) { networkService.refreshListeningPorts(); return true }
    return false
  }

  function submitCurrentInput(input) {
    if (!networkService || !input || typeof input !== "object" || input.ok !== true)
      return false
    var generation = 0
    if (currentActionId === "network.ping-host") generation = networkService.pingHost(input)
    else if (currentActionId === "network.dns-lookup") generation = networkService.lookupDns(input)
    else return false
    if (generation > 0) route = State.Route.Result
    return generation > 0
  }

  function refreshDashboardLive() { if (systemService) systemService.refreshDashboardLiveSnapshot() }
  function refreshDashboardCpu() { if (systemService) systemService.refreshDashboardCpuSnapshot() }
  function refreshDashboardInventory() { if (systemService) systemService.refreshDashboardInventorySnapshot() }
  function refreshDashboardNetwork() { if (networkService) networkService.refreshDashboardNetworkSnapshot() }

  // A child placeholder returns to the action list. The selected action ID is
  // retained so a future view can restore the matching row without rerouting.
  function back() {
    if (route === State.Route.Result && currentAction && currentAction.inputKind !== "none") {
      route = State.Route.Input
      return true
    }
    if (route !== State.Route.Root) {
      route = State.Route.Root
      return true
    }
    if (searchQuery !== "") {
      setSearchQuery("")
      return true
    }
    return false
  }

  function reset() {
    currentActionId = ""
    route = State.Route.Root
    activationError = ""
    setSearchQuery("")
  }
}
