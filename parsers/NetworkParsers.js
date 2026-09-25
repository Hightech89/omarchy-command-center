// Strict pure parsers for the fixed iproute2, ss, ping, and resolvectl probes.

var MAX_INPUT_LENGTH = 1024 * 1024
var MAX_RECORDS = 10000
var MAX_FIELD_LENGTH = 4096
var MAX_DISPLAY_LENGTH = 256

function failure(reason, message) {
  return { ok: false, reason: reason, message: message }
}

function parsed(data, completeness, warnings) {
  return { ok: true, data: data, completeness: completeness || "complete", warnings: warnings || [] }
}

function bounded(text, source) {
  if (typeof text !== "string") return failure("malformed-output", source + " output is missing.")
  if (text.length > MAX_INPUT_LENGTH) return failure("output-limit", source + " output exceeds the parser limit.")
  return null
}

function cleanString(value, label, allowEmpty, maximum) {
  if (typeof value !== "string") return failure("malformed-output", label + " must be a string.")
  if (/[\x00-\x1F\x7F]/.test(value)) return failure("malformed-output", label + " contains control characters.")
  var result = value.trim()
  if (!allowEmpty && result === "") return failure("malformed-output", label + " cannot be empty.")
  if (result.length > (maximum || MAX_FIELD_LENGTH)) return failure("output-limit", label + " exceeds the field limit.")
  return { ok: true, value: result }
}

function jsonArray(text, source) {
  var limit = bounded(text, source)
  if (limit) return limit
  var value
  try { value = JSON.parse(text) } catch (error) { return failure("malformed-output", source + " emitted malformed JSON.") }
  if (!Array.isArray(value)) return failure("malformed-output", source + " JSON must be an array.")
  if (value.length > MAX_RECORDS) return failure("output-limit", source + " returned too many records.")
  return { ok: true, value: value }
}

function safeInteger(value, minimum, maximum) {
  return Number.isSafeInteger(value) && value >= minimum && value <= maximum
}

function validIpv4(value) {
  if (typeof value !== "string") return false
  var parts = value.split(".")
  if (parts.length !== 4) return false
  for (var i = 0; i < parts.length; i++) {
    if (!/^[0-9]+$/.test(parts[i]) || (parts[i].length > 1 && parts[i].charAt(0) === "0")) return false
    var part = Number(parts[i])
    if (!safeInteger(part, 0, 255)) return false
  }
  return true
}

function validIpv6(value) {
  if (typeof value !== "string" || value.length < 2 || value.length > 45 || value.indexOf("%") !== -1) return false
  var marker = value.indexOf("::")
  if (marker !== -1 && value.indexOf("::", marker + 2) !== -1) return false
  var compressed = marker !== -1
  var parts = compressed
    ? (value.slice(0, marker) === "" ? [] : value.slice(0, marker).split(":"))
        .concat(value.slice(marker + 2) === "" ? [] : value.slice(marker + 2).split(":"))
    : value.split(":")
  if (parts.some(function(part) { return part === "" })) return false
  var groups = 0
  for (var i = 0; i < parts.length; i++) {
    if (parts[i].indexOf(".") !== -1) {
      if (i !== parts.length - 1 || !validIpv4(parts[i])) return false
      groups += 2
    } else {
      if (!/^[0-9A-Fa-f]{1,4}$/.test(parts[i])) return false
      groups += 1
    }
  }
  return compressed ? groups < 8 : groups === 8
}

function ipFamily(value) {
  if (validIpv4(value)) return "ipv4"
  if (validIpv6(value)) return "ipv6"
  return null
}

function optionalString(record, key, label) {
  if (record[key] === undefined || record[key] === null) return { ok: true, value: null }
  return cleanString(record[key], label, false, MAX_DISPLAY_LENGTH)
}

