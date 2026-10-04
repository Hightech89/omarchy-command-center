import QtQml
import "../diagnostics/DiagnosticRules.js" as Rules

// Coordinates existing read-only services. It owns no process or parser.
QtObject {
  id: root
  property var systemService: null
  property var networkService: null
  readonly property bool running: _active !== ""
  readonly property var systemHealthResult: _systemHealthResult
  readonly property var networkDiagnosticResult: _networkDiagnosticResult
  property var _systemHealthResult: ({ status: "unavailable", checks: [] })
  property var _networkDiagnosticResult: ({ status: "unavailable", stages: Rules.pendingStages() })
  property string _active: ""
  property int _runId: 0
  property int _activeRunId: 0
  property var _systemParts: ({})
  property var _systemGenerations: ({})
  property int _networkGeneration: 0
  property string _awaiting: ""
  property var _networkData: null
  property var _targets: []
  property var _attempts: []
  property int _targetIndex: 0

  function cancel() {
    ++_runId
    _activeRunId = 0
    var old = _active
    _active = ""
    _awaiting = ""
    if (old === "system" && systemService) {
      systemService.cancelSystemOverview()
      systemService.cancelFailedServices()
      systemService.cancelSystemdSystemState()
    }
    if (old === "network" && networkService) {
      networkService.cancelNetworkOverview()
      networkService.cancelPing()
      networkService.cancelDns()
    }
  }
  function startSystemHealth() {
    cancel()
    if (!systemService) return
    _active = "system"
    _activeRunId = _runId
    _systemParts = ({})
    _systemGenerations = ({})
    _systemHealthResult = { status: "running", completeness: "partial", checks: [
      { name: "CPU utilization", status: "pending" }, { name: "Normalized load", status: "pending" },
      { name: "Memory available", status: "pending" }, { name: "Root storage", status: "pending" },
      { name: "Failed services", status: "pending" }, { name: "systemd state", status: "pending" }
    ] }
    _systemGenerations = { overview: systemService.refreshSystemOverview(), failed: systemService.refreshFailedServices(), state: systemService.refreshSystemdSystemState() }
  }
  function _systemCompleted(name, result) {
    if (_active !== "system" || _activeRunId !== _runId || result.status === "canceled" || result.serviceGeneration !== _systemGenerations[name]) return
    var parts = Object.assign({}, _systemParts)
    parts[name] = result
    _systemParts = parts
    if (parts.overview && parts.failed && parts.state) {
      _systemHealthResult = Rules.systemHealth(parts.overview, parts.failed, parts.state)
      _active = ""
    }
  }
  function _publishNetwork(stages, running) {
    var overall = Rules.networkOverall(stages, running)
    _networkDiagnosticResult = { status: overall.status, completeness: overall.completeness, stop: overall.stop, stages: stages }
  }
  function _setStage(index, value, running) {
    var stages = _networkDiagnosticResult.stages.slice()
    stages[index] = value
    _publishNetwork(stages, running)
  }
  function startNetworkDiagnostic() {
    cancel()
    if (!networkService) return
    _active = "network"
    _activeRunId = _runId
    _networkData = null
    _targets = []
    _attempts = []
    _targetIndex = 0
    _publishNetwork(Rules.pendingStages(), true)
    _setStage(0, { name: Rules.NetworkStages[0], status: "running", observed: "Checking local interface…", explanation: "" }, true)
    _awaiting = "overview"
    _networkGeneration = networkService.refreshNetworkOverview()
  }
  function _overviewCompleted(result) {
    if (_active !== "network" || _activeRunId !== _runId || _awaiting !== "overview" || result.status === "canceled" || result.serviceGeneration !== _networkGeneration) return
    _awaiting = ""
    var local = Rules.networkLocal(result)
    _networkData = local.data
    _publishNetwork(local.stages, true)
    // Independent DNS remains useful even when local configuration is incomplete.
    var gateway = local.data && local.data.route && local.data.route.gateway
    if (gateway && local.stages[0].status === "healthy" && local.stages[1].status === "healthy") {
      _setStage(3, { name: Rules.NetworkStages[3], status: "running", observed: "Probing " + gateway + "…", explanation: "" }, true)
      _awaiting = "gateway"
      _networkGeneration = networkService.pingHost(gateway)
    } else {
      _setStage(3, gateway && local.stages[0].status !== "healthy" ? { name: Rules.NetworkStages[3], status: "skipped", observed: "Gateway probe skipped", explanation: "A usable interface and address are required." } : Rules.gatewayResult(null, gateway), true)
      _startDns()
    }
  }
  function _pingCompleted(result) {
    if (_active !== "network" || _activeRunId !== _runId || result.status === "canceled" || result.serviceGeneration !== _networkGeneration) return
    if (_awaiting === "gateway") {
      _awaiting = ""
      _setStage(3, Rules.gatewayResult(result, _networkData.route.gateway), true)
      _startDns()
    } else if (_awaiting === "public") {
      _awaiting = ""
      var target = _targets[_targetIndex]
      _attempts = _attempts.concat([{ target: target, result: result }])
      if (result.status === "success" && result.data && result.data.replied) {
        _setStage(5, Rules.publicResult(_attempts, target), false)
        _active = ""
      } else {
        ++_targetIndex
        _nextPublic()
      }
    }
  }
  function _startDns() {
    if (_active !== "network") return
    _setStage(4, { name: Rules.NetworkStages[4], status: "running", observed: "Resolving example.com…", explanation: "" }, true)
    _awaiting = "dns"
    _networkGeneration = networkService.lookupDns("example.com")
  }
  function _dnsCompleted(result) {
    if (_active !== "network" || _activeRunId !== _runId || _awaiting !== "dns" || result.status === "canceled" || result.serviceGeneration !== _networkGeneration) return
    _awaiting = ""
    _setStage(4, Rules.dnsResult(result), true)
    var stages = _networkDiagnosticResult.stages
    _targets = stages[0].status === "healthy" && stages[1].status === "healthy" && stages[2].status === "healthy" ? Rules.publicTargets(_networkData) : []
    _nextPublic()
  }
  function _nextPublic() {
    if (_active !== "network") return
    if (_targetIndex >= _targets.length) {
      _setStage(5, Rules.publicResult(_attempts, null), false)
      _active = ""
      return
    }
    var target = _targets[_targetIndex]
    _setStage(5, { name: Rules.NetworkStages[5], status: "running", observed: "Testing " + target.provider + " " + target.address + "…", explanation: "ICMP echo request to a fixed public diagnostic address." }, true)
    _awaiting = "public"
    _networkGeneration = networkService.pingHost(target.address)
  }
  property var _systemConnections: Connections {
    target: root.systemService
    function onSystemOverviewCompleted(result) { root._systemCompleted("overview", result) }
    function onFailedServicesCompleted(result) { root._systemCompleted("failed", result) }
    function onSystemdSystemStateCompleted(result) { root._systemCompleted("state", result) }
  }
  property var _networkConnections: Connections {
    target: root.networkService
    function onNetworkOverviewCompleted(result) { root._overviewCompleted(result) }
    function onPingCompleted(result) { root._pingCompleted(result) }
    function onDnsCompleted(result) { root._dnsCompleted(result) }
  }
  Component.onDestruction: cancel()
}
