// Strict, local-only validation for the Ping Host and DNS Lookup inputs.

function invalid(reason, message) {
  return { ok: false, reason: reason, message: message }
}

function valid(kind, value, displayValue) {
  return { ok: true, kind: kind, value: value, displayValue: displayValue === undefined ? value : displayValue }
}

function validateIpv4(value) {
  if (typeof value !== "string")
    return invalid("invalid-input", "Enter a host or IP address.")

  var octets = value.split(".")
  if (octets.length !== 4)
    return invalid("invalid-ipv4", "IPv4 addresses need exactly four decimal octets.")

  for (var i = 0; i < octets.length; i++) {
    var octet = octets[i]
    if (!/^[0-9]+$/.test(octet) || (octet.length > 1 && octet.charAt(0) === "0"))
      return invalid("invalid-ipv4", "IPv4 octets must be decimal without leading zeroes.")
    var numeric = Number(octet)
    if (!Number.isSafeInteger(numeric) || numeric < 0 || numeric > 255)
      return invalid("invalid-ipv4", "IPv4 octets must be between 0 and 255.")
  }
  return valid("ipv4", value, value)
}

function validateIpv6(value) {
  if (typeof value !== "string" || value.length === 0 || value.length > 45)
    return invalid("invalid-ipv6", "Enter a valid IPv6 literal.")

  var firstCompression = value.indexOf("::")
  if (firstCompression !== -1 && value.indexOf("::", firstCompression + 2) !== -1)
    return invalid("invalid-ipv6", "An IPv6 address can contain only one :: compression marker.")

  var compressed = firstCompression !== -1
  var parts
  if (compressed) {
    var leftText = value.slice(0, firstCompression)
    var rightText = value.slice(firstCompression + 2)
    var left = leftText === "" ? [] : leftText.split(":")
    var right = rightText === "" ? [] : rightText.split(":")
    parts = left.concat(right)
  } else {
    parts = value.split(":")
  }

  if (parts.length === 0 || parts.some(function(part) { return part.length === 0 }))
    return invalid("invalid-ipv6", "IPv6 groups cannot be empty outside :: compression.")

  var groups = 0
  for (var i = 0; i < parts.length; i++) {
    var part = parts[i]
    if (part.indexOf(".") !== -1) {
      if (i !== parts.length - 1)
        return invalid("invalid-ipv6", "An embedded IPv4 address must be the final IPv6 component.")
      var ipv4 = validateIpv4(part)
      if (!ipv4.ok)
        return invalid("invalid-ipv6", "The embedded IPv4 address is invalid.")
      groups += 2
    } else {
      if (!/^[0-9A-Fa-f]{1,4}$/.test(part))
        return invalid("invalid-ipv6", "IPv6 groups contain one to four hexadecimal digits.")
      groups += 1
    }
  }

  if ((compressed && groups >= 8) || (!compressed && groups !== 8))
    return invalid("invalid-ipv6", "IPv6 addresses must contain exactly 128 bits.")

  return valid("ipv6", value.toLowerCase(), value)
}

function validateName(value) {
  var rooted = value.charAt(value.length - 1) === "."
  var name = rooted ? value.slice(0, -1) : value
  if (name.length < 1 || name.length > 253)
    return invalid("invalid-name-length", "Names must be between 1 and 253 ASCII characters.")

  var labels = name.split(".")
  for (var i = 0; i < labels.length; i++) {
    var label = labels[i]
    if (label.length < 1 || label.length > 63)
      return invalid("invalid-label-length", "Each name label must be between 1 and 63 characters.")
    if (!/^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$/.test(label))
      return invalid("invalid-name", "Names may use ASCII letters, digits, and internal hyphens only.")
  }
  return valid("name", name.toLowerCase() + (rooted ? "." : ""), value)
}

function validateHostInput(value) {
  if (typeof value !== "string" || value.length === 0)
    return invalid("invalid-input", "Enter a host or IP address.")
  if (value !== value.trim())
    return invalid("whitespace", "Leading or trailing whitespace is not allowed.")
  if (/[\x00-\x1F\x7F]/.test(value))
    return invalid("control-character", "Control characters are not allowed.")
  if (!/^[\x00-\x7F]+$/.test(value))
    return invalid("unicode-idn", "Internationalized names must use ASCII punycode in v0.1.")
  if (value.charAt(0) === "-")
    return invalid("leading-hyphen", "A host cannot start with a hyphen.")
  if (value.indexOf(":") !== -1)
    return validateIpv6(value)
  if (/^[0-9.]+$/.test(value) && value.indexOf(".") !== -1)
    return validateIpv4(value)
  return validateName(value)
}

function validatePingTarget(value) {
  return validateHostInput(value)
}

function validateDnsName(value) {
  return validateHostInput(value)
}