function parseIpRouteJson(text) {
  var decoded = jsonArray(text, "ip route")
  if (!decoded.ok) return decoded
  var routes = []
  for (var i = 0; i < decoded.value.length; i++) {
    var row = decoded.value[i]
    if (!row || typeof row !== "object" || Array.isArray(row)) return failure("malformed-output", "An ip route record is not an object.")
    var dst = cleanString(row.dst, "Route destination", false, MAX_DISPLAY_LENGTH)
    if (!dst.ok || dst.value !== "default") return failure("malformed-output", "Every requested route must be a default route.")
    var dev = optionalString(row, "dev", "Route interface")
    var gateway = optionalString(row, "gateway", "Route gateway")
    var prefsrc = optionalString(row, "prefsrc", "Route preferred source")
    var protocol = optionalString(row, "protocol", "Route protocol")
    if (!dev.ok || !gateway.ok || !prefsrc.ok || !protocol.ok) return !dev.ok ? dev : !gateway.ok ? gateway : !prefsrc.ok ? prefsrc : protocol
    if (gateway.value !== null && ipFamily(gateway.value) === null) return failure("malformed-output", "Route gateway is not an IP address.")
    if (prefsrc.value !== null && ipFamily(prefsrc.value) === null) return failure("malformed-output", "Route preferred source is not an IP address.")
    var metric = row.metric === undefined ? null : row.metric
    if (metric !== null && !safeInteger(metric, 0, 4294967295)) return failure("malformed-output", "Route metric is invalid.")
    if (row.flags !== undefined && (!Array.isArray(row.flags) || row.flags.some(function(flag) { return typeof flag !== "string" })))
      return failure("malformed-output", "Route flags must be strings.")
    routes.push({ destination: "default", interfaceName: dev.value, gateway: gateway.value,
      preferredSource: prefsrc.value, metric: metric, protocol: protocol.value,
      family: gateway.value ? ipFamily(gateway.value) : (prefsrc.value ? ipFamily(prefsrc.value) : null) })
  }
  return parsed({ routes: routes })
}

function parseIpLinkJson(text) {
  var decoded = jsonArray(text, "ip link")
  if (!decoded.ok) return decoded
  var links = []
  var names = {}
  for (var i = 0; i < decoded.value.length; i++) {
    var row = decoded.value[i]
    if (!row || typeof row !== "object" || Array.isArray(row)) return failure("malformed-output", "An ip link record is not an object.")
    if (!safeInteger(row.ifindex, 1, 2147483647)) return failure("malformed-output", "Link ifindex is invalid.")
    var name = cleanString(row.ifname, "Link name", false, MAX_DISPLAY_LENGTH)
    var state = cleanString(row.operstate, "Link operational state", false, 32)
    if (!name.ok || !state.ok) return !name.ok ? name : state
    if (names[name.value]) return failure("malformed-output", "Link names must be unique.")
    if (!Array.isArray(row.flags) || row.flags.some(function(flag) { return typeof flag !== "string" || flag.length > 64 }))
      return failure("malformed-output", "Link flags must be a bounded string array.")
    names[name.value] = true
    var flags = row.flags.slice()
    links.push({ index: row.ifindex, name: name.value, operationalState: state.value,
      flags: flags, administrativelyUp: flags.indexOf("UP") !== -1,
      carrierUp: flags.indexOf("LOWER_UP") !== -1,
      pointToPoint: flags.indexOf("POINTOPOINT") !== -1,
      loopback: flags.indexOf("LOOPBACK") !== -1 || row.link_type === "loopback" })
  }
  return parsed({ links: links })
}

function ipv4LinkLocal(value) {
  var parts = value.split(".")
  return parts[0] === "169" && parts[1] === "254"
}

function ipv6LinkLocal(value) {
  var first = parseInt(value.split(":")[0] || "0", 16)
  return Number.isFinite(first) && (first & 0xffc0) === 0xfe80
}

function usableUnicast(family, value) {
  if (family === "ipv4") {
    var first = Number(value.split(".")[0])
    return first !== 0 && first !== 127 && first < 224 && value !== "255.255.255.255" && !ipv4LinkLocal(value)
  }
  var normalized = value.toLowerCase()
  return normalized !== "::" && normalized !== "::1" && normalized.indexOf("ff") !== 0 && !ipv6LinkLocal(normalized)
}

