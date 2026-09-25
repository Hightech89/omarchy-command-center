import QtQuick
import Quickshell
import "services"

// Headless read-only smoke test. It emits statuses only and uses loopback for
// Ping integration; it performs no public-host probe or DNS lookup.
ShellRoot {
  id: testRoot
  property int phase: 0
  property int failures: 0
  property var statuses: []
  property int replacementFirstGeneration: 0
  property int replacementSecondGeneration: 0

  function check(condition, message) { if (!condition) { failures += 1; console.error("FAIL: " + message) } }
  function next() { phase += 1; Qt.callLater(startPhase) }
  function record(result) { statuses.push(result.status + "/" + result.completeness) }
  function startPhase() {
    if (phase === 1) service.refreshNetworkOverview()
    else if (phase === 2) service.refreshListeningPorts()
    else if (phase === 3) service.pingHost("-unsafe")
    else if (phase === 4) service.lookupDns("192.0.2.1")
    else if (phase === 5) service.pingHost("127.0.0.1")
    else if (phase === 6) service.pingHost("::1")
    else if (phase === 7) {
      replacementFirstGeneration = service.pingHost("127.0.0.1")
      replacementTimer.restart()
    }
    else {
      console.log(failures === 0 ? "NETWORK_SERVICE_SMOKE_PASS statuses=" + statuses.join(",") : "NETWORK_SERVICE_SMOKE_FAIL=" + failures + " statuses=" + statuses.join(","))
      Qt.quit()
    }
  }

  NetworkService {
    id: service
    onNetworkOverviewCompleted: function(result) {
      testRoot.record(result)
      testRoot.check(result.status === "success", "network overview should return structured local state")
      testRoot.check(result.data && ["connected-local", "no-default-route", "interface-unavailable", "interface-down", "no-usable-address"].indexOf(result.data.connectionState) !== -1, "derived connection state")
      testRoot.next()
    }
    onListeningPortsCompleted: function(result) {
      testRoot.record(result)
      testRoot.check(result.status === "success" || result.status === "empty", "listening ports status")
      testRoot.check(result.data && Array.isArray(result.data.sockets), "structured socket records")
      testRoot.next()
    }
    onPingCompleted: function(result) {
      testRoot.record(result)
      if (testRoot.phase === 3) {
        testRoot.check(result.status === "error" && result.reason !== "", "invalid Ping rejected")
        testRoot.check(!service.busy, "invalid Ping launches no process")
      } else if (testRoot.phase === 5 || testRoot.phase === 6) {
        testRoot.check(result.status === "success" && result.data && result.data.replied, "loopback Ping replies")
        testRoot.check(result.data.target === (testRoot.phase === 5 ? "127.0.0.1" : "::1"), "Ping target preserved")
      } else {
        testRoot.check(result.status === "success" && result.data && result.data.target === "::1", "latest replacement target wins")
        testRoot.check(testRoot.replacementSecondGeneration > testRoot.replacementFirstGeneration, "Ping replacement advances generation")
      }
      testRoot.next()
    }
    onDnsCompleted: function(result) {
      testRoot.record(result)
      testRoot.check(result.status === "error" && result.reason === "dns-name-required", "invalid DNS IP rejected")
      testRoot.check(!service.busy, "invalid DNS launches no process")
      testRoot.next()
    }
  }

  Timer { id: replacementTimer; interval: 5; repeat: false; onTriggered: testRoot.replacementSecondGeneration = service.pingHost("::1") }

  Timer {
    interval: 20000
    running: true
    repeat: false
    onTriggered: { console.error("FAIL: watchdog expired at phase " + testRoot.phase); service.cancelAll(); Qt.quit() }
  }
  Component.onCompleted: next()
}
