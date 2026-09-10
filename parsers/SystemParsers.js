// Parsers for fixed Linux virtual files. They receive bounded text and never read files.

var MAX_DISPLAY_STRING = 256

function failure(reason, message) {
  return { ok: false, reason: reason, message: message }
}

function parsed(data, completeness, warnings) {
  return { ok: true, data: data, completeness: completeness || "complete", warnings: warnings || [] }
}

function finiteNonNegative(value) {
  return typeof value === "number" && Number.isFinite(value) && value >= 0
}

function parseUnsigned(text) {
  if (!/^[0-9]+$/.test(text))
    return null
  var value = Number(text)
  return Number.isSafeInteger(value) && value >= 0 ? value : null
}

function parseFinite(text) {
  if (!/^(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)$/.test(text))
    return null
  var value = Number(text)
  return finiteNonNegative(value) ? value : null
}

function parseProcStat(text) {
  if (typeof text !== "string")
    return failure("malformed-output", "Missing /proc/stat text.")
  var lines = text.split(/\r?\n/)
  var cpuLine = null
  for (var i = 0; i < lines.length; i++) {
    if (/^cpu(?:\s|$)/.test(lines[i])) {
      cpuLine = lines[i]
      break
    }
  }
  if (cpuLine === null)
    return failure("malformed-output", "Aggregate CPU counters are missing.")
  var fields = cpuLine.trim().split(/\s+/)
  if (fields.length < 5)
    return failure("malformed-output", "Aggregate CPU counters are incomplete.")
  var counters = []
  for (var index = 1; index < fields.length; index++) {
    var counter = parseUnsigned(fields[index])
    if (counter === null)
      return failure("malformed-output", "Aggregate CPU counters must be non-negative integers.")
    counters.push(counter)
  }
  var user = counters[0]
  var nice = counters[1]
  var system = counters[2]
  var idle = counters[3]
  var iowait = counters.length > 4 ? counters[4] : 0
  var irq = counters.length > 5 ? counters[5] : 0
  var softirq = counters.length > 6 ? counters[6] : 0
  var steal = counters.length > 7 ? counters[7] : 0
  var guest = counters.length > 8 ? counters[8] : 0
  var guestNice = counters.length > 9 ? counters[9] : 0
  var total = user + nice + system + idle + iowait + irq + softirq + steal
  if (!Number.isSafeInteger(total) || total < idle + iowait || guest > user || guestNice > nice)
    return failure("malformed-output", "Aggregate CPU counter total is impossible.")
  return parsed({ user: user, nice: nice, system: system, idle: idle, iowait: iowait,
    irq: irq, softirq: softirq, steal: steal, guest: guest, guestNice: guestNice,
    idleTotal: idle + iowait, total: total })
}

function parseMeminfo(text) {
  if (typeof text !== "string")
    return failure("malformed-output", "Missing /proc/meminfo text.")
  var wanted = { MemTotal: true, MemAvailable: true, MemFree: true, Buffers: true,
    Cached: true, SwapTotal: true, SwapFree: true }
  var values = {}
  var lines = text.split(/\r?\n/)
  for (var i = 0; i < lines.length; i++) {
    if (lines[i] === "")
      continue
    var match = /^([A-Za-z_][A-Za-z0-9_]*):\s*([0-9]+)\s+kB\s*$/.exec(lines[i])
    if (!match) {
      if (/^(MemTotal|MemAvailable|MemFree|Buffers|Cached|SwapTotal|SwapFree):/.test(lines[i]))
        return failure("malformed-output", "A memory field has an invalid unit or value.")
      continue
    }
    if (wanted[match[1]]) {
      if (values[match[1]] !== undefined)
        return failure("malformed-output", "A memory field is duplicated.")
      var amount = parseUnsigned(match[2])
      if (amount === null)
        return failure("malformed-output", "Memory values must be non-negative integers.")
      values[match[1]] = amount * 1024
      if (!Number.isSafeInteger(values[match[1]]))
        return failure("malformed-output", "A memory value is too large.")
    }
  }
  if (values.MemTotal === undefined || values.MemAvailable === undefined)
    return failure("malformed-output", "MemTotal and MemAvailable are required.")
  if (values.MemTotal === 0 || values.MemAvailable > values.MemTotal)
    return failure("malformed-output", "Memory totals are impossible.")
  if (values.SwapFree !== undefined && values.SwapTotal !== undefined && values.SwapFree > values.SwapTotal)
    return failure("malformed-output", "Swap totals are impossible.")
  return parsed({ total: values.MemTotal, available: values.MemAvailable,
    used: values.MemTotal - values.MemAvailable,
    memFree: values.MemFree === undefined ? null : values.MemFree,
    buffers: values.Buffers === undefined ? null : values.Buffers,
    cached: values.Cached === undefined ? null : values.Cached,
    swapTotal: values.SwapTotal === undefined ? null : values.SwapTotal,
    swapFree: values.SwapFree === undefined ? null : values.SwapFree,
    swapUsed: values.SwapTotal === undefined || values.SwapFree === undefined ? null : values.SwapTotal - values.SwapFree })
}