function parseIpAddressJson(text) {
  var decoded = jsonArray(text, "ip address")
  if (!decoded.ok) return decoded
  var interfaces = []
  for (var i = 0; i < decoded.value.length; i++) {
    var row = decoded.value[i]
    if (!row || typeof row !== "object" || Array.isArray(row)) return failure("malformed-output", "An ip address interface record is not an object.")
    if (!safeInteger(row.ifindex, 1, 2147483647)) return failure("malformed-output", "Address ifindex is invalid.")
    var name = cleanString(row.ifname, "Address interface name", false, MAX_DISPLAY_LENGTH)
    if (!name.ok || !Array.isArray(row.addr_info)) return !name.ok ? name : failure("malformed-output", "Address records need an addr_info array.")
    if (row.addr_info.length > MAX_RECORDS) return failure("output-limit", "An interface has too many addresses.")
    var addresses = []
    for (var j = 0; j < row.addr_info.length; j++) {
      var info = row.addr_info[j]
      if (!info || typeof info !== "object" || Array.isArray(info)) return failure("malformed-output", "An address record is not an object.")
      if (info.family !== "inet" && info.family !== "inet6") return failure("malformed-output", "Address family must be inet or inet6.")
      var local = cleanString(info.local, "Local address", false, MAX_DISPLAY_LENGTH)
      var scope = cleanString(info.scope, "Address scope", false, 32)
      if (!local.ok || !scope.ok) return !local.ok ? local : scope
      var family = info.family === "inet" ? "ipv4" : "ipv6"
      if (ipFamily(local.value) !== family) return failure("malformed-output", "Local address does not match its family.")
      var maximumPrefix = family === "ipv4" ? 32 : 128
      if (!safeInteger(info.prefixlen, 0, maximumPrefix)) return failure("malformed-output", "Address prefix length is invalid.")
      var loopback = scope.value === "host" || local.value === "127.0.0.1" || local.value.toLowerCase() === "::1"
      var linkLocal = scope.value === "link" || (family === "ipv4" ? ipv4LinkLocal(local.value) : ipv6LinkLocal(local.value))
      addresses.push({ family: family, address: local.value.toLowerCase(), prefixLength: info.prefixlen,
        scope: scope.value, loopback: loopback, linkLocal: linkLocal,
        usableGlobal: scope.value === "global" && !loopback && !linkLocal && usableUnicast(family, local.value) })
    }
    interfaces.push({ index: row.ifindex, name: name.value, addresses: addresses })
  }
  return parsed({ interfaces: interfaces })
}

function parseDnsServer(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return failure("malformed-output", label + " is not an object.")
  var address = cleanString(value.addressString, label + " address", false, MAX_DISPLAY_LENGTH)
  if (!address.ok || ipFamily(address.value) === null) return address.ok ? failure("malformed-output", label + " address is invalid.") : address
  if (value.port !== undefined && !safeInteger(value.port, 1, 65535)) return failure("malformed-output", label + " port is invalid.")
  return { ok: true, value: { address: address.value.toLowerCase(), family: ipFamily(address.value),
    port: value.port === undefined ? 53 : value.port, accessible: typeof value.accessible === "boolean" ? value.accessible : null } }
}

