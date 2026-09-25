const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const test = require('node:test')
const { loadQmlJs } = require('./load-qml-js.cjs')

const root = path.join(__dirname, '..')
const catalog = loadQmlJs(path.join(root, 'catalog', 'CommandCatalog.js'))
const state = loadQmlJs(path.join(root, 'controllers', 'CommandCenterState.js'))
const controllerSource = fs.readFileSync(path.join(root, 'controllers', 'CommandCenterController.qml'), 'utf8')

test('controller activation routes trusted action IDs without invoking a process', () => {
  const overview = state.activationFor(catalog.Actions, 'system.overview')
  assert.equal(overview.ok, true)
  assert.equal(overview.route, state.Route.Result)
  assert.equal(overview.action.id, 'system.overview')

  const unknown = state.activationFor(catalog.Actions, 'system.remove-everything')
  assert.equal(unknown.ok, false)
  assert.equal(unknown.reason, 'unknown-action')
})

test('controller routes only Ping Host and DNS Lookup to input placeholders', () => {
  assert.equal(state.activationFor(catalog.Actions, 'network.ping-host').route, state.Route.Input)
  assert.equal(state.activationFor(catalog.Actions, 'network.dns-lookup').route, state.Route.Input)
  for (const action of catalog.Actions) {
    if (action.inputKind === 'none')
      assert.equal(state.activationFor(catalog.Actions, action.id).route, state.Route.Result, action.id)
  }
})

test('input action results return to their input route while non-input results return to root', () => {
  assert.match(controllerSource, /route === State\.Route\.Result && currentAction && currentAction\.inputKind !== "none"/)
  assert.match(controllerSource, /route = State\.Route\.Input/)
  assert.match(controllerSource, /if \(route !== State\.Route\.Root\)/)
})

test('controller exposes reset/back state and no execution-shaped public API', () => {
  assert.match(controllerSource, /function back\(\)/)
  assert.match(controllerSource, /function reset\(\)/)
  assert.match(controllerSource, /route = State\.Route\.Root/)
  assert.match(controllerSource, /function activateAction\(actionId\)/)
  assert.doesNotMatch(controllerSource, /ProcessRunner|executable|arguments|argv|command\s*:/i)
  assert.doesNotMatch(controllerSource, /\.run\s*\(/)
  assert.match(controllerSource, /function submitCurrentInput\(input\)/)
  assert.match(controllerSource, /networkService\.refreshNetworkOverview\(\)/)
  assert.match(controllerSource, /networkService\.refreshListeningPorts\(\)/)
})
