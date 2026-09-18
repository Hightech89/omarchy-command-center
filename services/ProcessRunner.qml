import QtQuick
import Quickshell
import Quickshell.Io

import "../parsers/Result.js" as Result

// Internal, bounded process primitive. Callers must supply code-owned request
// definitions; this type deliberately has no API that accepts shell text.
Scope {
  id: root

  readonly property int snapshotStdoutMaxBytes: 1024 * 1024
  readonly property int stderrMaxBytes: 32 * 1024
  readonly property int streamMaxRows: 10000
  readonly property int streamMaxBytes: 2 * 1024 * 1024
  readonly property int maximumTimeoutMs: 60000
  readonly property int terminationGraceMs: 500
  readonly property int postExitDrainMs: 100

  readonly property double runId: _currentRunId
  readonly property string state: _state
  readonly property var result: _result
  readonly property bool busy: _active !== null || _pending !== null
  readonly property bool processRunning: nativeProcess.running

  // completed is emitted once for every accepted, rejected, replaced, timed
  // out, or canceled request. rowAccepted is emitted only for bounded rows in
  // outputMode "lines" and never after a run becomes stale.
  signal completed(var executionResult)
  signal rowAccepted(double runId, string row)

  property double _nextRunId: 0
  property double _currentRunId: 0
  property string _state: "idle"
  property var _result: null
  property var _active: null
  property var _pending: null
  property double _processRunId: 0
  property bool _destroying: false

  function _nowIso() {
    return new Date().toISOString()
  }

  function _nextId() {
    // A QML double preserves integer precision through Number.MAX_SAFE_INTEGER,
    // unlike a QML int which would wrap after about two billion requests.
    _nextRunId += 1
    return _nextRunId
  }

  function _failure(message) {
    return { ok: false, message: message }
  }

  function _validateRequest(request, id) {
    if (!request || typeof request !== "object" || Array.isArray(request))
      return _failure("Process request must be an object.")
    if (request.command !== undefined)
      return _failure("Shell commands and command strings are not accepted.")

    var actionId = request.actionId
    if (typeof actionId !== "string" || actionId.length < 1 || actionId.length > 128
        || /[\x00-\x1F\x7F]/.test(actionId))
      return _failure("Process request needs a valid actionId.")

    var executable = request.executable
    if (typeof executable !== "string" || executable.length < 2 || executable.length > 4096
        || executable.charAt(0) !== "/" || /[\x00-\x1F\x7F]/.test(executable))
      return _failure("Executable must be an absolute path.")

    var args = request.arguments === undefined ? [] : request.arguments
    if (!Array.isArray(args))
      return _failure("Process arguments must be an array.")
    if (args.length > 256)
      return _failure("Process argument count exceeds the internal safety limit.")
    var copiedArgs = []
    var argumentCharacters = 0
    for (var index = 0; index < args.length; index++) {
      if (typeof args[index] !== "string" || args[index].length > 4096
          || args[index].indexOf("\x00") !== -1)
        return _failure("Every process argument must be a string without NUL bytes.")
      argumentCharacters += args[index].length
      if (argumentCharacters > 65536)
        return _failure("Process arguments exceed the internal safety limit.")
      copiedArgs.push(args[index])
    }

    var outputMode = request.outputMode === undefined ? "collect" : request.outputMode
    if (outputMode !== "collect" && outputMode !== "lines")
      return _failure("outputMode must be collect or lines.")

    var timeoutMs = request.timeoutMs === undefined ? 2000 : request.timeoutMs
    if (typeof timeoutMs !== "number" || !Number.isSafeInteger(timeoutMs)
        || timeoutMs < 1 || timeoutMs > maximumTimeoutMs)
      return _failure("timeoutMs must be an integer between 1 and " + maximumTimeoutMs + ".")

    return {
      ok: true,
      record: {
        runId: id,
        actionId: actionId,
        executable: executable,
        arguments: copiedArgs,
        outputMode: outputMode,
        timeoutMs: timeoutMs,
        state: "queued",
        startedAt: null,
        finishedAt: null,
        processStarted: false,
        processExited: false,
        stdoutState: "pending",
        stderrState: "pending",
        stdout: "",
        stderr: "",
        rows: [],
        stdoutBytes: 0,
        stderrBytes: 0,
        stdoutCollectorLength: 0,
        stderrCollectorLength: 0,
        lineRemainder: "",
        exitCode: null,
        exitStatus: null,
        timedOut: false,
        canceled: false,
        stale: false,
        terminalStatus: "",
        reason: "",
        message: "",
        published: false
      }
    }
  }

  function _loadingResult(record) {
    return Result.loading(record.actionId, {
      message: record.state === "queued" ? "Queued" : "Running",
      observedAt: _nowIso()
    })
  }

  function _snapshot(record) {
    return {
      runId: record.runId,
      state: record.terminalStatus === Result.Status.Success ? "complete" : record.terminalStatus,
      startedAt: record.startedAt,
      finishedAt: record.finishedAt,
      processStarted: record.processStarted,
      processExited: record.processExited,
      timedOut: record.timedOut,
      canceled: record.canceled,
      exitCode: record.exitCode,
      exitStatus: record.exitStatus,
      stdoutState: record.stdoutState,
      stderrState: record.stderrState,
      stdout: record.stdout,
      stderr: record.stderr,
      rows: record.rows.slice(),
      stdoutBytes: record.stdoutBytes,
      stderrBytes: record.stderrBytes
    }
  }

  function _outcome(record) {
    record.finishedAt = record.finishedAt || _nowIso()
    return Result.makeResult(record.actionId, record.terminalStatus, _snapshot(record), {
      message: record.message,
      reason: record.reason,
      source: { tool: record.executable },
      observedAt: record.finishedAt
    })
  }

  function _publish(record) {
    if (record.published)
      return
    record.published = true
    var outcome = _outcome(record)
    if (record.runId === _currentRunId) {
      _state = record.terminalStatus === Result.Status.Success ? "complete" : record.terminalStatus
      _result = outcome
    }
    completed(outcome)
  }

  function _publishRejected(id, request, message) {
    var actionId = request && typeof request.actionId === "string" ? request.actionId : "process.invalid"
    var record = {
      runId: id, actionId: actionId, executable: "", arguments: [], outputMode: "collect",
      state: "error", startedAt: null, finishedAt: _nowIso(), processStarted: false,
      processExited: false, stdoutState: "not-started", stderrState: "not-started",
      stdout: "", stderr: "", rows: [], stdoutBytes: 0, stderrBytes: 0,
      exitCode: null, exitStatus: null, timedOut: false, canceled: false,
      terminalStatus: Result.Status.Error, reason: "invalid-request", message: message,
      published: false
    }
    _publish(record)
  }

  function _cancelQueued(record, reason) {
    if (!record || record.published)
      return
    record.canceled = true
    record.stale = true
    record.stdoutState = "not-started"
    record.stderrState = "not-started"
    record.terminalStatus = Result.Status.Canceled
    record.reason = reason
    record.message = reason === "replaced" ? "Replaced by a newer request." : "Canceled."
    _publish(record)
  }

  // Starts a request and returns its monotonic runId. A newer call replaces
  // the active or queued request; only one newest replacement is retained.
  function run(request) {
    if (_destroying)
      return 0

    var id = _nextId()
    _currentRunId = id
    var checked = _validateRequest(request, id)

    if (_pending !== null) {
      var superseded = _pending
      _pending = null
      _cancelQueued(superseded, "replaced")
    }

    if (!checked.ok) {
      if (_active !== null)
        _cancelActive("replaced")
      _state = "error"
      _publishRejected(id, request, checked.message)
      return id
    }

    var record = checked.record
    _state = "queued"
    _result = _loadingResult(record)
    if (_active !== null) {
      _pending = record
      _cancelActive("replaced")
    } else {
      _launch(record)
    }
    return id
  }

  // Cancels both the visible queued request and any child still draining.
  function cancel() {
    if (_destroying)
      return
    if (_pending !== null) {
      var queued = _pending
      _pending = null
      _cancelQueued(queued, "canceled")
    }
    if (_active !== null)
      _cancelActive("canceled")
  }

  function _launch(record) {
    if (_destroying)
      return
    _active = record
    _processRunId = record.runId
    record.state = "queued"
    record.stdoutCollectorLength = 0
    record.stderrCollectorLength = 0

    nativeProcess.stdout = record.outputMode === "lines" ? stdoutChunks : stdoutCollector
    nativeProcess.stderr = stderrCollector
    nativeProcess.command = [record.executable].concat(record.arguments)
    // Keep the desktop/session environment (notably DBus and XDG variables),
    // while making all text parsing deterministic. Values are fixed here and
    // cannot be supplied by UI input or request objects.
    nativeProcess.environment = ({
      LC_ALL: "C",
      LANG: "C",
      SYSTEMD_COLORS: "0",
      SYSTEMD_PAGER: "cat"
    })
    nativeProcess.clearEnvironment = false
    timeoutTimer.armedRunId = record.runId
    timeoutTimer.interval = record.timeoutMs
    timeoutTimer.restart()
    nativeProcess.running = true
  }

  function _activeRecord(id) {
    return _active !== null && _active.runId === id ? _active : null
  }

  function _setRunningVisible(record) {
    if (!record.stale && record.runId === _currentRunId) {
      _state = record.state
      _result = _loadingResult(record)
    }
  }

  function _handleStarted(id) {
    var record = _activeRecord(id)
    if (record === null)
      return
    record.processStarted = true
    record.startedAt = _nowIso()
    record.state = "running"
    if (record.stale) {
      _terminate(record)
      return
    }
    _setRunningVisible(record)
  }

  function _utf8Length(text, stopAfter) {
    var bytes = 0
    for (var index = 0; index < text.length; index++) {
      var code = text.charCodeAt(index)
      if (code < 0x80) bytes += 1
      else if (code < 0x800) bytes += 2
      else if (code >= 0xD800 && code <= 0xDBFF && index + 1 < text.length
               && text.charCodeAt(index + 1) >= 0xDC00 && text.charCodeAt(index + 1) <= 0xDFFF) {
        bytes += 4
        index += 1
      } else bytes += 3
      if (bytes > stopAfter)
        return bytes
    }
    return bytes
  }

  function _collectorDelta(text, previousLength) {
    // StdioCollector replaces its exposed buffer for each new process. A
    // shorter value therefore starts a new buffer rather than being a splice.
    return text.slice(previousLength <= text.length ? previousLength : 0)
  }

  function _handleStdoutChanged(id) {
    var record = _activeRecord(id)
    if (record === null || record.stale || record.outputMode !== "collect")
      return
    var text = String(stdoutCollector.text || "")
    var delta = _collectorDelta(text, record.stdoutCollectorLength)
    record.stdoutCollectorLength = text.length
    var remaining = snapshotStdoutMaxBytes - record.stdoutBytes
    var added = _utf8Length(delta, remaining)
    if (added > remaining) {
      _outputLimit(record, "stdout exceeded the 1 MiB snapshot limit.")
      return
    }
    record.stdout += delta
    record.stdoutBytes += added
  }

  function _handleStderrChanged(id) {
    var record = _activeRecord(id)
    if (record === null || record.stale)
      return
    var text = String(stderrCollector.text || "")
    var delta = _collectorDelta(text, record.stderrCollectorLength)
    record.stderrCollectorLength = text.length
    var remaining = stderrMaxBytes - record.stderrBytes
    var added = _utf8Length(delta, remaining)
    if (added > remaining) {
      _outputLimit(record, "stderr exceeded the 32 KiB retention limit.")
      return
    }
    record.stderr += delta
    record.stderrBytes += added
  }

  function _handleLineChunk(id, chunk) {
    var record = _activeRecord(id)
    if (record === null || record.stale || record.outputMode !== "lines")
      return
    var text = String(chunk || "")
    var remaining = streamMaxBytes - record.stdoutBytes
    var added = _utf8Length(text, remaining)
    if (added > remaining) {
      _outputLimit(record, "stdout exceeded the 2 MiB stream limit.")
      return
    }
    record.stdoutBytes += added

    var combined = String(record.lineRemainder) + text
    // The value is a JavaScript string; Qt 6.10's static analyzer loses that
    // type through the var-backed record even though the runtime API is valid.
    // qmllint disable missing-property
    var parts = combined.split("\n")
    // qmllint enable missing-property
    record.lineRemainder = parts.pop()
    for (var index = 0; index < parts.length; index++) {
      if (record.rows.length >= streamMaxRows) {
        _outputLimit(record, "stdout exceeded the 10,000 row stream limit.")
        return
      }
      var row = parts[index]
      if (row.length > 0 && row.charAt(row.length - 1) === "\r")
        row = row.slice(0, -1)
      record.rows.push(row)
      rowAccepted(record.runId, row)
    }
  }

  function _flushFinalLine(record) {
    if (record.outputMode !== "lines" || record.stale || record.lineRemainder === "")
      return
    if (record.rows.length >= streamMaxRows) {
      _outputLimit(record, "stdout exceeded the 10,000 row stream limit.")
      return
    }
    var row = record.lineRemainder
    if (row.length > 0 && row.charAt(row.length - 1) === "\r")
      row = row.slice(0, -1)
    record.lineRemainder = ""
    record.rows.push(row)
    rowAccepted(record.runId, row)
  }

  function _handleStdoutFinished(id) {
    var record = _activeRecord(id)
    if (record === null || record.outputMode !== "collect")
      return
    record.stdoutState = "settled"
    _maybeFinalize(record)
  }

  function _handleStderrFinished(id) {
    var record = _activeRecord(id)
    if (record === null)
      return
    record.stderrState = "settled"
    _maybeFinalize(record)
  }

  function _classifyExit(record, exitCode, exitStatus) {
    if (record.terminalStatus !== "")
      return
    if (exitStatus !== 0) {
      record.terminalStatus = Result.Status.Error
      record.reason = "process-crashed"
      record.message = "Process ended abnormally."
    } else if (exitCode !== 0) {
      record.terminalStatus = Result.Status.Error
      record.reason = "nonzero-exit"
      record.message = "Process exited with status " + exitCode + "."
    } else {
      record.terminalStatus = Result.Status.Success
      record.message = "Process completed."
    }
  }

  function _handleExited(id, exitCode, exitStatus) {
    var record = _activeRecord(id)
    if (record === null)
      return
    timeoutTimer.stop()
    if (killTimer.armedRunId === record.runId)
      killTimer.stop()
    record.processExited = true
    record.exitCode = exitCode
    record.exitStatus = exitStatus
    record.state = "settling"

    // Quickshell 0.3.1's Process::onFinished calls SplitParser::streamEnded
    // synchronously before emitting exited. SplitParser has no finished signal,
    // so this is the verified settlement point for line/chunk mode.
    if (record.outputMode === "lines") {
      _flushFinalLine(record)
      record.stdoutState = "settled"
    }
    _classifyExit(record, exitCode, exitStatus)
    if (!record.stale)
      _setRunningVisible(record)

    if (record.stdoutState !== "settled" || record.stderrState !== "settled") {
      drainTimer.armedRunId = record.runId
      drainTimer.restart()
    }
    _maybeFinalize(record)
  }

  function _handleRunningChanged(id) {
    var record = _activeRecord(id)
    if (record === null || nativeProcess.running || record.processExited)
      return

    timeoutTimer.stop()
    if (killTimer.armedRunId === record.runId)
      killTimer.stop()
    record.processExited = true
    record.stdoutState = "settled"
    record.stderrState = "settled"
    if (record.terminalStatus === "") {
      record.terminalStatus = record.processStarted ? Result.Status.Error : Result.Status.Unavailable
      record.reason = record.processStarted ? "missing-exit-signal" : "launch-failed"
      record.message = record.processStarted
        ? "Process stopped without an exit result."
        : "Executable could not be started: " + record.executable
    }
    _maybeFinalize(record)
  }

  function _outputLimit(record, message) {
    if (record.terminalStatus !== "")
      return
    record.stale = true
    record.terminalStatus = Result.Status.Error
    record.reason = "output-limit"
    record.message = message
    _publish(record)
    _terminate(record)
  }

  function _timeout(record) {
    if (record.terminalStatus !== "")
      return
    record.timedOut = true
    record.stale = true
    record.terminalStatus = Result.Status.Timeout
    record.reason = "timeout"
    record.message = "Process timed out."
    _publish(record)
    _terminate(record)
  }

  function _cancelActive(reason) {
    var record = _active
    if (record === null || record.terminalStatus !== "")
      return
    record.canceled = true
    record.stale = true
    record.terminalStatus = Result.Status.Canceled
    record.reason = reason
    record.message = reason === "replaced" ? "Replaced by a newer request." : "Canceled."
    _publish(record)
    _terminate(record)
  }

  function _terminate(record) {
    timeoutTimer.stop()
    if (!nativeProcess.running) {
      _handleRunningChanged(record.runId)
      return
    }
    killTimer.armedRunId = record.runId
    killTimer.armedPid = String(nativeProcess.processId === null ? "" : nativeProcess.processId)
    nativeProcess.running = false
    killTimer.restart()
  }

  function _maybeFinalize(record) {
    if (record !== _active || !record.processExited
        || record.stdoutState === "pending" || record.stderrState === "pending")
      return
    timeoutTimer.stop()
    drainTimer.stop()
    if (killTimer.armedRunId === record.runId)
      killTimer.stop()
    if (record.terminalStatus === "") {
      record.terminalStatus = Result.Status.Error
      record.reason = "incomplete-lifecycle"
      record.message = "Process lifecycle ended incompletely."
    }
    _publish(record)
    _active = null
    _processRunId = 0

    if (_pending !== null && !_destroying) {
      var replacement = _pending
      _pending = null
      Qt.callLater(function() {
        if (!_destroying && _active === null && replacement.runId === _currentRunId)
          _launch(replacement)
      })
    }
  }

  function shutdown() {
    if (_destroying)
      return
    _destroying = true
    timeoutTimer.stop()
    drainTimer.stop()
    killTimer.stop()
    if (_pending !== null) {
      _pending.stale = true
      _pending = null
    }
    if (_active !== null) {
      _active.stale = true
      _active.canceled = true
      nativeProcess.running = false
      if (nativeProcess.running)
        nativeProcess.signal(9)
    }
  }

  Process {
    id: nativeProcess
    running: false
    command: []
    clearEnvironment: false

    onStarted: root._handleStarted(root._processRunId)
    // The static analyzer cannot resolve QProcess::ExitStatus from the
    // installed Quickshell metadata, although the runtime signal is valid.
    // qmllint disable signal-handler-parameters
    onExited: function(exitCode, exitStatus) {
      root._handleExited(root._processRunId, exitCode, exitStatus)
    }
    // qmllint enable signal-handler-parameters
    onRunningChanged: root._handleRunningChanged(root._processRunId)
  }

  StdioCollector {
    id: stdoutCollector
    waitForEnd: false
    onDataChanged: root._handleStdoutChanged(root._processRunId)
    onStreamFinished: root._handleStdoutFinished(root._processRunId)
  }

  // An empty marker is a verified Quickshell 0.3.1 raw-chunk mode: every
  // readyRead buffer is emitted immediately and no unterminated row is held in
  // SplitParser's native buffer. QML performs the bounded line split instead.
  SplitParser {
    id: stdoutChunks
    splitMarker: ""
    onRead: function(chunk) { root._handleLineChunk(root._processRunId, chunk) }
  }

  StdioCollector {
    id: stderrCollector
    waitForEnd: false
    onDataChanged: root._handleStderrChanged(root._processRunId)
    onStreamFinished: root._handleStderrFinished(root._processRunId)
  }

  Timer {
    id: timeoutTimer
    property double armedRunId: 0
    repeat: false
    onTriggered: {
      var record = root._activeRecord(armedRunId)
      if (record !== null && !record.processExited)
        root._timeout(record)
    }
  }

  Timer {
    id: killTimer
    property double armedRunId: 0
    property string armedPid: ""
    interval: root.terminationGraceMs
    repeat: false
    onTriggered: {
      var record = root._activeRecord(armedRunId)
      if (record !== null && nativeProcess.running
          && root._processRunId === armedRunId
          && String(nativeProcess.processId === null ? "" : nativeProcess.processId) === armedPid)
        nativeProcess.signal(9)
    }
  }

  Timer {
    id: drainTimer
    property double armedRunId: 0
    interval: root.postExitDrainMs
    repeat: false
    onTriggered: {
      var record = root._activeRecord(armedRunId)
      if (record === null || !record.processExited)
        return
      if (record.stdoutState === "pending")
        record.stdoutState = "drain-deadline"
      if (record.stderrState === "pending")
        record.stderrState = "drain-deadline"
      root._maybeFinalize(record)
    }
  }

  Component.onDestruction: shutdown()
}