function parseResolvectlStatusJson(text) {
  var decoded = jsonArray(text, "resolvectl status")
  if (!decoded.ok) return decoded
  var global = null
  var links = []
  for (var i = 0; i < decoded.value.length; i++) {
    var row = decoded.value[i]
    if (!row || typeof row !== "object" || Array.isArray(row)) return failure("malformed-output", "A resolver status record is not an object.")
    var isLink = row.ifindex !== undefined || row.ifname !== undefined
    if (isLink && (!safeInteger(row.ifindex, 1, 2147483647) || typeof row.ifname !== "string" || row.ifname.length < 1 || row.ifname.length > MAX_DISPLAY_LENGTH))
      return failure("malformed-output", "Resolver link identity is invalid.")
    var rawServers = row.servers === undefined ? [] : row.servers
    if (!Array.isArray(rawServers) || rawServers.length > MAX_RECORDS) return failure("malformed-output", "Resolver servers must be a bounded array.")
    var servers = []
    for (var j = 0; j < rawServers.length; j++) {
      var server = parseDnsServer(rawServers[j], "DNS server")
      if (!server.ok) return server
      if (!servers.some(function(item) { return item.address === server.value.address && item.port === server.value.port })) servers.push(server.value)
    }
    var currentServer = null
    if (row.currentServer !== undefined) {
      var current = parseDnsServer(row.currentServer, "Current DNS server")
      if (!current.ok) return current
      currentServer = current.value
    }
    var rawDomains = row.searchDomains === undefined ? [] : row.searchDomains
    if (!Array.isArray(rawDomains) || rawDomains.length > MAX_RECORDS) return failure("malformed-output", "Resolver search domains must be a bounded array.")
    var domains = []
    for (var k = 0; k < rawDomains.length; k++) {
      var domainRow = rawDomains[k]
      if (!domainRow || typeof domainRow !== "object" || Array.isArray(domainRow)) return failure("malformed-output", "A resolver search domain is not an object.")
      var domain = cleanString(domainRow.name, "Search domain", false, MAX_DISPLAY_LENGTH)
      if (!domain.ok || (domainRow.routeOnly !== undefined && typeof domainRow.routeOnly !== "boolean")) return domain.ok ? failure("malformed-output", "Search-domain routeOnly must be boolean.") : domain
      domains.push({ name: domain.value, routeOnly: domainRow.routeOnly === true })
    }
    var entry = { interfaceName: isLink ? row.ifname : null, interfaceIndex: isLink ? row.ifindex : null,
      defaultRoute: typeof row.defaultRoute === "boolean" ? row.defaultRoute : null,
      currentServer: currentServer, servers: servers, searchDomains: domains }
    if (isLink) links.push(entry)
    else if (global === null) global = entry
    else return failure("malformed-output", "Resolver status has multiple global records.")
  }
  return parsed({ global: global, links: links }, global === null ? "partial" : "complete",
    global === null ? ["Global resolver status is unavailable."] : [])
}

function endpoint(value, label, local) {
  var field = cleanString(value, label, false, MAX_DISPLAY_LENGTH)
  if (!field.ok) return field
  var text = field.value
  var address
  var portText
  if (text.charAt(0) === "[") {
    var close = text.lastIndexOf("]:")
    if (close < 2) return failure("malformed-output", label + " bracketed endpoint is invalid.")
    address = text.slice(1, close)
    portText = text.slice(close + 2)
  } else {
    var colon = text.lastIndexOf(":")
    if (colon < 1) return failure("malformed-output", label + " endpoint is missing a port.")
    address = text.slice(0, colon)
    portText = text.slice(colon + 1)
  }
  var zone = null
  var percent = address.lastIndexOf("%")
  if (percent > 0) { zone = address.slice(percent + 1); address = address.slice(0, percent) }
  if (address === "") address = "::"
  if (address !== "*" && ipFamily(address) === null) return failure("malformed-output", label + " address is invalid.")
  var port = portText === "*" ? null : Number(portText)
  if ((portText !== "*" && (!/^[0-9]+$/.test(portText) || !safeInteger(port, 0, 65535))) || (local && port === null))
    return failure("malformed-output", label + " port is invalid.")
  return { ok: true, value: { address: address.toLowerCase(), port: port, wildcard: address === "*" || address === "0.0.0.0" || address === "::", zone: zone } }
}

