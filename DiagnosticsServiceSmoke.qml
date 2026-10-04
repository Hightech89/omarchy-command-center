import QtQuick
import Quickshell
import "services"

// Synthetic diagnostic smoke: no external DNS or ICMP packets.
ShellRoot {
  id: testRoot
  property int failures: 0
  property int phase: 0
  function check(ok, message) { if (!ok) { failures++; console.error("FAIL: " + message) } }
  QtObject {
    id: systemMock
    signal systemOverviewCompleted(var result)
    signal failedServicesCompleted(var result)
    signal systemdSystemStateCompleted(var result)
    function refreshSystemOverview() { Qt.callLater(function() { systemOverviewCompleted({ status: "success", serviceGeneration: 1, data: {
      cpu: { usagePercent: 72, logicalProcessors: 2 }, load: { one: 1, five: 1, fifteen: 1 },
      memory: { total: 1000, available: 500, used: 500 }, rootStorage: { usePercent: 50, target: "/" }, components: {}
    } }) }); return 1 }
    function refreshFailedServices() { Qt.callLater(function() { failedServicesCompleted({ status: "success", serviceGeneration: 1, data: { scopes: {
      system: { status: "success", count: 0 }, user: { status: "success", count: 0 }
    } } }) }); return 1 }
    function refreshSystemdSystemState() { Qt.callLater(function() { systemdSystemStateCompleted({ status: "success", serviceGeneration: 1, data: { state: "running" } }) }); return 1 }
    function cancelSystemOverview() {}
    function cancelFailedServices() {}
    function cancelSystemdSystemState() {}
  }
  QtObject {
    id: networkMock
    signal networkOverviewCompleted(var result)
    signal pingCompleted(var result)
    signal dnsCompleted(var result)
    property var pings: []
    function refreshNetworkOverview() { Qt.callLater(function() { networkOverviewCompleted({ status: "success", serviceGeneration: 1, data: {
      connectionState: "connected-local", primaryInterface: { name: "eth0", operationalState: "UP" },
      route: { interfaceName: "eth0", gateway: "192.0.2.1", family: "ipv4", metric: 1 },
      ipv4: ["192.0.2.2"], ipv6: [], linkLocal: []
    } }) }); return 1 }
    function pingHost(target) {
      pings = pings.concat([target])
      var generation = pings.length
      Qt.callLater(function() { pingCompleted({ status: "success", serviceGeneration: generation, data: { replied: target === "1.1.1.1" } }) })
      return pings.length
    }
    function lookupDns(name) { Qt.callLater(function() { dnsCompleted({ status: "success", serviceGeneration: 1, data: { ipv4: ["93.184.215.14"], ipv6: [] } }) }); return 1 }
    function cancelNetworkOverview() {}
    function cancelPing() {}
    function cancelDns() {}
  }
  DiagnosticsService { id: diagnostic; systemService: systemMock; networkService: networkMock }
  Connections {
    target: diagnostic
    function onRunningChanged() {
      if (diagnostic.running) return
      if (testRoot.phase === 1) {
        testRoot.check(diagnostic.systemHealthResult.status === "warning", "system threshold interpretation")
        testRoot.phase = 2
        Qt.callLater(function() { diagnostic.startNetworkDiagnostic() })
      } else if (testRoot.phase === 2) {
        testRoot.check(diagnostic.networkDiagnosticResult.status === "warning", "gateway no-response stays warning")
        testRoot.check(diagnostic.networkDiagnosticResult.stages[4].status === "healthy", "DNS succeeds")
        testRoot.check(diagnostic.networkDiagnosticResult.stages[5].status === "healthy", "public ICMP succeeds")
        testRoot.check(JSON.stringify(networkMock.pings) === JSON.stringify(["192.0.2.1", "1.1.1.1"]), "stop after first public success")
        testRoot.phase = 3
        Qt.callLater(function() { diagnostic.startNetworkDiagnostic(); diagnostic.cancel() })
      } else if (testRoot.phase === 3) {
        testRoot.phase = 4
        var canceledResult = JSON.stringify(diagnostic.networkDiagnosticResult)
        Qt.callLater(function() {
          testRoot.check(!diagnostic.running, "canceled run remains inactive")
          testRoot.check(JSON.stringify(diagnostic.networkDiagnosticResult) === canceledResult, "late overview does not update canceled run")
          console.log(testRoot.failures ? "DIAGNOSTICS_SERVICE_SMOKE_FAIL=" + testRoot.failures : "DIAGNOSTICS_SERVICE_SMOKE_PASS")
          Qt.quit()
        })
      }
    }
  }
  Timer { interval: 10000; running: true; repeat: false; onTriggered: { console.error("DIAGNOSTICS_SERVICE_SMOKE_TIMEOUT"); Qt.quit() } }
  Component.onCompleted: { phase = 1; diagnostic.startSystemHealth() }
}
