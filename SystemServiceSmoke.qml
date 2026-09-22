import QtQuick
import Quickshell

import "services"

// Headless read-only integration smoke test. It reports statuses only and
// never prints the observed hostname, OS, filesystem, unit, or CPU values.
ShellRoot {
  id: testRoot

  property int phase: 0
  property int failures: 0
  property var statuses: []
  property int replacementFirstGeneration: 0
  property int replacementSecondGeneration: 0

  function check(condition, message) {
    if (!condition) {
      failures += 1
      console.error("FAIL: " + message)
    }
  }

  function acceptable(result) {
    return result && (result.status === "success" || result.status === "empty"
      || result.status === "unavailable")
  }

  function record(result) {
    statuses.push(result.status + "/" + result.completeness)
  }

  function next() {
    phase += 1
    Qt.callLater(startPhase)
  }

  function startPhase() {
    if (phase === 1) service.refreshSystemOverview()
    else if (phase === 2) service.refreshDiskUsage()
    else if (phase === 3) service.refreshMemoryUsage()
    else if (phase === 4) service.refreshFailedServices()
    else if (phase === 5) service.refreshSystemdSystemState()
    else if (phase === 6) service.refreshDashboardSystemSnapshot()
    else if (phase === 7) {
      replacementFirstGeneration = service.refreshDashboardSystemSnapshot()
      replacementTimer.restart()
    } else if (phase === 8) {
      service.refreshSystemOverview()
      cancelTimer.restart()
    }
    else {
      console.log(failures === 0
        ? "SYSTEM_SERVICE_SMOKE_PASS statuses=" + statuses.join(",")
        : "SYSTEM_SERVICE_SMOKE_FAIL=" + failures + " statuses=" + statuses.join(","))
      Qt.quit()
    }
  }

  SystemService {
    id: service

    onSystemOverviewCompleted: function(result) {
      testRoot.record(result)
      if (testRoot.phase === 8) {
        testRoot.check(result.status === "canceled", "explicit overview cancellation")
        testRoot.next()
        return
      }
      testRoot.check(result.status === "success", "system overview should have usable local data")
      testRoot.check(result.data && result.data.hostname && typeof result.data.hostname.value === "string"
        && result.data.hostname.value.length > 0, "hostname presence")
      testRoot.check(result.data && result.data.os && typeof result.data.os.displayName === "string"
        && result.data.os.displayName.length > 0, "OS information")
      testRoot.check(result.data && result.data.kernel && typeof result.data.kernel.ostype === "string"
        && typeof result.data.kernel.release === "string", "kernel information")
      testRoot.check(result.data && result.data.cpu && Number.isInteger(result.data.cpu.logicalProcessors)
        && result.data.cpu.logicalProcessors > 0 && typeof result.data.cpu.usagePercent === "number"
        && result.data.cpu.usagePercent >= 0 && result.data.cpu.usagePercent <= 100, "CPU information")
      testRoot.check(result.data && result.data.memory && result.data.memory.total > 0
        && result.data.memory.used >= 0 && result.data.memory.available >= 0, "memory information")
      testRoot.check(result.data && result.data.uptime && result.data.uptime.seconds >= 0, "uptime information")
      testRoot.check(result.data && result.data.load && result.data.load.one >= 0
        && result.data.load.runningTasks <= result.data.load.totalTasks, "load information")
      testRoot.check(result.data && result.data.rootStorage && result.data.rootStorage.target === "/"
        && result.data.rootStorage.size > 0, "root storage information")
      testRoot.next()
    }

    onDiskUsageCompleted: function(result) {
      testRoot.record(result)
      testRoot.check(result.status === "success" || result.status === "empty", "disk query status")
      testRoot.check(result.data && Array.isArray(result.data.filesystems), "disk records array")
      if (result.data && result.data.filesystems.length > 0) {
        var record = result.data.filesystems[0]
        testRoot.check(typeof record.target === "string" && record.target.length > 0, "disk target type")
        testRoot.check(Number.isInteger(record.size) && record.size > 0, "disk size type")
        testRoot.check(typeof record.usePercent === "number" && record.usePercent >= 0
          && record.usePercent <= 100, "disk percentage range")
      }
      testRoot.next()
    }

    onMemoryUsageCompleted: function(result) {
      testRoot.record(result)
      testRoot.check(result.status === "success", "memory query status")
      testRoot.check(result.data && result.data.total > 0 && result.data.used >= 0
        && result.data.available >= 0, "memory result ranges")
      testRoot.check(result.data && (result.data.swapConfigured === true
        || result.data.swapConfigured === false || result.data.swapConfigured === null), "swap state type")
      testRoot.next()
    }

    onFailedServicesCompleted: function(result) {
      testRoot.record(result)
      testRoot.check(testRoot.acceptable(result), "failed-services query should succeed, be empty, or be unavailable")
      testRoot.check(result.data && result.data.scopes && result.data.scopes.system.scope === "system",
        "system failed-unit scope")
      testRoot.check(result.data && result.data.scopes && result.data.scopes.user.scope === "user",
        "user failed-unit scope")
      testRoot.check(result.data && Array.isArray(result.data.units), "failed-unit records array")
      testRoot.next()
    }

    onSystemdSystemStateCompleted: function(result) {
      testRoot.record(result)
      testRoot.check(testRoot.acceptable(result), "systemd state should be observed or gracefully unavailable")
      if (result.status === "success")
        testRoot.check(result.data && typeof result.data.state === "string", "systemd state type")
      testRoot.next()
    }

    onDashboardSystemSnapshotCompleted: function(result) {
      testRoot.record(result)
      testRoot.check(result.status === "success", "dashboard system snapshot should retain usable system fields")
      testRoot.check(result.data && result.data.cpu && typeof result.data.cpu.usagePercent === "number",
        "dashboard CPU")
      testRoot.check(result.data && result.data.memory && result.data.memory.total > 0, "dashboard memory")
      testRoot.check(result.data && result.data.uptime && result.data.uptime.seconds >= 0, "dashboard uptime")
      testRoot.check(result.data && result.data.rootStorage && result.data.rootStorage.target === "/",
        "dashboard root storage")
      testRoot.check(result.data && result.data.failedServices && result.data.failedServices.scopes,
        "dashboard failed-service scopes")
      if (testRoot.phase === 7)
        testRoot.check(testRoot.replacementSecondGeneration > testRoot.replacementFirstGeneration,
          "new dashboard refresh should advance the generation")
      testRoot.next()
    }
  }

  Timer {
    id: replacementTimer
    interval: 50
    repeat: false
    onTriggered: testRoot.replacementSecondGeneration = service.refreshDashboardSystemSnapshot()
  }

  Timer {
    id: cancelTimer
    interval: 30
    repeat: false
    onTriggered: service.cancelSystemOverview()
  }

  Timer {
    interval: 30000
    running: true
    repeat: false
    onTriggered: {
      console.error("FAIL: watchdog expired at phase " + testRoot.phase)
      service.cancelAll()
      Qt.quit()
    }
  }

  Component.onCompleted: next()
}