function parseOwners(metadata) {
  if (metadata === undefined || metadata === "") return { ok: true, value: [] }
  if (metadata.length > MAX_FIELD_LENGTH || metadata.indexOf("users:(") !== 0) return failure("malformed-output", "Socket owner metadata is malformed.")
  if (metadata.charAt(metadata.length - 1) !== ")") return failure("malformed-output", "Socket owner metadata is unterminated.")
  var body = metadata.slice(7, -1)
  var owners = []
  var pattern = /\("([^"\x00-\x1F]{1,256})",pid=([0-9]+),fd=([0-9]+)\)/g
  var match
  while ((match = pattern.exec(metadata)) !== null) {
    var pid = Number(match[2]); var fd = Number(match[3])
    if (!safeInteger(pid, 1, 2147483647) || !safeInteger(fd, 0, 2147483647)) return failure("malformed-output", "Socket owner numbers are invalid.")
    owners.push({ process: match[1], pid: pid, fd: fd })
  }
  if (owners.length === 0) return failure("malformed-output", "Socket owner metadata has no valid owner record.")
  if (body.replace(pattern, "").replace(/,/g, "").trim() !== "") return failure("malformed-output", "Socket owner metadata contains unsupported fields.")
  return { ok: true, value: owners }
}

function parseSsListening(text) {
  var limit = bounded(text, "ss")
  if (limit) return limit
  var lines = text.split(/\r?\n/).filter(function(line) { return line !== "" })
  if (lines.length > MAX_RECORDS) return failure("output-limit", "ss returned too many socket rows.")
  var sockets = []
  for (var i = 0; i < lines.length; i++) {
    var match = /^(\S+)\s+(\S+)\s+([0-9]+)\s+([0-9]+)\s+(\S+)\s+(\S+)(?:\s+(.*))?$/.exec(lines[i])
    if (!match) return failure("malformed-output", "An ss row is malformed.")
    if (match[1] !== "tcp" && match[1] !== "udp") return failure("malformed-output", "Socket protocol must be tcp or udp.")
    var receiveQueue = Number(match[3]); var sendQueue = Number(match[4])
    if (!safeInteger(receiveQueue, 0, Number.MAX_SAFE_INTEGER) || !safeInteger(sendQueue, 0, Number.MAX_SAFE_INTEGER)) return failure("malformed-output", "Socket queue sizes are invalid.")
    var localEndpoint = endpoint(match[5], "Local socket", true)
    var peerEndpoint = endpoint(match[6], "Peer socket", false)
    var owners = parseOwners(match[7])
    if (!localEndpoint.ok || !peerEndpoint.ok || !owners.ok) return !localEndpoint.ok ? localEndpoint : !peerEndpoint.ok ? peerEndpoint : owners
    sockets.push({ protocol: match[1], state: match[2], receiveQueue: receiveQueue, sendQueue: sendQueue,
      localAddress: localEndpoint.value.address, localPort: localEndpoint.value.port,
      localWildcard: localEndpoint.value.wildcard, localZone: localEndpoint.value.zone,
      peerAddress: peerEndpoint.value.address, peerPort: peerEndpoint.value.port,
      owners: owners.value, ownerAvailable: owners.value.length > 0 })
  }
  return parsed({ sockets: sockets, count: sockets.length })
}