function parseUptime(text) {
  if (typeof text !== "string")
    return failure("malformed-output", "Missing /proc/uptime text.")
  var fields = text.trim().split(/\s+/)
  var seconds = parseFinite(fields[0] || "")
  if (seconds === null)
    return failure("malformed-output", "Uptime must begin with a non-negative finite number.")
  return parsed({ seconds: seconds })
}

function parseLoadavg(text) {
  if (typeof text !== "string")
    return failure("malformed-output", "Missing /proc/loadavg text.")
  var fields = text.trim().split(/\s+/)
  if (fields.length < 5)
    return failure("malformed-output", "Load average fields are incomplete.")
  var one = parseFinite(fields[0])
  var five = parseFinite(fields[1])
  var fifteen = parseFinite(fields[2])
  var taskMatch = /^([0-9]+)\/([0-9]+)$/.exec(fields[3])
  var lastPid = parseUnsigned(fields[4])
  if (one === null || five === null || fifteen === null || !taskMatch || lastPid === null)
    return failure("malformed-output", "Load average fields are malformed.")
  var running = parseUnsigned(taskMatch[1])
  var total = parseUnsigned(taskMatch[2])
  if (running === null || total === null || total === 0 || running > total)
    return failure("malformed-output", "Load average task counts are impossible.")
  return parsed({ one: one, five: five, fifteen: fifteen, runningTasks: running,
    totalTasks: total, lastPid: lastPid })
}

function normalizeOsValue(value) {
  var normalized = value.replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, "").trim()
  return normalized.length > MAX_DISPLAY_STRING ? normalized.slice(0, MAX_DISPLAY_STRING) : normalized
}

function parseOsReleaseValue(raw) {
  if (raw.length === 0)
    return ""
  var quote = raw.charAt(0)
  if (quote !== "\"" && quote !== "'")
    return raw
  if (raw.length < 2 || raw.charAt(raw.length - 1) !== quote)
    return null
  var inner = raw.slice(1, -1)
  if (quote === "'")
    return inner
  var output = ""
  for (var i = 0; i < inner.length; i++) {
    if (inner.charAt(i) !== "\\") {
      output += inner.charAt(i)
      continue
    }
    i += 1
    if (i >= inner.length)
      return null
    var escaped = inner.charAt(i)
    if (escaped !== "\\" && escaped !== "\"" && escaped !== "$" && escaped !== "`")
      return null
    output += escaped
  }
  return output
}

function parseOsRelease(text) {
  if (typeof text !== "string")
    return failure("malformed-output", "Missing os-release text.")
  var values = {}
  var lines = text.split(/\r?\n/)
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line === "" || /^\s*#/.test(line))
      continue
    var match = /^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/.exec(line)
    if (!match)
      return failure("malformed-output", "os-release contains an invalid assignment.")
    if (values[match[1]] !== undefined)
      return failure("malformed-output", "os-release contains a duplicate key.")
    var decoded = parseOsReleaseValue(match[2])
    if (decoded === null)
      return failure("malformed-output", "os-release contains an invalid quoted value.")
    values[match[1]] = normalizeOsValue(decoded)
  }
  var prettyName = values.PRETTY_NAME || null
  var name = values.NAME || null
  var versionId = values.VERSION_ID || null
  if (!prettyName && !(name && versionId))
    return failure("malformed-output", "os-release needs PRETTY_NAME or NAME with VERSION_ID.")
  return parsed({ prettyName: prettyName, name: name, versionId: versionId,
    displayName: prettyName || (name + " " + versionId) })
}
