// Parsers for fixed Linux virtual files. They receive bounded text and never read files.

var MAX_DISPLAY_STRING = 256
var MAX_FIELD_STRING = 4096
var MAX_INPUT_LENGTH = 1024 * 1024
var MAX_RECORDS = 10000

function failure(reason, message) {
  return { ok: false, reason: reason, message: message }
}

function parsed(data, completeness, warnings) {
  return { ok: true, data: data, completeness: completeness || "complete", warnings: warnings || [] }
}

function finiteNonNegative(value) {
  return typeof value === "number" && Number.isFinite(value) && value >= 0
}

function boundedText(text, source) {
  if (typeof text !== "string")
    return failure("malformed-output", "Missing " + source + " text.")
  if (text.length > MAX_INPUT_LENGTH)
    return failure("output-limit", source + " text exceeds the parser limit.")
  return null
}

function normalizedField(value, name, allowEmpty, maximumLength) {
  if (typeof value !== "string")
    return failure("malformed-output", name + " must be a string.")
  if (/[\x00-\x1F\x7F]/.test(value))
    return failure("malformed-output", name + " contains control characters.")
  var normalized = value.trim()
  if (!allowEmpty && normalized === "")
    return failure("malformed-output", name + " cannot be empty.")
  if (normalized.length > (maximumLength || MAX_FIELD_STRING))
    return failure("output-limit", name + " exceeds the field limit.")
  return { ok: true, value: normalized }
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
  var bounded = boundedText(text, "/proc/stat")
  if (bounded !== null)
    return bounded
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

function calculateCpuUsage(first, second) {
  if (!first || !second || typeof first !== "object" || typeof second !== "object")
    return failure("malformed-output", "Two CPU counter samples are required.")
  var fields = ["user", "nice", "system", "idle", "iowait", "irq", "softirq", "steal", "total", "idleTotal"]
  for (var i = 0; i < fields.length; i++) {
    var name = fields[i]
    if (!Number.isSafeInteger(first[name]) || !Number.isSafeInteger(second[name])
        || first[name] < 0 || second[name] < first[name])
      return failure("non-monotonic-counters", "CPU counters did not increase monotonically.")
  }
  var totalDelta = second.total - first.total
  var idleDelta = second.idleTotal - first.idleTotal
  if (totalDelta <= 0 || idleDelta < 0 || idleDelta > totalDelta)
    return failure("non-monotonic-counters", "CPU counter deltas are impossible.")
  var usage = ((totalDelta - idleDelta) / totalDelta) * 100
  if (!finiteNonNegative(usage) || usage > 100)
    return failure("malformed-output", "CPU utilization is outside its valid range.")
  return parsed({ usagePercent: usage, totalDelta: totalDelta, idleDelta: idleDelta })
}

function parseCpuinfo(text) {
  var bounded = boundedText(text, "/proc/cpuinfo")
  if (bounded !== null)
    return bounded
  var lines = text.split(/\r?\n/)
  var processorIds = {}
  var logicalProcessors = 0
  var model = null
  for (var i = 0; i < lines.length; i++) {
    var processor = /^processor\s*:\s*([0-9]+)\s*$/.exec(lines[i])
    if (processor) {
      var id = parseUnsigned(processor[1])
      if (id === null || processorIds[processor[1]])
        return failure("malformed-output", "CPU processor records are invalid or duplicated.")
      processorIds[processor[1]] = true
      logicalProcessors += 1
      continue
    }
    var modelMatch = /^model name\s*:\s*(.*)$/.exec(lines[i])
    if (modelMatch && model === null) {
      var normalized = normalizedField(modelMatch[1], "CPU model", false, MAX_DISPLAY_STRING)
      if (!normalized.ok)
        return normalized
      model = normalized.value
    }
  }
  if (logicalProcessors < 1)
    return failure("malformed-output", "No logical processor records were found.")
  if (model === null)
    return parsed({ model: null, logicalProcessors: logicalProcessors }, "partial", ["CPU model is unavailable."])
  return parsed({ model: model, logicalProcessors: logicalProcessors })
}

function parseMeminfo(text) {
  var bounded = boundedText(text, "/proc/meminfo")
  if (bounded !== null)
    return bounded
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
  if ((values.SwapFree === undefined) !== (values.SwapTotal === undefined))
    return failure("malformed-output", "SwapTotal and SwapFree must appear together.")
  if (values.SwapFree !== undefined && values.SwapFree > values.SwapTotal)
    return failure("malformed-output", "Swap totals are impossible.")
  var warnings = []
  if (values.SwapTotal === undefined)
    warnings.push("Swap fields are unavailable.")
  return parsed({ total: values.MemTotal, available: values.MemAvailable,
    used: values.MemTotal - values.MemAvailable,
    memFree: values.MemFree === undefined ? null : values.MemFree,
    buffers: values.Buffers === undefined ? null : values.Buffers,
    cached: values.Cached === undefined ? null : values.Cached,
    swapTotal: values.SwapTotal === undefined ? null : values.SwapTotal,
    swapFree: values.SwapFree === undefined ? null : values.SwapFree,
    swapUsed: values.SwapTotal === undefined ? null : values.SwapTotal - values.SwapFree,
    swapConfigured: values.SwapTotal === undefined ? null : values.SwapTotal > 0 },
    warnings.length > 0 ? "partial" : "complete", warnings)
}

function parseUptime(text) {
  var bounded = boundedText(text, "/proc/uptime")
  if (bounded !== null)
    return bounded
  var fields = text.trim().split(/\s+/)
  var seconds = parseFinite(fields[0] || "")
  if (seconds === null)
    return failure("malformed-output", "Uptime must begin with a non-negative finite number.")
  return parsed({ seconds: seconds })
}

function parseLoadavg(text) {
  var bounded = boundedText(text, "/proc/loadavg")
  if (bounded !== null)
    return bounded
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
  var bounded = boundedText(text, "os-release")
  if (bounded !== null)
    return bounded
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

function parseSmallText(text, label, maximumLength) {
  var bounded = boundedText(text, label)
  if (bounded !== null)
    return bounded
  var withoutFinalNewline = text.replace(/(?:\r?\n)$/, "")
  if (/[\r\n]/.test(withoutFinalNewline))
    return failure("malformed-output", label + " must contain exactly one line.")
  var normalized = normalizedField(withoutFinalNewline, label, false, maximumLength)
  if (!normalized.ok)
    return normalized
  return parsed({ value: normalized.value })
}

function parseHostname(text) {
  return parseSmallText(text, "Hostname", 64)
}

function parseKernelText(text) {
  return parseSmallText(text, "Kernel value", MAX_DISPLAY_STRING)
}

function jsonObject(text, source) {
  var bounded = boundedText(text, source)
  if (bounded !== null)
    return bounded
  var value
  try {
    value = JSON.parse(text)
  } catch (error) {
    return failure("malformed-output", source + " emitted malformed JSON.")
  }
  if (!value || typeof value !== "object" || Array.isArray(value))
    return failure("malformed-output", source + " JSON must be an object.")
  return { ok: true, value: value }
}

function jsonString(record, key, allowEmpty) {
  if (!Object.prototype.hasOwnProperty.call(record, key))
    return failure("malformed-output", "Filesystem field " + key + " is missing.")
  return normalizedField(record[key], "Filesystem field " + key, allowEmpty, MAX_FIELD_STRING)
}

function jsonBytes(record, key) {
  var value = record[key]
  if (!Number.isSafeInteger(value) || value < 0)
    return failure("malformed-output", "Filesystem field " + key + " must be a non-negative integer.")
  return { ok: true, value: value }
}

function parseFindmntJson(text, optionsRequired) {
  var decoded = jsonObject(text, "findmnt")
  if (!decoded.ok)
    return decoded
  if (!Array.isArray(decoded.value.filesystems))
    return failure("malformed-output", "findmnt JSON needs a filesystems array.")
  if (decoded.value.filesystems.length > MAX_RECORDS)
    return failure("output-limit", "findmnt returned too many filesystem records.")

  var records = []
  for (var i = 0; i < decoded.value.filesystems.length; i++) {
    var item = decoded.value.filesystems[i]
    if (!item || typeof item !== "object" || Array.isArray(item))
      return failure("malformed-output", "A filesystem record is not an object.")
    var source = jsonString(item, "source", false)
    var fstype = jsonString(item, "fstype", false)
    var target = jsonString(item, "target", false)
    var size = jsonBytes(item, "size")
    var used = jsonBytes(item, "used")
    var available = jsonBytes(item, "avail")
    if (!source.ok || !fstype.ok || !target.ok || !size.ok || !used.ok || !available.ok)
      return !source.ok ? source : !fstype.ok ? fstype : !target.ok ? target : !size.ok ? size : !used.ok ? used : available
    if (size.value === 0 || used.value > size.value || available.value > size.value)
      return failure("malformed-output", "Filesystem capacity values are impossible.")
    var percentMatch = typeof item["use%"] === "string"
      ? /^(100|[0-9]{1,2})%$/.exec(item["use%"])
      : null
    if (!percentMatch)
      return failure("malformed-output", "Filesystem use% must be an integer percentage.")
    var options = null
    if (optionsRequired) {
      var parsedOptions = jsonString(item, "options", true)
      if (!parsedOptions.ok)
        return parsedOptions
      options = parsedOptions.value
    } else if (item.options !== undefined) {
      var optionalOptions = jsonString(item, "options", true)
      if (!optionalOptions.ok)
        return optionalOptions
      options = optionalOptions.value
    }
    var backingSource = source.value
    if (fstype.value === "btrfs") {
      var subvolume = backingSource.indexOf("[")
      if (subvolume > 0 && backingSource.charAt(backingSource.length - 1) === "]")
        backingSource = backingSource.slice(0, subvolume)
    }
    records.push({
      source: source.value,
      backingSource: backingSource,
      fstype: fstype.value,
      size: size.value,
      used: used.value,
      available: available.value,
      usePercent: Number(percentMatch[1]),
      target: target.value,
      options: options
    })
  }
  return parsed({ filesystems: records })
}

function parseRootFindmntJson(text) {
  var result = parseFindmntJson(text, false)
  if (!result.ok)
    return result
  if (result.data.filesystems.length !== 1 || result.data.filesystems[0].target !== "/")
    return failure("malformed-output", "Root findmnt JSON must contain exactly the root filesystem.")
  return parsed(result.data.filesystems[0])
}

function parseDiskUsageFindmntJson(text) {
  return parseFindmntJson(text, true)
}

function parseFailedUnitsJson(text, scope) {
  if (scope !== "system" && scope !== "user")
    return failure("invalid-scope", "Failed-unit scope must be system or user.")
  var bounded = boundedText(text, "systemctl")
  if (bounded !== null)
    return bounded
  var rows
  try {
    rows = JSON.parse(text)
  } catch (error) {
    return failure("malformed-output", "systemctl emitted malformed JSON.")
  }
  if (!Array.isArray(rows))
    return failure("malformed-output", "systemctl JSON must be an array.")
  if (rows.length > MAX_RECORDS)
    return failure("output-limit", "systemctl returned too many failed units.")
  var units = []
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    if (!row || typeof row !== "object" || Array.isArray(row))
      return failure("malformed-output", "A failed-unit record is not an object.")
    var keys = ["unit", "load", "active", "sub", "description"]
    var values = {}
    for (var j = 0; j < keys.length; j++) {
      var value = normalizedField(row[keys[j]], "Failed-unit field " + keys[j], false,
        keys[j] === "description" ? MAX_FIELD_STRING : MAX_DISPLAY_STRING)
      if (!value.ok)
        return value
      values[keys[j]] = value.value
    }
    if (values.active !== "failed")
      return failure("malformed-output", "A unit returned by --failed is not in the failed state.")
    units.push({ unit: values.unit, load: values.load, active: values.active,
      sub: values.sub, description: values.description, scope: scope })
  }
  return parsed({ scope: scope, units: units, count: units.length })
}

function parseSystemdSystemState(text) {
  var value = parseSmallText(text, "systemd system state", 32)
  if (!value.ok)
    return value
  var allowed = { running: true, degraded: true, maintenance: true, initializing: true,
    starting: true, stopping: true, offline: true, unknown: true }
  if (!allowed[value.data.value])
    return failure("malformed-output", "systemd returned an unknown system state.")
  return parsed({ state: value.data.value })
}