function parsePingSummary(text) {
  var limit = bounded(text, "ping")
  if (limit) return limit
  var summary = /(?:^|\n)([0-9]+) packets transmitted, ([0-9]+) received(?:, \+([0-9]+) errors)?, ([0-9]+(?:\.[0-9]+)?)% packet loss(?:, time [^\r\n]+)?(?:\r?\n|$)/.exec(text)
  if (!summary) return failure("malformed-output", "Ping packet summary is missing or malformed.")
  var transmitted = Number(summary[1]); var received = Number(summary[2]); var loss = Number(summary[4])
  if (!safeInteger(transmitted, 1, 1000000) || !safeInteger(received, 0, transmitted) || !Number.isFinite(loss) || loss < 0 || loss > 100)
    return failure("malformed-output", "Ping packet totals are impossible.")
  var expectedLoss = (transmitted - received) * 100 / transmitted
  if (Math.abs(expectedLoss - loss) > 0.11) return failure("malformed-output", "Ping loss percentage disagrees with packet totals.")
  var latencyMatch = /(?:^|\n)(?:rtt|round-trip) min\/avg\/max\/(?:mdev|stddev) = ([0-9.]+)\/([0-9.]+)\/([0-9.]+)\/([0-9.]+) ms(?:\r?\n|$)/.exec(text)
  var latency = null
  if (received > 0 && !latencyMatch) return failure("malformed-output", "Ping latency summary is missing despite received replies.")
  if (latencyMatch) {
    var values = latencyMatch.slice(1).map(Number)
    if (values.some(function(value) { return !Number.isFinite(value) || value < 0 }) || values[0] > values[1] || values[1] > values[2])
      return failure("malformed-output", "Ping latency values are impossible.")
    latency = { minimumMs: values[0], averageMs: values[1], maximumMs: values[2], deviationMs: values[3] }
  }
  return parsed({ transmitted: transmitted, received: received, packetLossPercent: loss,
    latency: latency, replied: received > 0 })
}

function ipv6FromBytes(bytes) {
  var groups = []
  for (var i = 0; i < 16; i += 2) groups.push(((bytes[i] << 8) | bytes[i + 1]).toString(16))
  var bestStart = -1; var bestLength = 0; var start = -1
  for (var j = 0; j <= groups.length; j++) {
    if (j < groups.length && groups[j] === "0") { if (start === -1) start = j }
    else if (start !== -1) { if (j - start > bestLength) { bestStart = start; bestLength = j - start } start = -1 }
  }
  if (bestLength < 2) return groups.join(":")
  var left = groups.slice(0, bestStart).join(":")
  var right = groups.slice(bestStart + bestLength).join(":")
  return left + "::" + right
}

function parseResolvectlDnsQueryJsonLines(text, expectedFamily) {
  if (expectedFamily !== "A" && expectedFamily !== "AAAA") return failure("invalid-family", "DNS family must be A or AAAA.")
  var limit = bounded(text, "resolvectl query")
  if (limit) return limit
  var lines = text.split(/\r?\n/).filter(function(line) { return line.trim() !== "" })
  if (lines.length > MAX_RECORDS) return failure("output-limit", "resolvectl returned too many DNS records.")
  var answers = []
  var expectedType = expectedFamily === "A" ? 1 : 28
  var expectedLength = expectedFamily === "A" ? 4 : 16
  for (var i = 0; i < lines.length; i++) {
    var row
    try { row = JSON.parse(lines[i]) } catch (error) { return failure("malformed-output", "resolvectl query emitted a malformed JSON line.") }
    if (!row || typeof row !== "object" || Array.isArray(row) || !row.key || typeof row.key !== "object" || Array.isArray(row.key))
      return failure("malformed-output", "A DNS answer record is malformed.")
    if (row.key.class !== 1 || row.key.type !== expectedType || typeof row.key.name !== "string" || row.key.name.length < 1 || row.key.name.length > 253)
      return failure("malformed-output", "A DNS answer key does not match the requested family.")
    if (!Array.isArray(row.address) || row.address.length !== expectedLength || row.address.some(function(byte) { return !safeInteger(byte, 0, 255) }))
      return failure("malformed-output", "A DNS answer address byte array is invalid.")
    var address = expectedFamily === "A" ? row.address.join(".") : ipv6FromBytes(row.address)
    if (answers.indexOf(address) === -1) answers.push(address)
  }
  return parsed({ family: expectedFamily, answers: answers, count: answers.length })
}

function parseResolvectlDnsNegative(text) {
  var limit = bounded(text, "resolvectl error")
  if (limit) return limit
  var value = text.trim()
  if (/^[^\r\n]{1,253}: resolve call failed: Name '[^'\r\n]{1,253}' not found$/.test(value))
    return parsed({ negative: true, reason: "not-found" })
  if (/^[^\r\n]{1,253}: resolve call failed: No appropriate name servers or networks/.test(value))
    return parsed({ negative: true, reason: "no-answer" })
  return failure("execution-failed", "resolvectl did not report a recognized negative DNS response.")
}

