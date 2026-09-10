// Shared result vocabulary for services and pure parsers.
// Keep this module dependency-free so it can be imported by QML and fixture tests.

var Status = Object.freeze({
  Loading: "loading",
  Success: "success",
  Empty: "empty",
  Unavailable: "unavailable",
  Error: "error",
  Timeout: "timeout",
  Canceled: "canceled"
})

var Completeness = Object.freeze({
  Complete: "complete",
  Partial: "partial"
})

var DiagnosticSeverity = Object.freeze({
  Healthy: "healthy",
  Warning: "warning",
  Critical: "critical",
  Unavailable: "unavailable",
  Error: "error"
})

function makeResult(actionId, status, data, options) {
  var settings = options || {}
  return {
    actionId: actionId,
    status: status,
    data: data === undefined ? null : data,
    message: settings.message || "",
    reason: settings.reason || "",
    evidence: Array.isArray(settings.evidence) ? settings.evidence.slice() : [],
    source: settings.source || null,
    observedAt: settings.observedAt || null,
    completeness: settings.completeness || Completeness.Complete
  }
}

function loading(actionId, options) {
  return makeResult(actionId, Status.Loading, null, options)
}

function success(actionId, data, options) {
  return makeResult(actionId, Status.Success, data, options)
}

function empty(actionId, options) {
  return makeResult(actionId, Status.Empty, null, options)
}

function unavailable(actionId, reason, options) {
  var settings = options || {}
  settings.reason = reason
  return makeResult(actionId, Status.Unavailable, null, settings)
}

function failure(reason, message) {
  return { ok: false, reason: reason, message: message }
}

function parsed(data, completeness, warnings) {
  return {
    ok: true,
    data: data,
    completeness: completeness || Completeness.Complete,
    warnings: Array.isArray(warnings) ? warnings.slice() : []
  }
}
