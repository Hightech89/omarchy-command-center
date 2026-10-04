// Pure interpretation of structured service results. No probes or side effects.
var NetworkStages = ["Interface", "Local IP address", "Default route", "Gateway reachability", "DNS resolution", "Public ICMP reachability"]
var PublicTargets = [
  { provider: "Cloudflare", ipv4: "1.1.1.1", ipv6: "2606:4700:4700::1111" },
  { provider: "Quad9", ipv4: "9.9.9.9", ipv6: "2620:fe::fe" },
  { provider: "Google", ipv4: "8.8.8.8", ipv6: "2001:4860:4860::8888" }
]

function check(name, status, observed, interpretation, explanation) {
  return { name: name, status: status, observed: observed, interpretation: interpretation, explanation: explanation }
}
function valid(value) { return typeof value === "number" && Number.isFinite(value) && value >= 0 }
function shown(value, suffix) { return valid(value) ? String(Math.round(value * 10) / 10) + suffix : "Unavailable" }
function high(value, warning, critical) { return !valid(value) ? "unavailable" : value >= critical ? "critical" : value >= warning ? "warning" : "healthy" }
function low(value, warning, critical) { return !valid(value) ? "unavailable" : value < critical ? "critical" : value < warning ? "warning" : "healthy" }
function sourceStatus(component) { return component && component.status === "error" || component && component.status === "timeout" ? "error" : "unavailable" }
function missing(name, component) { return check(name, sourceStatus(component), "Unavailable", "Source did not provide a usable value.", component && component.message ? component.message : "This check could not be completed.") }

function aggregate(checks) {
  var statuses = checks.map(function(item) { return item.status })
  var completeness = statuses.indexOf("error") !== -1 ? "error" : statuses.indexOf("unavailable") !== -1 ? "unavailable" : "complete"
  var status = statuses.indexOf("critical") !== -1 ? "critical"
    : statuses.indexOf("error") !== -1 ? "error"
    : statuses.indexOf("warning") !== -1 ? "warning"
    : statuses.indexOf("unavailable") !== -1 ? "unavailable" : "healthy"
  return { status: status, completeness: completeness }
}

function systemHealth(overview, failed, state) {
  var data = overview && overview.data || {}
  var parts = data.components || {}
  var checks = []
  var cpu = data.cpu && data.cpu.usagePercent
  checks.push(valid(cpu) ? check("CPU utilization", high(cpu, 70, 90), shown(cpu, "%"), "Warning at 70%; critical at 90%.", "Short CPU utilization sample.") : missing("CPU utilization", parts.cpuUsage))
  var processors = data.cpu && data.cpu.logicalProcessors
  var load = data.load && data.load.one
  var normalized = valid(load) && valid(processors) && processors > 0 ? load / processors : null
  checks.push(valid(normalized) ? check("Normalized load", high(normalized, 0.70, 1.00), shown(normalized, " per CPU"), "Warning at 0.70; critical at 1.00.", "1/5/15 min load: " + [data.load.one, data.load.five, data.load.fifteen].join(" / ") + "; " + processors + " logical CPUs.") : missing("Normalized load", !valid(processors) ? parts.cpuInfo : parts.load))
  var memory = data.memory
  var available = memory && valid(memory.total) && memory.total > 0 && valid(memory.available) ? memory.available / memory.total * 100 : null
  checks.push(valid(available) ? check("Memory available", low(available, 20, 10), shown(available, "% available"), "Warning below 20%; critical below 10%.", "MemAvailable / MemTotal; " + shown(memory.used / memory.total * 100, "% used") + ".") : missing("Memory available", parts.memory))
  var storage = data.rootStorage
  var used = storage && valid(storage.usePercent) ? storage.usePercent : null
  checks.push(valid(used) ? check("Root storage", high(used, 80, 90), shown(used, "% used"), "Warning at 80%; critical at 90%.", "Mount: " + storage.target + ".") : missing("Root storage", parts.rootStorage))
  var scopes = failed && failed.data && failed.data.scopes
  var system = scopes && scopes.system
  var user = scopes && scopes.user
  if (system && user && (system.status === "success" || system.status === "empty") && (user.status === "success" || user.status === "empty") && valid(system.count) && valid(user.count)) {
    var count = system.count + user.count
    checks.push(check("Failed services", high(count, 1, 3), count + " total", "Healthy: 0; warning: 1–2; critical: 3 or more.", system.count + " system, " + user.count + " user."))
  } else checks.push(missing("Failed services", system && system.status !== "success" ? system : user || failed))
  var systemd = state && state.data && state.data.state
  var status = systemd === "running" ? "healthy" : ["degraded", "initializing", "starting"].indexOf(systemd) !== -1 ? "warning" : ["maintenance", "stopping", "offline"].indexOf(systemd) !== -1 ? "critical" : "unavailable"
  checks.push(systemd ? check("systemd state", status, systemd, "running: healthy; degraded/starting: warning; maintenance/stopping/offline: critical.", status === "unavailable" ? "systemctl reported an unclassified state." : "State reported by systemctl is-system-running.") : missing("systemd state", state))
  var summary = aggregate(checks)
  return { status: summary.status, completeness: summary.completeness, checks: checks }
}