function selectPrimaryRoute(routes) {
  var candidates = (Array.isArray(routes) ? routes : []).filter(function(route) {
    return route && route.destination === "default" && typeof route.interfaceName === "string"
      && route.interfaceName !== "" && route.interfaceName !== "lo"
  })
  function compareText(left, right) { return left < right ? -1 : left > right ? 1 : 0 }
  candidates.sort(function(left, right) {
    var leftMetric = left.metric === null ? 0 : left.metric
    var rightMetric = right.metric === null ? 0 : right.metric
    return leftMetric - rightMetric
      || compareText(left.interfaceName, right.interfaceName)
      || compareText(String(left.gateway || ""), String(right.gateway || ""))
      || compareText(String(left.preferredSource || ""), String(right.preferredSource || ""))
  })
  if (candidates.length === 0) return { route: null, equalBestCount: 0, multipleRoutes: false, ambiguous: false }
  var bestMetric = candidates[0].metric === null ? 0 : candidates[0].metric
  var equalBestCount = candidates.filter(function(route) { return (route.metric === null ? 0 : route.metric) === bestMetric }).length
  return { route: candidates[0], equalBestCount: equalBestCount, multipleRoutes: candidates.length > 1, ambiguous: equalBestCount > 1 }
}

function deriveNetworkOverview(routeData, linkData, addressData, dnsData) {
  var selected = selectPrimaryRoute(routeData.routes)
  if (selected.route === null) return parsed({ connectionState: "no-default-route", primaryInterface: null,
    route: null, routeSelection: selected, ipv4: [], ipv6: [], linkLocal: [], dnsServers: [], searchDomains: [] })
  var route = selected.route
  var link = linkData.links.filter(function(item) { return item.name === route.interfaceName })[0] || null
  var addressInterface = addressData.interfaces.filter(function(item) { return item.name === route.interfaceName })[0] || null
  var allAddresses = addressInterface ? addressInterface.addresses : []
  var usable = allAddresses.filter(function(item) { return item.usableGlobal })
  if (route.preferredSource) {
    var preferred = usable.filter(function(item) { return item.address === route.preferredSource.toLowerCase() })
    if (preferred.length > 0) usable = preferred.concat(usable.filter(function(item) { return item !== preferred[0] }))
  }
  var ipv4 = usable.filter(function(item) { return item.family === "ipv4" }).map(function(item) { return item.address })
  var ipv6 = usable.filter(function(item) { return item.family === "ipv6" }).map(function(item) { return item.address })
  var linkLocal = allAddresses.filter(function(item) { return item.linkLocal && !item.loopback }).map(function(item) { return item.address })
  var dnsLink = dnsData.links.filter(function(item) { return item.interfaceName === route.interfaceName })[0] || null
  var dnsSource = dnsLink || dnsData.global
  var servers = dnsSource ? dnsSource.servers.slice() : []
  if (dnsSource && dnsSource.currentServer && !servers.some(function(item) { return item.address === dnsSource.currentServer.address && item.port === dnsSource.currentServer.port }))
    servers.unshift(dnsSource.currentServer)
  var connectionState = !link ? "interface-unavailable"
    : (!link.administrativelyUp || (!link.carrierUp && !link.pointToPoint)) ? "interface-down"
    : (ipv4.length === 0 && ipv6.length === 0) ? "no-usable-address" : "connected-local"
  return parsed({ connectionState: connectionState, primaryInterface: link,
    route: route, routeSelection: selected, ipv4: ipv4, ipv6: ipv6, linkLocal: linkLocal,
    dnsServers: servers, searchDomains: dnsSource ? dnsSource.searchDomains.slice() : [] },
    dnsSource ? "complete" : "partial", dnsSource ? [] : ["DNS information is unavailable for the selected interface."])
}
