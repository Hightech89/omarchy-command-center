import QtQuick
import Quickshell

import "services"

// Headless integration smoke test. Run from the repository root with:
//   qs --no-color -p ProcessRunnerSmoke.qml
ShellRoot {
  id: testRoot

  property int phase: 0
  property int failures: 0
  property double expectedRunId: 0
  property double replacedRunId: 0

  function check(condition, message) {
    if (!condition) {
      failures += 1
      console.error("FAIL: " + message)
    }
  }

  function advance() {
    phase += 1
    Qt.callLater(startPhase)
  }

  function startPhase() {
    var request = null
    if (phase === 1)
      request = { actionId: "smoke.stdout", executable: "/usr/bin/printf", arguments: ["hello\n"], timeoutMs: 1000 }
    else if (phase === 2)
      request = { actionId: "smoke.lines", executable: "/usr/bin/printf", arguments: ["one\ntwo\nlast"], outputMode: "lines", timeoutMs: 1000 }
    else if (phase === 3)
      request = { actionId: "smoke.nonzero", executable: "/usr/bin/env", arguments: ["--definitely-invalid"], timeoutMs: 1000 }
    else if (phase === 4)
      request = { actionId: "smoke.timeout", executable: "/usr/bin/sleep", arguments: ["2"], timeoutMs: 50 }
    else if (phase === 5) {
      expectedRunId = runner.run({ actionId: "smoke.cancel", executable: "/usr/bin/sleep", arguments: ["2"], timeoutMs: 1000 })
      actionTimer.action = "cancel"
      actionTimer.restart()
      return
    } else if (phase === 6) {
      replacedRunId = runner.run({ actionId: "smoke.replaced", executable: "/usr/bin/sleep", arguments: ["2"], timeoutMs: 1000 })
      actionTimer.action = "replace"
      actionTimer.restart()
      return
    } else if (phase === 7)
      request = { actionId: "smoke.output-limit", executable: "/usr/bin/yes", arguments: [], outputMode: "lines", timeoutMs: 3000 }
    else if (phase === 8)
      request = { actionId: "smoke.snapshot-limit", executable: "/usr/bin/yes", arguments: [], timeoutMs: 3000 }
    else if (phase === 9) {
      var missingPaths = []
      var longPart = "x".repeat(390)
      for (var index = 0; index < 100; index++)
        missingPaths.push("/tmp/command-center-smoke-missing-" + index + "-" + longPart)
      request = { actionId: "smoke.stderr-limit", executable: "/usr/bin/ls", arguments: missingPaths, timeoutMs: 3000 }
    } else if (phase === 10)
      request = { actionId: "smoke.missing", executable: "/usr/bin/command-center-does-not-exist", arguments: [], timeoutMs: 500 }
    else if (phase === 11)
      request = { actionId: "smoke.invalid", executable: "printf", arguments: ["bad"] }
    else if (phase === 12)
      request = { actionId: "smoke.command-string", command: "/usr/bin/printf unsafe" }
    else {
      check(runner.state === "error", "final malformed request should remain an error")
      check(!runner.processRunning, "runner should be idle after all cases")
      console.log(failures === 0 ? "PROCESS_RUNNER_SMOKE_PASS" : "PROCESS_RUNNER_SMOKE_FAIL=" + failures)
      Qt.quit()
      return
    }
    expectedRunId = runner.run(request)
  }

  ProcessRunner {
    id: runner

    onCompleted: function(outcome) {
      var execution = outcome.data
      if (outcome.actionId === "smoke.replaced") {
        testRoot.check(outcome.status === "canceled", "replaced request should be canceled")
        testRoot.check(execution.runId === testRoot.replacedRunId, "replaced runId should be preserved")
        return
      }

      if (outcome.actionId !== "smoke.invalid" && outcome.actionId !== "smoke.command-string")
        testRoot.check(execution && execution.runId === testRoot.expectedRunId,
                       outcome.actionId + " should match the current generation")
      if (outcome.actionId === "smoke.stdout") {
        testRoot.check(outcome.status === "success" && execution.stdout === "hello\n", "stdout capture")
        testRoot.check(execution.stdoutState === "settled" && execution.stderrState === "settled", "stream settlement")
      } else if (outcome.actionId === "smoke.lines") {
        testRoot.check(outcome.status === "success" && JSON.stringify(execution.rows) === JSON.stringify(["one", "two", "last"]), "row capture")
      } else if (outcome.actionId === "smoke.nonzero") {
        testRoot.check(outcome.status === "error" && outcome.reason === "nonzero-exit", "nonzero classification")
        testRoot.check(execution.stderr.length > 0, "stderr capture")
      } else if (outcome.actionId === "smoke.timeout")
        testRoot.check(outcome.status === "timeout" && execution.timedOut, "timeout classification")
      else if (outcome.actionId === "smoke.cancel")
        testRoot.check(outcome.status === "canceled" && execution.canceled, "cancel classification")
      else if (outcome.actionId === "smoke.replacement-winner")
        testRoot.check(outcome.status === "success" && execution.stdout === "newest", "latest request wins")
      else if (outcome.actionId === "smoke.output-limit") {
        testRoot.check(outcome.status === "error" && outcome.reason === "output-limit", "output-limit classification")
        testRoot.check(execution.rows.length <= runner.streamMaxRows && execution.stdoutBytes <= runner.streamMaxBytes, "bounded stream retention")
      } else if (outcome.actionId === "smoke.snapshot-limit") {
        testRoot.check(outcome.status === "error" && outcome.reason === "output-limit", "snapshot output-limit classification")
        testRoot.check(execution.stdoutBytes <= runner.snapshotStdoutMaxBytes, "bounded snapshot retention")
      } else if (outcome.actionId === "smoke.stderr-limit") {
        testRoot.check(outcome.status === "error" && outcome.reason === "output-limit", "stderr output-limit classification")
        testRoot.check(execution.stderrBytes <= runner.stderrMaxBytes, "bounded stderr retention")
      } else if (outcome.actionId === "smoke.missing")
        testRoot.check(outcome.status === "unavailable" && outcome.reason === "launch-failed", "launch failure classification")
      else if (outcome.actionId === "smoke.invalid" || outcome.actionId === "smoke.command-string")
        testRoot.check(outcome.status === "error" && outcome.reason === "invalid-request", "request rejection")
      testRoot.advance()
    }
  }

  Timer {
    id: actionTimer
    property string action: ""
    interval: 30
    repeat: false
    onTriggered: {
      if (action === "cancel") runner.cancel()
      else {
        testRoot.expectedRunId = runner.run({ actionId: "smoke.replacement-winner", executable: "/usr/bin/printf", arguments: ["newest"], timeoutMs: 1000 })
      }
    }
  }

  Timer {
    interval: 10000
    running: true
    repeat: false
    onTriggered: {
      console.error("FAIL: watchdog expired at phase " + testRoot.phase)
      Qt.quit()
    }
  }

  Component.onCompleted: advance()
}
