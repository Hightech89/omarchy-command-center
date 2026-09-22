// Pure route decisions shared by the QML controller and its dependency-free
// smoke tests. This module has no process or service dependency.

var Route = Object.freeze({
  Root: "root",
  Input: "input",
  Result: "result"
})

function actionForId(actions, actionId) {
  if (!Array.isArray(actions) || typeof actionId !== "string")
    return null
  for (var index = 0; index < actions.length; index++) {
    if (actions[index] && actions[index].id === actionId)
      return actions[index]
  }
  return null
}

function activationFor(actions, actionId) {
  var action = actionForId(actions, actionId)
  if (action === null)
    return { ok: false, reason: "unknown-action" }
  return {
    ok: true,
    action: action,
    route: action.inputKind === "none" ? Route.Result : Route.Input
  }
}
