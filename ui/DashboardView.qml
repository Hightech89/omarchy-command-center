import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../presentation/Formatters.js" as Formatters

Item {
  id: root
  property var liveResult: null
  property var cpuResult: null
  property var inventoryResult: null
  property var networkResult: null
  property real localUptimeSeconds: -1
  property var lastCpu: null
  property string lastCpuObservedAt: ""
  property var lastMemory: null
  property var lastLoad: null
  property string lastMemoryObservedAt: ""
  property var lastRootStorage: null
  property string lastRootStorageObservedAt: ""
  property var lastFailedServices: null
  property string lastFailedServicesObservedAt: ""
  property var lastNetwork: null
  property string lastNetworkObservedAt: ""
  implicitHeight: grid.implicitHeight
  function component(result, name) { return result && result.data && result.data.components ? result.data.components[name] : null }
  function componentOk(result, name) {
    var part = component(result, name)
    return part && (part.status === "success" || part.status === "empty")
  }
  function componentProblem(result, name) {
    var part = component(result, name)
    return result && result.status !== "loading" && part && part.status !== "success" && part.status !== "empty"
  }
  function failedServicesOk(result) {
    return componentOk(result, "failedSystem") || componentOk(result, "failedUser")
  }
  function failedServicesProblem(result) {
    return result && result.status !== "loading" && result.data && result.data.components && !failedServicesOk(result)
  }
  function isLoading(result) { return result && result.status === "loading" }
  function isFailure(result) { return result && result.status !== "success" && result.status !== "empty" && result.status !== "loading" }
  function stateText(result) {
    if (!result || result.status === "loading") return "Checking…"
    if (result.status === "unavailable") return "Unavailable"
    if (result.status === "timeout") return "Timed out"
    if (result.status === "canceled") return "Canceled"
    if (result.status === "error") return "Error"
    return "Unavailable"
  }
  function observedAt(result, componentName) {
    var part = component(result, componentName)
    return part && part.observedAt ? part.observedAt : (result && result.observedAt ? result.observedAt : "")
  }
  function refreshDetail(observedAt) {
    return "Refreshing… last observed " + Formatters.timestamp(observedAt)
  }
  function staleDetail(result, observedAt) {
    return "Stale, last observed " + Formatters.timestamp(observedAt) + " · " + stateText(result)
  }
  function staleComponentDetail(result, componentName, observedAt) {
    return "Stale, last observed " + Formatters.timestamp(observedAt) + " · " + stateText(component(result, componentName) || result)
  }
  function memoryValue(memory) {
    return Formatters.percent(memory.used * 100 / memory.total)
  }
  function memoryDetail(memory, load) {
    var detail = Formatters.bytes(memory.available) + " available"
    if (load)
      detail += " · load " + Formatters.load(load.one) + " / " + Formatters.load(load.five) + " / " + Formatters.load(load.fifteen)
    return detail
  }
  function rootStorageDetail(storage) {
    return Formatters.bytes(storage.used) + " used / " + Formatters.bytes(storage.available) + " available"
  }
  function failedServicesDetail(result, data) {
    if (result && result.completeness === "partial")
      return "Partial · last observed " + Formatters.timestamp(lastFailedServicesObservedAt)
    return "System + User scopes"
  }
  function failedServicesStaleDetail(result) {
    return "Stale, last observed " + Formatters.timestamp(lastFailedServicesObservedAt) + " · Failed-service scopes unavailable"
  }
  function networkValue(network) {
    if (network.connectionState === "connected-local") return "Connected locally"
    if (network.connectionState === "no-default-route") return "No default route"
    if (network.connectionState === "interface-unavailable") return "Interface unavailable"
    if (network.connectionState === "interface-down") return "Interface is down"
    return "No usable address"
  }
  function networkDetail(network) {
    var name = network.primaryInterface ? network.primaryInterface.name : "No interface"
    var address = network.ipv4.length ? network.ipv4[0] : network.ipv6.length ? network.ipv6[0] : "No general local address"
    return name + " · " + address
  }
  onCpuResultChanged: {
    if (componentOk(cpuResult, "cpuUsage") && cpuResult.data && cpuResult.data.cpu) {
      lastCpu = cpuResult.data.cpu
      lastCpuObservedAt = observedAt(cpuResult, "cpuUsage")
    }
  }
  onLiveResultChanged: {
    if (componentOk(liveResult, "memory") && liveResult.data && liveResult.data.memory) {
      lastMemory = liveResult.data.memory
      lastLoad = componentOk(liveResult, "load") && liveResult.data ? liveResult.data.load : null
      lastMemoryObservedAt = observedAt(liveResult, "memory")
    }
  }
  onInventoryResultChanged: {
    if (componentOk(inventoryResult, "rootStorage") && inventoryResult.data && inventoryResult.data.rootStorage) {
      lastRootStorage = inventoryResult.data.rootStorage
      lastRootStorageObservedAt = observedAt(inventoryResult, "rootStorage")
    }
    if (failedServicesOk(inventoryResult) && inventoryResult.data && inventoryResult.data.failedServices) {
      lastFailedServices = inventoryResult.data.failedServices
      lastFailedServicesObservedAt = inventoryResult.observedAt || observedAt(inventoryResult, "failedSystem") || observedAt(inventoryResult, "failedUser")
    }
  }
  onNetworkResultChanged: {
    if (networkResult && networkResult.status === "success" && networkResult.data) {
      lastNetwork = networkResult.data
      lastNetworkObservedAt = networkResult.observedAt || ""
    }
  }
  GridLayout {
    id: grid
    width: parent.width
    columns: width > Style.space(180) * 3 ? 3 : 2
    columnSpacing: Style.spacing.md
    rowSpacing: Style.spacing.md
    StatusCard { Layout.fillWidth: true; title: "CPU"; value: root.lastCpu ? Formatters.percent(root.lastCpu.usagePercent) : root.stateText(root.cpuResult); detail: root.isLoading(root.cpuResult) && root.lastCpu ? root.refreshDetail(root.lastCpuObservedAt) : root.componentProblem(root.cpuResult, "cpuUsage") && root.lastCpu ? root.staleComponentDetail(root.cpuResult, "cpuUsage", root.lastCpuObservedAt) : root.isFailure(root.cpuResult) && root.lastCpu ? root.staleDetail(root.cpuResult, root.lastCpuObservedAt) : "Aggregate /proc/stat"; alert: (root.componentProblem(root.cpuResult, "cpuUsage") || root.isFailure(root.cpuResult)) && root.lastCpu }
    StatusCard { Layout.fillWidth: true; title: "Memory"; value: root.lastMemory ? root.memoryValue(root.lastMemory) : root.stateText(root.liveResult); detail: root.isLoading(root.liveResult) && root.lastMemory ? root.refreshDetail(root.lastMemoryObservedAt) : root.componentProblem(root.liveResult, "memory") && root.lastMemory ? root.staleComponentDetail(root.liveResult, "memory", root.lastMemoryObservedAt) : root.isFailure(root.liveResult) && root.lastMemory ? root.staleDetail(root.liveResult, root.lastMemoryObservedAt) : root.lastMemory ? root.memoryDetail(root.lastMemory, root.lastLoad) : "/proc/meminfo"; alert: (root.componentProblem(root.liveResult, "memory") || root.isFailure(root.liveResult)) && root.lastMemory }
    StatusCard { Layout.fillWidth: true; title: "Root storage"; value: root.lastRootStorage ? Formatters.percent(root.lastRootStorage.usePercent) : root.stateText(root.inventoryResult); detail: root.isLoading(root.inventoryResult) && root.lastRootStorage ? root.refreshDetail(root.lastRootStorageObservedAt) : root.componentProblem(root.inventoryResult, "rootStorage") && root.lastRootStorage ? root.staleComponentDetail(root.inventoryResult, "rootStorage", root.lastRootStorageObservedAt) : root.isFailure(root.inventoryResult) && root.lastRootStorage ? root.staleDetail(root.inventoryResult, root.lastRootStorageObservedAt) : root.lastRootStorage ? root.rootStorageDetail(root.lastRootStorage) : "findmnt"; alert: (root.componentProblem(root.inventoryResult, "rootStorage") || root.isFailure(root.inventoryResult)) && root.lastRootStorage }
    StatusCard { Layout.fillWidth: true; title: "Uptime"; value: root.localUptimeSeconds >= 0 ? Formatters.duration(root.localUptimeSeconds) : "Checking…"; detail: "/proc/uptime" }
    StatusCard { Layout.fillWidth: true; title: "Failed services"; value: root.lastFailedServices ? String(root.lastFailedServices.totalCount) : root.stateText(root.inventoryResult); detail: root.isLoading(root.inventoryResult) && root.lastFailedServices ? root.refreshDetail(root.lastFailedServicesObservedAt) : root.failedServicesProblem(root.inventoryResult) && root.lastFailedServices ? root.failedServicesStaleDetail(root.inventoryResult) : root.isFailure(root.inventoryResult) && root.lastFailedServices ? root.staleDetail(root.inventoryResult, root.lastFailedServicesObservedAt) : root.lastFailedServices ? root.failedServicesDetail(root.inventoryResult, root.lastFailedServices) : "System + User scopes"; alert: root.lastFailedServices && root.lastFailedServices.totalCount > 0 }
    StatusCard { Layout.fillWidth: true; title: "Network"; value: root.lastNetwork ? root.networkValue(root.lastNetwork) : root.stateText(root.networkResult); detail: root.isLoading(root.networkResult) && root.lastNetwork ? root.refreshDetail(root.lastNetworkObservedAt) : root.isFailure(root.networkResult) && root.lastNetwork ? root.staleDetail(root.networkResult, root.lastNetworkObservedAt) : root.lastNetwork ? root.networkDetail(root.lastNetwork) : "Local route/link/address state"; alert: root.lastNetwork && root.lastNetwork.connectionState !== "connected-local" }
  }
}
