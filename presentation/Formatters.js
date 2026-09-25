// Display-only helpers. Values have already been parsed and validated by services.
function bytes(value) {
  var number = Number(value)
  if (!Number.isFinite(number) || number < 0) return "Unavailable"
  var units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"]
  var index = 0
  while (number >= 1024 && index < units.length - 1) { number /= 1024; index++ }
  return (index === 0 ? Math.round(number) : number.toFixed(number >= 10 ? 0 : 1)) + " " + units[index]
}

function percent(value) {
  var number = Number(value)
  return Number.isFinite(number) ? number.toFixed(number >= 10 ? 0 : 1) + "%" : "Unavailable"
}

function duration(seconds) {
  var value = Math.floor(Number(seconds))
  if (!Number.isFinite(value) || value < 0) return "Unavailable"
  var days = Math.floor(value / 86400); value %= 86400
  var hours = Math.floor(value / 3600); value %= 3600
  var minutes = Math.floor(value / 60)
  var parts = []
  if (days) parts.push(days + "d")
  if (hours || days) parts.push(hours + "h")
  parts.push(minutes + "m")
  return parts.join(" ")
}

function load(value) {
  var number = Number(value)
  return Number.isFinite(number) ? number.toFixed(2) : "Unavailable"
}

function timestamp(value) {
  var time = Date.parse(value || "")
  return Number.isFinite(time) ? new Date(time).toLocaleTimeString() : "Not observed"
}
