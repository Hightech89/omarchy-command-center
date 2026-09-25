import QtQuick
import Quickshell

import "../parsers/Result.js" as Result
import "../parsers/SystemParsers.js" as SystemParsers

// Read-only system snapshot service. Its public API accepts refresh/cancel
// intent only; every executable, argument, timeout, and parser is fixed here.
Scope {
  id: root

  readonly property var systemOverviewResult: _systemOverviewResult
  readonly property var diskUsageResult: _diskUsageResult
  readonly property var memoryUsageResult: _memoryUsageResult
  readonly property var failedServicesResult: _failedServicesResult
  readonly property var dashboardSystemSnapshotResult: _dashboardSystemSnapshotResult
  readonly property var dashboardLiveSnapshotResult: _dashboardLiveSnapshotResult
  readonly property var dashboardCpuSnapshotResult: _dashboardCpuSnapshotResult
  readonly property var dashboardInventorySnapshotResult: _dashboardInventorySnapshotResult
  readonly property var systemdSystemStateResult: _systemdSystemStateResult
  readonly property bool busy: runner0.busy || runner1.busy || runner2.busy || runner3.busy || _queue.length > 0

  signal systemOverviewCompleted(var result)
  signal diskUsageCompleted(var result)
  signal memoryUsageCompleted(var result)
  signal failedServicesCompleted(var result)
  signal dashboardSystemSnapshotCompleted(var result)
  signal systemdSystemStateCompleted(var result)

  property var _systemOverviewResult: _notRefreshed("system.overview")
  property var _diskUsageResult: _notRefreshed("system.disk-usage")
  property var _memoryUsageResult: _notRefreshed("system.memory-usage")
  property var _failedServicesResult: _notRefreshed("system.failed-services")
  property var _dashboardSystemSnapshotResult: _notRefreshed("dashboard.system")
  property var _dashboardLiveSnapshotResult: _notRefreshed("dashboard.live")
  property var _dashboardCpuSnapshotResult: _notRefreshed("dashboard.cpu")
  property var _dashboardInventorySnapshotResult: _notRefreshed("dashboard.inventory")
  property var _systemdSystemStateResult: _notRefreshed("system.systemd-state")

  property int _overviewGeneration: 0
  property int _diskGeneration: 0
  property int _memoryGeneration: 0
  property int _failedGeneration: 0
  property int _dashboardGeneration: 0
  property int _dashboardLiveGeneration: 0
  property int _dashboardCpuGeneration: 0
  property int _dashboardInventoryGeneration: 0
  property int _stateGeneration: 0

  property var _overviewContext: null
  property var _diskContext: null
  property var _memoryContext: null
  property var _failedContext: null
  property var _dashboardContext: null
  property var _dashboardLiveContext: null
  property var _dashboardCpuSnapshotContext: null
  property var _dashboardInventoryContext: null
  property var _stateContext: null
  property var _overviewCpuContext: null
  property var _dashboardCpuContext: null
  property var _queue: []
  property var _runnerJobs: [null, null, null, null]
  property bool _destroying: false

  function _nowIso() {
    return new Date().toISOString()
  }

  function _notRefreshed(actionId) {
    return Result.unavailable(actionId, "not-refreshed", {
      message: "This snapshot has not been refreshed yet."
    })
  }

  function _source(tool, displayCommand) {
    return { tool: tool, displayCommand: displayCommand }
  }

  function _request(kind) {
    if (kind === "hostname")
      return { actionId: "system.hostname", executable: "/usr/bin/cat", arguments: ["/proc/sys/kernel/hostname"], timeoutMs: 2000 }
    if (kind === "os-release")
      return { actionId: "system.os-release", executable: "/usr/bin/cat", arguments: ["/etc/os-release"], timeoutMs: 2000 }
    if (kind === "kernel-ostype")
      return { actionId: "system.kernel-ostype", executable: "/usr/bin/cat", arguments: ["/proc/sys/kernel/ostype"], timeoutMs: 2000 }
    if (kind === "kernel-release")
      return { actionId: "system.kernel-release", executable: "/usr/bin/cat", arguments: ["/proc/sys/kernel/osrelease"], timeoutMs: 2000 }
    if (kind === "cpuinfo")
      return { actionId: "system.cpuinfo", executable: "/usr/bin/cat", arguments: ["/proc/cpuinfo"], timeoutMs: 2000 }
    if (kind === "proc-stat-first" || kind === "proc-stat-second")
      return { actionId: "system.cpu-utilization", executable: "/usr/bin/cat", arguments: ["/proc/stat"], timeoutMs: 2000 }
    if (kind === "meminfo")
      return { actionId: "system.memory", executable: "/usr/bin/cat", arguments: ["/proc/meminfo"], timeoutMs: 2000 }
    if (kind === "uptime")
      return { actionId: "system.uptime", executable: "/usr/bin/cat", arguments: ["/proc/uptime"], timeoutMs: 2000 }
    if (kind === "loadavg")
      return { actionId: "system.load", executable: "/usr/bin/cat", arguments: ["/proc/loadavg"], timeoutMs: 2000 }
    if (kind === "root-findmnt")
      return {
        actionId: "system.root-storage",
        executable: "/usr/bin/findmnt",
        arguments: ["--json", "--bytes", "--df", "--target", "/", "--output", "SOURCE,FSTYPE,SIZE,USED,AVAIL,USE%,TARGET"],
        timeoutMs: 2000
      }
    if (kind === "disk-findmnt")
      return {
        actionId: "system.disk-usage",
        executable: "/usr/bin/findmnt",
        arguments: ["--json", "--bytes", "--df", "--real", "--output", "SOURCE,FSTYPE,SIZE,USED,AVAIL,USE%,TARGET,OPTIONS"],
        timeoutMs: 2000
      }
    if (kind === "failed-system")
      return {
        actionId: "system.failed-services.system",
        executable: "/usr/bin/systemctl",
        arguments: ["--system", "--failed", "--no-pager", "--no-legend", "--plain", "--output=json", "list-units"],
        timeoutMs: 3000
      }
    if (kind === "failed-user")
      return {
        actionId: "system.failed-services.user",
        executable: "/usr/bin/systemctl",
        arguments: ["--user", "--failed", "--no-pager", "--no-legend", "--plain", "--output=json", "list-units"],
        timeoutMs: 3000
      }
    if (kind === "systemd-state")
      return { actionId: "system.systemd-state", executable: "/usr/bin/systemctl", arguments: ["is-system-running"], timeoutMs: 3000 }
    return null
  }

  function _sourceFor(kind) {
    if (kind === "hostname") return _source("/usr/bin/cat", "cat /proc/sys/kernel/hostname")
    if (kind === "os-release") return _source("/usr/bin/cat", "cat /etc/os-release")
    if (kind === "kernel-ostype") return _source("/usr/bin/cat", "cat /proc/sys/kernel/ostype")
    if (kind === "kernel-release") return _source("/usr/bin/cat", "cat /proc/sys/kernel/osrelease")
    if (kind === "cpuinfo") return _source("/usr/bin/cat", "cat /proc/cpuinfo")
    if (kind === "proc-stat-first" || kind === "proc-stat-second") return _source("/usr/bin/cat", "cat /proc/stat (two samples)")
    if (kind === "meminfo") return _source("/usr/bin/cat", "cat /proc/meminfo")
    if (kind === "uptime") return _source("/usr/bin/cat", "cat /proc/uptime")
    if (kind === "loadavg") return _source("/usr/bin/cat", "cat /proc/loadavg")
    if (kind === "root-findmnt") return _source("/usr/bin/findmnt", "findmnt --json --bytes --df --target / --output SOURCE,FSTYPE,SIZE,USED,AVAIL,USE%,TARGET")
    if (kind === "disk-findmnt") return _source("/usr/bin/findmnt", "findmnt --json --bytes --df --real --output SOURCE,FSTYPE,SIZE,USED,AVAIL,USE%,TARGET,OPTIONS")
    if (kind === "failed-system") return _source("/usr/bin/systemctl", "systemctl --system --failed --no-pager --no-legend --plain --output=json list-units")
    if (kind === "failed-user") return _source("/usr/bin/systemctl", "systemctl --user --failed --no-pager --no-legend --plain --output=json list-units")
    return _source("/usr/bin/systemctl", "systemctl is-system-running")
  }

  function _runner(index) {
    if (index === 0) return runner0
    if (index === 1) return runner1
    if (index === 2) return runner2
    return runner3
  }

  function _context(feature) {
    if (feature === "overview") return _overviewContext
    if (feature === "disk") return _diskContext
    if (feature === "memory") return _memoryContext
    if (feature === "failed") return _failedContext
    if (feature === "dashboard") return _dashboardContext
    if (feature === "dashboardLive") return _dashboardLiveContext
    if (feature === "dashboardCpu") return _dashboardCpuSnapshotContext
    if (feature === "dashboardInventory") return _dashboardInventoryContext
    return _stateContext
  }

  function _setContext(feature, context) {
    if (feature === "overview") _overviewContext = context
    else if (feature === "disk") _diskContext = context
    else if (feature === "memory") _memoryContext = context
    else if (feature === "failed") _failedContext = context
    else if (feature === "dashboard") _dashboardContext = context
    else if (feature === "dashboardLive") _dashboardLiveContext = context
    else if (feature === "dashboardCpu") _dashboardCpuSnapshotContext = context
    else if (feature === "dashboardInventory") _dashboardInventoryContext = context
    else _stateContext = context
  }

  function _nextGeneration(feature) {
    if (feature === "overview") return ++_overviewGeneration
    if (feature === "disk") return ++_diskGeneration
    if (feature === "memory") return ++_memoryGeneration
    if (feature === "failed") return ++_failedGeneration
    if (feature === "dashboard") return ++_dashboardGeneration
    if (feature === "dashboardLive") return ++_dashboardLiveGeneration
    if (feature === "dashboardCpu") return ++_dashboardCpuGeneration
    if (feature === "dashboardInventory") return ++_dashboardInventoryGeneration
    return ++_stateGeneration
  }

  function _newContext(feature, actionId, componentCount) {
    _cancelFeatureWork(feature)
    var context = {
      feature: feature,
      actionId: actionId,
      generation: _nextGeneration(feature),
      remaining: componentCount,
      results: {},
      completedNames: {},
      firstCpu: null,
      firstCpuObservedAt: null,
      finished: false
    }
    _setContext(feature, context)
    _publishLoading(feature, actionId)
    return context
  }

  function _publishLoading(feature, actionId) {
    _publish(feature, Result.loading(actionId, { message: "Checking system data…", observedAt: _nowIso() }), false)
  }

  function _enqueue(context, kind, name) {
    if (_destroying || !context || context.finished || _context(context.feature) !== context)
      return
    _queue.push({ context: context, kind: kind, name: name, runId: 0 })
    _dispatch()
  }

  function _dispatch() {
    if (_destroying)
      return
    for (var index = 0; index < 4 && _queue.length > 0; index++) {
      var runner = _runner(index)
      if (runner.busy || _runnerJobs[index] !== null)
        continue
      var job = _queue.shift()
      if (!job.context.finished && _context(job.context.feature) === job.context) {
        var request = _request(job.kind)
        if (request === null) {
          _finishComponent(job.context, job.name, _componentFailure("error", "invalid-probe", "Internal probe definition is missing.", null))
          index -= 1
          continue
        }
        _runnerJobs[index] = job
        job.runId = runner.run(request)
      } else {
        index -= 1
      }
    }
  }

  function _runnerAvailable(index) {
    if (!_runner(index).busy && _runnerJobs[index] === null)
      _dispatch()
  }

  function _onRunnerCompleted(index, execution) {
    var job = _runnerJobs[index]
    if (job === null)
      return
    var executionRunId = execution && execution.data ? execution.data.runId : 0
    if (executionRunId !== job.runId)
      return
    _runnerJobs[index] = null
    if (!job.context.finished && _context(job.context.feature) === job.context)
      _handleJob(job, execution)
  }

  function _executionText(execution, stream) {
    if (!execution || !execution.data)
      return ""
    return String(execution.data[stream] || "")
  }

  function _managerUnavailable(execution) {
    if (execution.status === Result.Status.Unavailable)
      return true
    var detail = _executionText(execution, "stderr").toLowerCase()
    return detail.indexOf("permission denied") !== -1
      || detail.indexOf("operation not permitted") !== -1
      || detail.indexOf("failed to connect") !== -1
      || detail.indexOf("not been booted with systemd") !== -1
      || detail.indexOf("no such file or directory") !== -1
  }

  function _componentFailure(status, reason, message, source, observedAt) {
    return { status: status, data: null, reason: reason, message: message,
      source: source, observedAt: observedAt || _nowIso(), completeness: Result.Completeness.Complete,
      warnings: [] }
  }

  function _parseExecution(execution, kind) {
    var source = _sourceFor(kind)
    var allowNonzeroState = kind === "systemd-state"
      && execution.status === Result.Status.Error
      && execution.reason === "nonzero-exit"
      && _executionText(execution, "stdout").trim() !== ""
    if (execution.status !== Result.Status.Success && !allowNonzeroState) {
      if (execution.status === Result.Status.Unavailable)
        return _componentFailure(Result.Status.Unavailable, "command-missing",
          "The required read-only tool is unavailable: " + source.tool, source, execution.observedAt)
      if ((kind === "failed-system" || kind === "failed-user" || kind === "systemd-state")
          && _managerUnavailable(execution))
        return _componentFailure(Result.Status.Unavailable, "manager-unavailable",
          "The systemd manager is unavailable in this session.", source, execution.observedAt)
      return _componentFailure(execution.status, execution.reason || "execution-failed",
        execution.message || "The read-only probe failed.", source, execution.observedAt)
    }

    var text = _executionText(execution, "stdout")
    var parsed
    if (kind === "hostname") parsed = SystemParsers.parseHostname(text)
    else if (kind === "os-release") parsed = SystemParsers.parseOsRelease(text)
    else if (kind === "kernel-ostype" || kind === "kernel-release") parsed = SystemParsers.parseKernelText(text)
    else if (kind === "cpuinfo") parsed = SystemParsers.parseCpuinfo(text)
    else if (kind === "proc-stat-first" || kind === "proc-stat-second") parsed = SystemParsers.parseProcStat(text)
    else if (kind === "meminfo") parsed = SystemParsers.parseMeminfo(text)
    else if (kind === "uptime") parsed = SystemParsers.parseUptime(text)
    else if (kind === "loadavg") parsed = SystemParsers.parseLoadavg(text)
    else if (kind === "root-findmnt") parsed = SystemParsers.parseRootFindmntJson(text)
    else if (kind === "disk-findmnt") parsed = SystemParsers.parseDiskUsageFindmntJson(text)
    else if (kind === "failed-system") parsed = SystemParsers.parseFailedUnitsJson(text, "system")
    else if (kind === "failed-user") parsed = SystemParsers.parseFailedUnitsJson(text, "user")
    else parsed = SystemParsers.parseSystemdSystemState(text)

    if (!parsed.ok)
      return _componentFailure(Result.Status.Error, parsed.reason, parsed.message, source, execution.observedAt)
    if (kind === "systemd-state")
      parsed.data = { state: parsed.data.state,
        exitCode: execution.data && Number.isInteger(execution.data.exitCode) ? execution.data.exitCode : null }
    return { status: Result.Status.Success, data: parsed.data, reason: "", message: "",
      source: source, observedAt: execution.observedAt, completeness: parsed.completeness,
      warnings: parsed.warnings.slice() }
  }

  function _handleJob(job, execution) {
    var component = _parseExecution(execution, job.kind)
    if (job.kind === "proc-stat-first") {
      if (component.status !== Result.Status.Success) {
        _finishComponent(job.context, job.name, component)
        return
      }
      job.context.firstCpu = component.data
      job.context.firstCpuObservedAt = component.observedAt
      if (job.context.feature === "overview") {
        _overviewCpuContext = job.context
        overviewCpuTimer.restart()
      } else {
        _dashboardCpuContext = job.context
        dashboardCpuTimer.restart()
      }
      return
    }
    if (job.kind === "proc-stat-second" && component.status === Result.Status.Success) {
      var utilization = SystemParsers.calculateCpuUsage(job.context.firstCpu, component.data)
      if (!utilization.ok) {
        component = _componentFailure(Result.Status.Error, utilization.reason, utilization.message,
          _sourceFor(job.kind), component.observedAt)
      } else {
        var firstTime = Date.parse(job.context.firstCpuObservedAt || "")
        var secondTime = Date.parse(component.observedAt || "")
        utilization.data.sampleIntervalMs = Number.isFinite(firstTime) && Number.isFinite(secondTime)
          ? Math.max(0, secondTime - firstTime) : null
        component.data = utilization.data
      }
    }
    _finishComponent(job.context, job.name, component)
  }

  function _enqueueCpuSecond(context) {
    if (context && !context.finished && _context(context.feature) === context)
      _enqueue(context, "proc-stat-second", "cpuUsage")
  }

  function _finishComponent(context, name, component) {
    if (!context || context.finished || _context(context.feature) !== context || context.completedNames[name])
      return
    context.completedNames[name] = true
    context.results[name] = component
    context.remaining -= 1
    if (context.remaining === 0) {
      context.finished = true
      _publishContext(context)
    }
  }

  function _successful(component) {
    return component && (component.status === Result.Status.Success || component.status === Result.Status.Empty)
  }

  function _summary(components) {
    var names = Object.keys(components)
    var successes = 0
    var partial = false
    var issues = []
    var hasTimeout = false
    var hasError = false
    var hasUnavailable = false
    var hasCanceled = false
    for (var i = 0; i < names.length; i++) {
      var component = components[names[i]]
      if (_successful(component)) {
        successes += 1
        if (component.completeness === Result.Completeness.Partial)
          partial = true
      } else {
        partial = true
        issues.push({ component: names[i], status: component.status, reason: component.reason, message: component.message })
        hasTimeout = hasTimeout || component.status === Result.Status.Timeout
        hasError = hasError || component.status === Result.Status.Error
        hasUnavailable = hasUnavailable || component.status === Result.Status.Unavailable
        hasCanceled = hasCanceled || component.status === Result.Status.Canceled
      }
    }
    var status = Result.Status.Success
    if (successes === 0) {
      if (hasTimeout) status = Result.Status.Timeout
      else if (hasError) status = Result.Status.Error
      else if (hasUnavailable) status = Result.Status.Unavailable
      else if (hasCanceled) status = Result.Status.Canceled
    }
    return { status: status, completeness: partial ? Result.Completeness.Partial : Result.Completeness.Complete,
      issues: issues, successCount: successes }
  }

  function _componentData(component) {
    return _successful(component) ? component.data : null
  }

  function _scopeData(scope, component) {
    if (!component)
      return { scope: scope, status: Result.Status.Unavailable, count: null,
        reason: "not-requested", message: "This scope was not requested." }
    return { scope: scope, status: component.status,
      count: _successful(component) ? component.data.count : null,
      reason: component.reason, message: component.message }
  }

  function _failedData(components) {
    var system = components.system
    var user = components.user
    var units = []
    if (_successful(system)) units = units.concat(system.data.units)
    if (_successful(user)) units = units.concat(user.data.units)
    return { units: units, totalCount: units.length,
      scopes: { system: _scopeData("system", system), user: _scopeData("user", user) } }
  }

  function _compositeResult(actionId, summary, data, message, source) {
    return Result.makeResult(actionId, summary.status, data, {
      message: message,
      reason: summary.status === Result.Status.Success ? "" : (summary.issues[0] ? summary.issues[0].reason : "snapshot-failed"),
      evidence: summary.issues,
      source: source,
      observedAt: _nowIso(),
      completeness: summary.completeness
    })
  }

  function _publishContext(context) {
    var components = context.results
    var summary = _summary(components)
    var result
    if (context.feature === "overview") {
      var kernelType = _componentData(components.kernelType)
      var kernelRelease = _componentData(components.kernelRelease)
      var cpuInfo = _componentData(components.cpuInfo)
      var cpuUsage = _componentData(components.cpuUsage)
      var data = {
        hostname: _componentData(components.hostname),
        os: _componentData(components.os),
        kernel: kernelType || kernelRelease ? {
          ostype: kernelType ? kernelType.value : null,
          release: kernelRelease ? kernelRelease.value : null,
          displayName: (kernelType ? kernelType.value : "") + (kernelType && kernelRelease ? " " : "") + (kernelRelease ? kernelRelease.value : "")
        } : null,
        cpu: cpuInfo || cpuUsage ? {
          model: cpuInfo ? cpuInfo.model : null,
          logicalProcessors: cpuInfo ? cpuInfo.logicalProcessors : null,
          usagePercent: cpuUsage ? cpuUsage.usagePercent : null,
          sampleIntervalMs: cpuUsage ? cpuUsage.sampleIntervalMs : null
        } : null,
        memory: _componentData(components.memory),
        uptime: _componentData(components.uptime),
        load: _componentData(components.load),
        rootStorage: _componentData(components.rootStorage),
        components: components,
        issues: summary.issues
      }
      result = _compositeResult(context.actionId, summary, data,
        summary.completeness === Result.Completeness.Complete ? "System overview refreshed." : "System overview is partially available.",
        _source("multiple fixed read-only sources", "Linux virtual files and findmnt"))
    } else if (context.feature === "disk") {
      var disk = components.disk
      if (_successful(disk) && disk.data.filesystems.length === 0) {
        result = Result.makeResult(context.actionId, Result.Status.Empty, disk.data, {
          message: "No real mounted filesystems were reported.", source: disk.source,
          observedAt: disk.observedAt, completeness: disk.completeness
        })
      } else if (_successful(disk)) {
        result = Result.success(context.actionId, disk.data, { message: "Disk usage refreshed.",
          source: disk.source, observedAt: disk.observedAt, completeness: disk.completeness })
      } else {
        result = Result.makeResult(context.actionId, disk.status, null, { message: disk.message,
          reason: disk.reason, source: disk.source, observedAt: disk.observedAt,
          completeness: Result.Completeness.Partial })
      }
    } else if (context.feature === "memory") {
      var memory = components.memory
      if (_successful(memory)) {
        result = Result.success(context.actionId, memory.data, { message: "Memory usage refreshed.",
          source: memory.source, observedAt: memory.observedAt, completeness: memory.completeness,
          evidence: memory.warnings })
      } else {
        result = Result.makeResult(context.actionId, memory.status, null, { message: memory.message,
          reason: memory.reason, source: memory.source, observedAt: memory.observedAt,
          completeness: Result.Completeness.Partial })
      }
    } else if (context.feature === "failed") {
      var failedData = _failedData(components)
      if (summary.status === Result.Status.Success && summary.completeness === Result.Completeness.Complete && failedData.totalCount === 0) {
        result = Result.makeResult(context.actionId, Result.Status.Empty, failedData, {
          message: "No failed system or user units were reported.",
          source: _source("/usr/bin/systemctl", "systemctl --system/--user --failed --output=json list-units"),
          observedAt: _nowIso()
        })
      } else {
        result = _compositeResult(context.actionId, summary, failedData,
          summary.completeness === Result.Completeness.Complete ? "Failed services refreshed." : "Failed services are partially available.",
          _source("/usr/bin/systemctl", "systemctl --system/--user --failed --output=json list-units"))
      }
    } else if (context.feature === "dashboard" || context.feature === "dashboardLive" || context.feature === "dashboardCpu" || context.feature === "dashboardInventory") {
      var dashboardFailed = _failedData({ system: components.failedSystem, user: components.failedUser })
      var dashboardData = {
        cpu: _componentData(components.cpuUsage),
        memory: _componentData(components.memory),
        uptime: _componentData(components.uptime),
        load: _componentData(components.load),
        rootStorage: _componentData(components.rootStorage),
        failedServices: dashboardFailed,
        systemdSystemState: _componentData(components.systemState),
        components: components,
        issues: summary.issues
      }
      result = _compositeResult(context.actionId, summary, dashboardData,
        summary.completeness === Result.Completeness.Complete ? "Dashboard system snapshot refreshed." : "Dashboard system snapshot is partially available.",
        _source("multiple fixed read-only sources", "Linux virtual files, findmnt, and systemctl"))
    } else {
      var state = components.systemState
      if (_successful(state)) {
        result = Result.success(context.actionId, state.data, { message: "systemd system state observed.",
          source: state.source, observedAt: state.observedAt })
      } else {
        result = Result.makeResult(context.actionId, state.status, null, { message: state.message,
          reason: state.reason, source: state.source, observedAt: state.observedAt,
          completeness: Result.Completeness.Partial })
      }
    }
    _publish(context.feature, result, true)
  }

  function _publish(feature, result, emitCompletion) {
    if (feature === "overview") {
      _systemOverviewResult = result
      if (emitCompletion) systemOverviewCompleted(result)
    } else if (feature === "disk") {
      _diskUsageResult = result
      if (emitCompletion) diskUsageCompleted(result)
    } else if (feature === "memory") {
      _memoryUsageResult = result
      if (emitCompletion) memoryUsageCompleted(result)
    } else if (feature === "failed") {
      _failedServicesResult = result
      if (emitCompletion) failedServicesCompleted(result)
    } else if (feature === "dashboard") {
      _dashboardSystemSnapshotResult = result
      if (emitCompletion) dashboardSystemSnapshotCompleted(result)
    } else if (feature === "dashboardLive") {
      _dashboardLiveSnapshotResult = result
    } else if (feature === "dashboardCpu") {
      _dashboardCpuSnapshotResult = result
    } else if (feature === "dashboardInventory") {
      _dashboardInventorySnapshotResult = result
    } else {
      _systemdSystemStateResult = result
      if (emitCompletion) systemdSystemStateCompleted(result)
    }
  }

  function _cancelFeatureWork(feature) {
    var context = _context(feature)
    if (context === null || context.finished)
      return
    context.finished = true
    _queue = _queue.filter(function(job) { return job.context !== context })
    if (feature === "overview" && _overviewCpuContext === context) {
      overviewCpuTimer.stop()
      _overviewCpuContext = null
    }
    if ((feature === "dashboard" || feature === "dashboardLive" || feature === "dashboardCpu") && _dashboardCpuContext === context) {
      dashboardCpuTimer.stop()
      _dashboardCpuContext = null
    }
    for (var index = 0; index < 4; index++) {
      var job = _runnerJobs[index]
      if (job !== null && job.context === context)
        _runner(index).cancel()
    }
  }

  function _cancelPublic(feature, actionId) {
    var context = _context(feature)
    if (context === null || context.finished)
      return false
    _cancelFeatureWork(feature)
    var canceled = Result.makeResult(actionId, Result.Status.Canceled, null, {
      message: "Refresh canceled.", reason: "canceled", observedAt: _nowIso()
    })
    _publish(feature, canceled, true)
    return true
  }

  function refreshSystemOverview() {
    var context = _newContext("overview", "system.overview", 10)
    _enqueue(context, "hostname", "hostname")
    _enqueue(context, "os-release", "os")
    _enqueue(context, "kernel-ostype", "kernelType")
    _enqueue(context, "kernel-release", "kernelRelease")
    _enqueue(context, "cpuinfo", "cpuInfo")
    _enqueue(context, "proc-stat-first", "cpuUsage")
    _enqueue(context, "meminfo", "memory")
    _enqueue(context, "uptime", "uptime")
    _enqueue(context, "loadavg", "load")
    _enqueue(context, "root-findmnt", "rootStorage")
    return context.generation
  }

  function refreshDiskUsage() {
    var context = _newContext("disk", "system.disk-usage", 1)
    _enqueue(context, "disk-findmnt", "disk")
    return context.generation
  }

  function refreshMemoryUsage() {
    var context = _newContext("memory", "system.memory-usage", 1)
    _enqueue(context, "meminfo", "memory")
    return context.generation
  }

  function refreshFailedServices() {
    var context = _newContext("failed", "system.failed-services", 2)
    _enqueue(context, "failed-system", "system")
    _enqueue(context, "failed-user", "user")
    return context.generation
  }

  function refreshDashboardSystemSnapshot() {
    var context = _newContext("dashboard", "dashboard.system", 8)
    _enqueue(context, "proc-stat-first", "cpuUsage")
    _enqueue(context, "meminfo", "memory")
    _enqueue(context, "uptime", "uptime")
    _enqueue(context, "loadavg", "load")
    _enqueue(context, "root-findmnt", "rootStorage")
    _enqueue(context, "failed-system", "failedSystem")
    _enqueue(context, "failed-user", "failedUser")
    _enqueue(context, "systemd-state", "systemState")
    return context.generation
  }

  // Separating live from inventory probes avoids rerunning systemd/findmnt
  // when the visible dashboard samples CPU, memory, load, and uptime.
  function refreshDashboardLiveSnapshot() {
    var context = _newContext("dashboardLive", "dashboard.live", 3)
    _enqueue(context, "meminfo", "memory")
    _enqueue(context, "uptime", "uptime")
    _enqueue(context, "loadavg", "load")
    return context.generation
  }

  function refreshDashboardCpuSnapshot() {
    var context = _newContext("dashboardCpu", "dashboard.cpu", 1)
    _enqueue(context, "proc-stat-first", "cpuUsage")
    return context.generation
  }

  function refreshDashboardInventorySnapshot() {
    var context = _newContext("dashboardInventory", "dashboard.inventory", 4)
    _enqueue(context, "root-findmnt", "rootStorage")
    _enqueue(context, "failed-system", "failedSystem")
    _enqueue(context, "failed-user", "failedUser")
    _enqueue(context, "systemd-state", "systemState")
    return context.generation
  }

  function refreshSystemdSystemState() {
    var context = _newContext("state", "system.systemd-state", 1)
    _enqueue(context, "systemd-state", "systemState")
    return context.generation
  }

  function cancelSystemOverview() { return _cancelPublic("overview", "system.overview") }
  function cancelDiskUsage() { return _cancelPublic("disk", "system.disk-usage") }
  function cancelMemoryUsage() { return _cancelPublic("memory", "system.memory-usage") }
  function cancelFailedServices() { return _cancelPublic("failed", "system.failed-services") }
  function cancelDashboardSystemSnapshot() { return _cancelPublic("dashboard", "dashboard.system") }
  function cancelDashboardLiveSnapshot() { return _cancelPublic("dashboardLive", "dashboard.live") }
  function cancelDashboardCpuSnapshot() { return _cancelPublic("dashboardCpu", "dashboard.cpu") }
  function cancelDashboardInventorySnapshot() { return _cancelPublic("dashboardInventory", "dashboard.inventory") }
  function cancelSystemdSystemState() { return _cancelPublic("state", "system.systemd-state") }

  function cancelAll() {
    cancelSystemOverview()
    cancelDiskUsage()
    cancelMemoryUsage()
    cancelFailedServices()
    cancelDashboardSystemSnapshot()
    cancelDashboardLiveSnapshot()
    cancelDashboardCpuSnapshot()
    cancelDashboardInventorySnapshot()
    cancelSystemdSystemState()
  }

  function shutdown() {
    if (_destroying)
      return
    _destroying = true
    overviewCpuTimer.stop()
    dashboardCpuTimer.stop()
    _queue = []
    for (var index = 0; index < 4; index++)
      _runner(index).shutdown()
  }

  Timer {
    id: overviewCpuTimer
    interval: 500
    repeat: false
    onTriggered: {
      var context = root._overviewCpuContext
      root._overviewCpuContext = null
      root._enqueueCpuSecond(context)
    }
  }

  Timer {
    id: dashboardCpuTimer
    interval: 500
    repeat: false
    onTriggered: {
      var context = root._dashboardCpuContext
      root._dashboardCpuContext = null
      root._enqueueCpuSecond(context)
    }
  }

  ProcessRunner {
    id: runner0
    onCompleted: function(result) { root._onRunnerCompleted(0, result) }
    onBusyChanged: Qt.callLater(function() { root._runnerAvailable(0) })
  }

  ProcessRunner {
    id: runner1
    onCompleted: function(result) { root._onRunnerCompleted(1, result) }
    onBusyChanged: Qt.callLater(function() { root._runnerAvailable(1) })
  }

  ProcessRunner {
    id: runner2
    onCompleted: function(result) { root._onRunnerCompleted(2, result) }
    onBusyChanged: Qt.callLater(function() { root._runnerAvailable(2) })
  }

  ProcessRunner {
    id: runner3
    onCompleted: function(result) { root._onRunnerCompleted(3, result) }
    onBusyChanged: Qt.callLater(function() { root._runnerAvailable(3) })
  }

  Component.onDestruction: shutdown()
}
