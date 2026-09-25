// Discoverability metadata only. Services—not this catalog—will eventually
// map trusted action IDs to fixed process requests.

var Actions = Object.freeze([
  {
    id: "system.overview",
    name: "System Overview",
    description: "Inspect hostname, operating system, kernel, uptime, CPU, memory, storage, and load.",
    category: "System",
    keywords: ["system", "overview", "hostname", "operating-system", "kernel", "uptime", "cpu", "memory", "ram", "storage", "load"],
    risk: "read-only",
    inputKind: "none",
    resultView: "system-overview",
    learningLabel: "Linux system information"
  },
  {
    id: "system.disk-usage",
    name: "Disk Usage",
    description: "Inspect mounted filesystems, capacity, available space, and usage without scanning files.",
    category: "System",
    keywords: ["system", "disk", "storage", "filesystem", "mount", "capacity", "space", "usage"],
    risk: "read-only",
    inputKind: "none",
    resultView: "disk-usage",
    learningLabel: "Mounted filesystem usage"
  },
  {
    id: "system.memory-usage",
    name: "Memory Usage",
    description: "Inspect total, used, available, and swap memory.",
    category: "System",
    keywords: ["system", "memory", "ram", "swap", "available", "used"],
    risk: "read-only",
    inputKind: "none",
    resultView: "memory-usage",
    learningLabel: "/proc/meminfo"
  },
  {
    id: "system.failed-services",
    name: "Failed Services",
    description: "Inspect failed system and user services without changing them.",
    category: "System",
    keywords: ["system", "failed", "services", "service", "systemd", "units"],
    risk: "read-only",
    inputKind: "none",
    resultView: "failed-services",
    learningLabel: "systemctl --failed"
  },
  {
    id: "network.overview",
    name: "Network Overview",
    description: "Inspect the active interface, local IP address, default gateway, DNS, and connection state.",
    category: "Network",
    keywords: ["network", "overview", "interface", "ip", "gateway", "dns", "connection", "route"],
    risk: "read-only",
    inputKind: "none",
    resultView: "network-overview",
    learningLabel: "ip -j route/link/address · resolvectl status"
  },
  {
    id: "network.listening-ports",
    name: "Listening Ports",
    description: "Inspect TCP and UDP listening sockets and associated processes when available.",
    category: "Network",
    keywords: ["network", "listening", "ports", "port", "tcp", "udp", "sockets", "processes"],
    risk: "read-only",
    inputKind: "none",
    resultView: "listening-ports",
    learningLabel: "ss -H -l -n -t -u -p"
  },
  {
    id: "network.ping-host",
    name: "Ping Host",
    description: "Check latency and packet loss for a validated hostname or IP address.",
    category: "Network",
    keywords: ["network", "ping", "host", "latency", "packet-loss", "icmp", "ip"],
    risk: "read-only",
    inputKind: "host",
    resultView: "ping-host",
    learningLabel: "ping"
  },
  {
    id: "network.dns-lookup",
    name: "DNS Lookup",
    description: "Resolve a validated DNS name and inspect its returned addresses.",
    category: "Network",
    keywords: ["network", "dns", "lookup", "resolve", "domain", "hostname", "addresses"],
    risk: "read-only",
    inputKind: "dns-name",
    resultView: "dns-lookup",
    learningLabel: "resolvectl query"
  },
  {
    id: "diagnostics.system-health",
    name: "System Health",
    description: "Run the predefined read-only checks for load, memory, storage, failed services, and system status.",
    category: "Diagnostics",
    keywords: ["diagnostics", "system", "health", "load", "memory", "storage", "failed-services", "status"],
    risk: "read-only",
    inputKind: "none",
    resultView: "system-health",
    learningLabel: "Predefined system health checks"
  },
  {
    id: "diagnostics.network-diagnostic",
    name: "Network Diagnostic",
    description: "Run the predefined network checks for interface state, local IP, route, DNS, and reachability.",
    category: "Diagnostics",
    keywords: ["diagnostics", "network", "diagnostic", "interface", "route", "gateway", "dns", "reachability"],
    risk: "read-only",
    inputKind: "none",
    resultView: "network-diagnostic",
    learningLabel: "Predefined network diagnostic checks"
  }
])

function allActions() {
  return Actions.slice()
}

function actionById(actionId) {
  if (typeof actionId !== "string")
    return null
  for (var index = 0; index < Actions.length; index++) {
    if (Actions[index].id === actionId)
      return Actions[index]
  }
  return null
}