function stage(name, status, observed, explanation) { return { name: name, status: status, observed: observed, explanation: explanation } }
function pendingStages() { return NetworkStages.map(function(name) { return stage(name, "pending", "Waiting", "") }) }
function networkLocal(overview) {
  var stages = pendingStages()
  if (!overview || overview.status !== "success" || !overview.data) {
    var failedStatus = overview && overview.status === "error" || overview && overview.status === "timeout" ? "error" : "unavailable"
    for (var i = 0; i < 3; i++) stages[i] = stage(NetworkStages[i], failedStatus, "Unavailable", overview && overview.message || "Local network data could not be obtained.")
    return { stages: stages, data: null }
  }
  var data = overview.data, link = data.primaryInterface, route = data.route
  stages[0] = !link ? stage(NetworkStages[0], route ? "critical" : "unavailable", "Interface unavailable", route ? "The selected route interface was not found." : "No default route selected an interface.")
    : data.connectionState === "interface-down" ? stage(NetworkStages[0], "critical", "Interface down", link.name + " is not operational.")
    : stage(NetworkStages[0], "healthy", "Interface available", link.name + " · " + link.operationalState)
  var ipv4 = data.ipv4 || [], ipv6 = data.ipv6 || [], local = ipv4.concat(ipv6)
  stages[1] = !link ? stage(NetworkStages[1], "unavailable", "Address unavailable", "No selected interface to inspect.")
    : local.length ? stage(NetworkStages[1], "healthy", "IPv4: " + (ipv4.join(", ") || "none") + " · IPv6: " + (ipv6.join(", ") || "none"), "Usable addresses. Link-local: " + ((data.linkLocal || []).join(", ") || "none") + ".")
    : stage(NetworkStages[1], "critical", "No usable local address", "Link-local: " + ((data.linkLocal || []).join(", ") || "none") + ". Link-local alone is not a routable address.")
  stages[2] = route ? stage(NetworkStages[2], "healthy", route.interfaceName + " · " + (route.gateway || "on-link") + " · " + (route.family || "family unknown"), "Metric: " + (route.metric === null ? "not supplied" : route.metric) + ".")
    : stage(NetworkStages[2], "critical", "No default route", "No IPv4 or IPv6 default route was reported.")
  if (overview.evidence && overview.evidence.some(function(item) { return item.component === "route6" })) {
    stages[2].completeness = "partial"
    stages[2].explanation += " IPv6 route data could not be assessed."
  }
  return { stages: stages, data: data }
}
function gatewayResult(result, gateway) {
  if (!gateway) return stage(NetworkStages[3], "skipped", "No gateway address", "The default route is on-link or has no explicit gateway.")
  if (result && result.status === "success" && result.data)
    return result.data.replied ? stage(NetworkStages[3], "healthy", gateway + " responded", "Gateway ICMP reply observed.") : stage(NetworkStages[3], "warning", "Gateway did not respond to ICMP", "The gateway may ignore ICMP; this does not establish that it is offline.")
  return stage(NetworkStages[3], sourceStatus(result), "Gateway probe unavailable", result && result.message || "Gateway ICMP could not be assessed.")
}
function dnsResult(result) {
  if (result && (result.status === "success" || result.status === "empty") && result.data) {
    var count = (result.data.ipv4 || []).length + (result.data.ipv6 || []).length
    if (count) {
      var answer = stage(NetworkStages[4], "healthy", count + " A/AAAA answer" + (count === 1 ? "" : "s"), "example.com resolved via the configured resolver.")
      if (result.completeness === "partial") { answer.completeness = "partial"; answer.explanation += " One address family could not be assessed." }
      return answer
    }
    return result.completeness === "partial" ? stage(NetworkStages[4], "unavailable", "DNS result incomplete", "No usable answer was observed, and one address family could not be assessed.")
      : stage(NetworkStages[4], "warning", "DNS did not return an A/AAAA result", "example.com produced no usable address answer.")
  }
  return stage(NetworkStages[4], sourceStatus(result), "DNS lookup unavailable", result && result.message || "DNS could not be assessed.")
}
function publicTargets(data) {
  var routes = data && data.defaultRoutes ? data.defaultRoutes : data && data.route ? [data.route] : []
  var selectedInterface = data && data.route && data.route.interfaceName
  var hasRoute = function(family) { return routes.some(function(route) { return route.family === family && route.interfaceName === selectedInterface }) }
  var use4 = data && data.ipv4 && data.ipv4.length && hasRoute("ipv4")
  var use6 = data && data.ipv6 && data.ipv6.length && hasRoute("ipv6")
  var targets = []
  PublicTargets.forEach(function(provider) {
    if (use4) targets.push({ provider: provider.provider, address: provider.ipv4 })
    if (use6) targets.push({ provider: provider.provider, address: provider.ipv6 })
  })
  return targets
}
function publicResult(attempts, successful) {
  if (successful) return stage(NetworkStages[5], "healthy", successful.provider + " " + successful.address + " responded", "Public IP/ICMP reachability observed.")
  if (!attempts.length) return stage(NetworkStages[5], "unavailable", "No suitable target", "A usable local address and matching default route are required.")
  var failed = attempts.filter(function(item) { return item.result && item.result.status === "success" && item.result.data && !item.result.data.replied })
  if (failed.length === attempts.length) return stage(NetworkStages[5], "warning", "Tested endpoints did not respond to ICMP", attempts.map(function(item) { return item.target.provider + " " + item.target.address }).join("; ") + ". ICMP can be blocked even when other network traffic works.")
  return stage(NetworkStages[5], "unavailable", "Public ICMP partly unavailable", "Some probes could not be assessed; ICMP can be blocked even when other traffic works.")
}
function networkOverall(stages, running) {
  if (running) return { status: "running", completeness: "partial", stop: "" }
  var summary = aggregate(stages.filter(function(item) { return item.status !== "pending" && item.status !== "skipped" }))
  if (stages.some(function(item) { return item.completeness === "partial" })) {
    summary.completeness = "unavailable"
    if (summary.status === "healthy") summary.status = "unavailable"
  }
  var first = stages.filter(function(item) { return item.status === "critical" })[0]
    || stages.filter(function(item) { return ["warning", "error", "unavailable"].indexOf(item.status) !== -1 })[0]
  return { status: summary.status, completeness: summary.completeness, stop: first ? first.name + ": " + first.observed : "All observed stages completed." }
}
