import QtQuick
import Quickshell

import "../parsers/Result.js" as Result
import "../parsers/Validation.js" as Validation
import "../parsers/NetworkParsers.js" as NetworkParsers

// Read-only network service. Public methods accept feature intent or validated
// host/name input only; all executable paths, argv, deadlines, and parsers are
// fixed below.
Scope {
  id: root

  readonly property var networkOverviewResult: _networkOverviewResult
  readonly property var listeningPortsResult: _listeningPortsResult
  readonly property var pingResult: _pingResult
  readonly property var dnsResult: _dnsResult
  readonly property var dashboardNetworkSnapshotResult: _dashboardNetworkSnapshotResult
  readonly property bool busy: runner0.busy || runner1.busy || runner2.busy || runner3.busy || _queue.length > 0

  signal networkOverviewCompleted(var result)
  signal listeningPortsCompleted(var result)
  signal pingCompleted(var result)
  signal dnsCompleted(var result)
  signal dashboardNetworkSnapshotCompleted(var result)

  property var _networkOverviewResult: _notRefreshed("network.overview")
  property var _listeningPortsResult: _notRefreshed("network.listening-ports")
  property var _pingResult: _notRefreshed("network.ping-host")
  property var _dnsResult: _notRefreshed("network.dns-lookup")
  property var _dashboardNetworkSnapshotResult: _notRefreshed("dashboard.network")
  property var _contexts: ({ overview: null, ports: null, ping: null, dns: null, dashboard: null })
  property var _generations: ({ overview: 0, ports: 0, ping: 0, dns: 0, dashboard: 0 })
  property var _queue: []
  property var _runnerJobs: [null, null, null, null]
  property bool _destroying: false

  function _nowIso() { return new Date().toISOString() }
  function _notRefreshed(actionId) { return Result.unavailable(actionId, "not-refreshed", { message: "This snapshot has not been refreshed yet." }) }
  function _source(tool, displayCommand) { return { tool: tool, displayCommand: displayCommand } }

  function _request(kind, context) {
    if (kind === "route") return { actionId: context.actionId + ".route", executable: "/usr/bin/ip", arguments: ["-j", "route", "show", "default"], timeoutMs: 2000 }
    if (kind === "link") return { actionId: context.actionId + ".link", executable: "/usr/bin/ip", arguments: ["-j", "link", "show"], timeoutMs: 2000 }
    if (kind === "address") return { actionId: context.actionId + ".address", executable: "/usr/bin/ip", arguments: ["-j", "address", "show"], timeoutMs: 2000 }
    if (kind === "resolver-status") return { actionId: context.actionId + ".resolver", executable: "/usr/bin/resolvectl", arguments: ["--json=short", "status"], timeoutMs: 2000 }
    if (kind === "ports") return { actionId: "network.listening-ports", executable: "/usr/bin/ss", arguments: ["-H", "-l", "-n", "-t", "-u", "-p"], outputMode: "lines", timeoutMs: 2000 }
    if (kind === "ping") {
      var family = context.input.kind === "ipv4" ? ["-4"] : context.input.kind === "ipv6" ? ["-6"] : []
      return { actionId: "network.ping-host", executable: "/usr/bin/ping",
        arguments: family.concat(["-n", "-c", "4", "-W", "1", "-w", "5", "--", context.input.value]), timeoutMs: 6000 }
    }
    if (kind === "dns-a" || kind === "dns-aaaa") return {
      actionId: "network.dns-lookup." + (kind === "dns-a" ? "a" : "aaaa"), executable: "/usr/bin/resolvectl",
      arguments: ["--json=short", "query", "--type=" + (kind === "dns-a" ? "A" : "AAAA"), context.input.value], timeoutMs: 5000
    }
    return null
  }

  function _sourceFor(kind) {
    if (kind === "route") return _source("/usr/bin/ip", "ip -j route show default")
    if (kind === "link") return _source("/usr/bin/ip", "ip -j link show")
    if (kind === "address") return _source("/usr/bin/ip", "ip -j address show")
    if (kind === "resolver-status") return _source("/usr/bin/resolvectl", "resolvectl --json=short status")
    if (kind === "ports") return _source("/usr/bin/ss", "ss -H -l -n -t -u -p")
    if (kind === "ping") return _source("/usr/bin/ping", "ping")
    return _source("/usr/bin/resolvectl", "resolvectl --json=short query --type=" + (kind === "dns-a" ? "A" : "AAAA"))
  }

  function _runner(index) { return index === 0 ? runner0 : index === 1 ? runner1 : index === 2 ? runner2 : runner3 }
  function _context(feature) { return _contexts[feature] || null }
  function _setContext(feature, context) { var copy = Object.assign({}, _contexts); copy[feature] = context; _contexts = copy }
  function _nextGeneration(feature) { var copy = Object.assign({}, _generations); copy[feature] += 1; _generations = copy; return copy[feature] }

  function _newContext(feature, actionId, count, input) {
    _cancelFeatureWork(feature)
    var context = { feature: feature, actionId: actionId, generation: _nextGeneration(feature),
      remaining: count, results: {}, completed: {}, input: input || null, finished: false }
    _setContext(feature, context)
    _publish(feature, Result.loading(actionId, { message: "Checking network data…", observedAt: _nowIso() }), false)
    return context
  }

  function _enqueue(context, kind, name) {
    if (_destroying || !context || context.finished || _context(context.feature) !== context) return
    _queue.push({ context: context, kind: kind, name: name, runId: 0 })
    _dispatch()
  }

  function _dispatch() {
    if (_destroying) return
    for (var index = 0; index < 4 && _queue.length > 0; index++) {
      var runner = _runner(index)
      if (runner.busy || _runnerJobs[index] !== null) continue
      var job = _queue.shift()
      if (job.context.finished || _context(job.context.feature) !== job.context) { index -= 1; continue }
      var request = _request(job.kind, job.context)
      if (request === null) { _finish(job.context, job.name, _componentFailure(Result.Status.Error, "invalid-probe", "Internal network probe is missing.", null)); index -= 1; continue }
      _runnerJobs[index] = job
      job.runId = runner.run(request)
    }
  }

  function _runnerAvailable(index) { if (!_runner(index).busy && _runnerJobs[index] === null) _dispatch() }
  function _onRunnerCompleted(index, execution) {
    var job = _runnerJobs[index]
    if (job === null) return
    var runId = execution && execution.data ? execution.data.runId : 0
    if (runId !== job.runId) return
    _runnerJobs[index] = null
    if (!job.context.finished && _context(job.context.feature) === job.context) _finish(job.context, job.name, _parseExecution(execution, job.kind))
  }

  function _executionText(execution, stream) { return execution && execution.data ? String(execution.data[stream] || "") : "" }
  function _componentFailure(status, reason, message, source, observedAt) {
    return { status: status, data: null, reason: reason, message: message, source: source,
      observedAt: observedAt || _nowIso(), completeness: Result.Completeness.Complete, warnings: [] }
  }
  function _negativeDns(execution) {
    return execution.reason === "nonzero-exit"
      && NetworkParsers.parseResolvectlDnsNegative(_executionText(execution, "stderr")).ok
  }

  function _parseExecution(execution, kind) {
    var source = _sourceFor(kind)
    var allowPingNegative = kind === "ping" && execution.reason === "nonzero-exit" && execution.data && execution.data.exitCode === 1
    var allowDnsNegative = (kind === "dns-a" || kind === "dns-aaaa") && _negativeDns(execution)
    if (execution.status !== Result.Status.Success && !allowPingNegative && !allowDnsNegative) {
      var status = execution.status
      var reason = execution.reason || "execution-failed"
      var message = execution.message || "The network probe failed."
      if (status === Result.Status.Unavailable) { reason = "command-missing"; message = "The required read-only tool is unavailable: " + source.tool }
      return _componentFailure(status, reason, message, source, execution.observedAt)
    }
    var text = kind === "ports" ? (execution.data && Array.isArray(execution.data.rows) ? execution.data.rows.join("\n") : "") : _executionText(execution, "stdout")
    var parsed
    if (kind === "route") parsed = NetworkParsers.parseIpRouteJson(text)
    else if (kind === "link") parsed = NetworkParsers.parseIpLinkJson(text)
    else if (kind === "address") parsed = NetworkParsers.parseIpAddressJson(text)
    else if (kind === "resolver-status") parsed = NetworkParsers.parseResolvectlStatusJson(text)
    else if (kind === "ports") parsed = NetworkParsers.parseSsListening(text)
    else if (kind === "ping") parsed = NetworkParsers.parsePingSummary(text)
    else if (allowDnsNegative) parsed = { ok: true, data: { family: kind === "dns-a" ? "A" : "AAAA", answers: [], count: 0, negative: true }, completeness: "complete", warnings: [] }
    else parsed = NetworkParsers.parseResolvectlDnsQueryJsonLines(text, kind === "dns-a" ? "A" : "AAAA")
    if (!parsed.ok) return _componentFailure(Result.Status.Error, parsed.reason, parsed.message, source, execution.observedAt)
    return { status: Result.Status.Success, data: parsed.data, reason: "", message: "", source: source,
      observedAt: execution.observedAt, completeness: parsed.completeness, warnings: parsed.warnings.slice() }
  }

  function _finish(context, name, component) {
    if (!context || context.finished || _context(context.feature) !== context || context.completed[name]) return
    context.completed[name] = true
    context.results[name] = component
    context.remaining -= 1
    if (context.remaining === 0) { context.finished = true; _publishContext(context) }
  }

  function _ok(component) { return component && (component.status === Result.Status.Success || component.status === Result.Status.Empty) }
  function _firstFailure(components, names) { for (var i = 0; i < names.length; i++) if (!_ok(components[names[i]])) return components[names[i]]; return null }

  function _publishContext(context) {
    var parts = context.results
    var result
    if (context.feature === "overview" || context.feature === "dashboard") {
      var required = ["route", "link", "address"]
      var failed = _firstFailure(parts, required)
      if (failed) result = Result.makeResult(context.actionId, failed.status, null, { message: failed.message, reason: failed.reason, source: failed.source, observedAt: failed.observedAt, completeness: Result.Completeness.Partial })
      else {
        var dnsData = _ok(parts.dns) ? parts.dns.data : { global: null, links: [] }
        var derived = NetworkParsers.deriveNetworkOverview(parts.route.data, parts.link.data, parts.address.data, dnsData)
        if (!derived.ok) result = Result.makeResult(context.actionId, Result.Status.Error, null, { message: derived.message, reason: derived.reason, observedAt: _nowIso() })
        else {
          var partial = context.feature === "overview" && !_ok(parts.dns)
          result = Result.success(context.actionId, derived.data, { message: derived.data.connectionState === "connected-local" ? "Connected locally." : "Local network state observed.",
            source: _source("multiple fixed read-only sources", context.feature === "dashboard" ? "ip -j route/link/address" : "ip -j route/link/address and resolvectl status"),
            observedAt: _nowIso(), completeness: partial || derived.completeness === "partial" ? Result.Completeness.Partial : Result.Completeness.Complete,
            evidence: partial ? [{ component: "dns", status: parts.dns.status, reason: parts.dns.reason, message: parts.dns.message }] : [] })
        }
      }
    } else if (context.feature === "ports") {
      var ports = parts.ports
      if (_ok(ports)) result = Result.makeResult(context.actionId, ports.data.count === 0 ? Result.Status.Empty : Result.Status.Success, ports.data,
        { message: ports.data.count === 0 ? "No TCP or UDP listening sockets were reported." : "Listening sockets refreshed.", source: ports.source, observedAt: ports.observedAt })
      else result = Result.makeResult(context.actionId, ports.status, null, { message: ports.message, reason: ports.reason, source: ports.source, observedAt: ports.observedAt })
    } else if (context.feature === "ping") {
      var ping = parts.ping
      if (_ok(ping)) {
        var pingData = Object.assign({ target: context.input.displayValue, targetKind: context.input.kind }, ping.data)
        result = Result.success(context.actionId, pingData, { message: pingData.replied ? "Replies received." : "Ping completed with no replies.", source: ping.source, observedAt: ping.observedAt })
      } else result = Result.makeResult(context.actionId, ping.status, null, { message: ping.message, reason: ping.reason, source: ping.source, observedAt: ping.observedAt })
    } else {
      var a = parts.a; var aaaa = parts.aaaa
      var dnsFailure = !_ok(a) && !_ok(aaaa) ? a : null
      if (dnsFailure) result = Result.makeResult(context.actionId, dnsFailure.status, null, { message: dnsFailure.message, reason: dnsFailure.reason, source: dnsFailure.source, observedAt: dnsFailure.observedAt })
      else {
        var ipv4 = _ok(a) ? a.data.answers.slice() : []
        var ipv6 = _ok(aaaa) ? aaaa.data.answers.slice() : []
        var negative = (_ok(a) && a.data.negative === true) && (_ok(aaaa) && aaaa.data.negative === true)
        var dnsDataResult = { name: context.input.displayValue, ipv4: ipv4, ipv6: ipv6, negative: negative,
          families: { A: _ok(a) ? "complete" : a.status, AAAA: _ok(aaaa) ? "complete" : aaaa.status } }
        var status = ipv4.length === 0 && ipv6.length === 0 ? Result.Status.Empty : Result.Status.Success
        result = Result.makeResult(context.actionId, status, dnsDataResult, { message: negative ? "The resolver reported that the name was not found." : status === Result.Status.Empty ? "The resolver returned no A or AAAA answers." : "DNS lookup completed.",
          source: _source("/usr/bin/resolvectl", "resolvectl query (separate A and AAAA requests)"), observedAt: _nowIso(),
          completeness: _ok(a) && _ok(aaaa) ? Result.Completeness.Complete : Result.Completeness.Partial })
      }
    }
    _publish(context.feature, result, true)
  }

  function _publish(feature, result, completed) {
    if (feature === "overview") { _networkOverviewResult = result; if (completed) networkOverviewCompleted(result) }
    else if (feature === "ports") { _listeningPortsResult = result; if (completed) listeningPortsCompleted(result) }
    else if (feature === "ping") { _pingResult = result; if (completed) pingCompleted(result) }
    else if (feature === "dns") { _dnsResult = result; if (completed) dnsCompleted(result) }
    else { _dashboardNetworkSnapshotResult = result; if (completed) dashboardNetworkSnapshotCompleted(result) }
  }

  function _cancelFeatureWork(feature) {
    var context = _context(feature)
    if (!context || context.finished) return
    context.finished = true
    _queue = _queue.filter(function(job) { return job.context !== context })
    for (var i = 0; i < 4; i++) if (_runnerJobs[i] && _runnerJobs[i].context === context) _runner(i).cancel()
  }
  function _cancelPublic(feature, actionId) {
    var context = _context(feature)
    if (!context || context.finished) return false
    _cancelFeatureWork(feature)
    _publish(feature, Result.makeResult(actionId, Result.Status.Canceled, null, { message: "Refresh canceled.", reason: "canceled", observedAt: _nowIso() }), true)
    return true
  }

  function _validatedPing(input) {
    var raw = typeof input === "string" ? input : input && typeof input.value === "string" ? input.value : ""
    var checked = Validation.validatePingTarget(raw)
    if (!checked.ok || (typeof input === "object" && input !== null && (input.kind !== checked.kind || input.value !== checked.value))) return checked.ok ? { ok: false, reason: "invalid-input", message: "The typed Ping target did not pass service validation." } : checked
    return checked
  }
  function _validatedDns(input) {
    var raw = typeof input === "string" ? input : input && typeof input.value === "string" ? input.value : ""
    var checked = Validation.validateDnsName(raw)
    if (!checked.ok || (typeof input === "object" && input !== null && (input.kind !== checked.kind || input.value !== checked.value))) return checked.ok ? { ok: false, reason: "invalid-input", message: "The typed DNS name did not pass service validation." } : checked
    return checked
  }
  function _rejectInput(feature, actionId, validation) {
    _cancelFeatureWork(feature)
    var result = Result.makeResult(actionId, Result.Status.Error, null, { message: validation.message, reason: validation.reason || "invalid-input", observedAt: _nowIso() })
    _publish(feature, result, true)
    return 0
  }

  function refreshNetworkOverview() { var c = _newContext("overview", "network.overview", 4); _enqueue(c, "route", "route"); _enqueue(c, "link", "link"); _enqueue(c, "address", "address"); _enqueue(c, "resolver-status", "dns"); return c.generation }
  function refreshListeningPorts() { var c = _newContext("ports", "network.listening-ports", 1); _enqueue(c, "ports", "ports"); return c.generation }
  function pingHost(input) { var checked = _validatedPing(input); if (!checked.ok) return _rejectInput("ping", "network.ping-host", checked); var c = _newContext("ping", "network.ping-host", 1, checked); _enqueue(c, "ping", "ping"); return c.generation }
  function lookupDns(input) { var checked = _validatedDns(input); if (!checked.ok) return _rejectInput("dns", "network.dns-lookup", checked); var c = _newContext("dns", "network.dns-lookup", 2, checked); _enqueue(c, "dns-a", "a"); _enqueue(c, "dns-aaaa", "aaaa"); return c.generation }
  function refreshDashboardNetworkSnapshot() { var c = _newContext("dashboard", "dashboard.network", 3); _enqueue(c, "route", "route"); _enqueue(c, "link", "link"); _enqueue(c, "address", "address"); return c.generation }

  function cancelNetworkOverview() { return _cancelPublic("overview", "network.overview") }
  function cancelListeningPorts() { return _cancelPublic("ports", "network.listening-ports") }
  function cancelPing() { return _cancelPublic("ping", "network.ping-host") }
  function cancelDns() { return _cancelPublic("dns", "network.dns-lookup") }
  function cancelDashboardNetworkSnapshot() { return _cancelPublic("dashboard", "dashboard.network") }
  function cancelAll() { cancelNetworkOverview(); cancelListeningPorts(); cancelPing(); cancelDns(); cancelDashboardNetworkSnapshot() }
  function shutdown() { if (_destroying) return; _destroying = true; _queue = []; for (var i = 0; i < 4; i++) _runner(i).shutdown() }

  ProcessRunner { id: runner0; onCompleted: function(result) { root._onRunnerCompleted(0, result) }; onBusyChanged: Qt.callLater(function() { root._runnerAvailable(0) }) }
  ProcessRunner { id: runner1; onCompleted: function(result) { root._onRunnerCompleted(1, result) }; onBusyChanged: Qt.callLater(function() { root._runnerAvailable(1) }) }
  ProcessRunner { id: runner2; onCompleted: function(result) { root._onRunnerCompleted(2, result) }; onBusyChanged: Qt.callLater(function() { root._runnerAvailable(2) }) }
  ProcessRunner { id: runner3; onCompleted: function(result) { root._onRunnerCompleted(3, result) }; onBusyChanged: Qt.callLater(function() { root._runnerAvailable(3) }) }

  Component.onDestruction: shutdown()
}
