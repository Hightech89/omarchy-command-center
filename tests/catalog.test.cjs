const assert = require('node:assert/strict')
const path = require('node:path')
const test = require('node:test')
const { loadQmlJs } = require('./load-qml-js.cjs')

const catalog = loadQmlJs(path.join(__dirname, '..', 'catalog', 'CommandCatalog.js'))

const expectedIds = [
  'system.overview',
  'system.disk-usage',
  'system.memory-usage',
  'system.failed-services',
  'network.overview',
  'network.listening-ports',
  'network.ping-host',
  'network.dns-lookup',
  'diagnostics.system-health',
  'diagnostics.network-diagnostic'
]
const supportedCategories = new Set(['System', 'Network', 'Diagnostics'])
const supportedInputKinds = new Set(['none', 'host', 'dns-name'])
const supportedResultViews = new Set([
  'system-overview', 'disk-usage', 'memory-usage', 'failed-services',
  'network-overview', 'listening-ports', 'ping-host', 'dns-lookup',
  'system-health', 'network-diagnostic'
])
const requiredKeys = ['id', 'name', 'description', 'category', 'keywords', 'risk', 'inputKind', 'resultView', 'learningLabel']
const forbiddenKeys = new Set([
  'executable', 'executablePath', 'executableName', 'argv', 'arguments',
  'command', 'commandLine', 'shell', 'callback', 'run', 'execute'
])

test('catalog contains exactly the stable v0.1 read-only action metadata', () => {
  assert.equal(catalog.Actions.length, 10)
  assert.deepEqual(Array.from(catalog.Actions, action => action.id), expectedIds)
  assert.equal(new Set(catalog.Actions.map(action => action.id)).size, 10)

  for (const action of catalog.Actions) {
    assert.deepEqual(Object.keys(action).sort(), requiredKeys.slice().sort())
    assert.match(action.id, /^(system|network|diagnostics)\.[a-z0-9-]+$/)
    assert.ok(action.name.length > 0)
    assert.ok(action.description.length > 0)
    assert.ok(action.learningLabel.length > 0)
    assert.ok(supportedCategories.has(action.category))
    assert.equal(action.risk, 'read-only')
    assert.ok(supportedInputKinds.has(action.inputKind))
    assert.ok(supportedResultViews.has(action.resultView))
    assert.equal(Object.keys(action).some(key => forbiddenKeys.has(key)), false)
    assert.ok(Array.isArray(action.keywords) && action.keywords.length > 0)
    assert.equal(new Set(action.keywords).size, action.keywords.length)
    for (const keyword of action.keywords) {
      assert.match(keyword, /^[a-z0-9]+(?:-[a-z0-9]+)*$/)
    }
  }
})

test('catalog input metadata is fixed to the two validated network actions', () => {
  assert.equal(catalog.actionById('network.ping-host').inputKind, 'host')
  assert.equal(catalog.actionById('network.dns-lookup').inputKind, 'dns-name')
  for (const action of catalog.Actions) {
    if (action.id !== 'network.ping-host' && action.id !== 'network.dns-lookup')
      assert.equal(action.inputKind, 'none', action.id)
  }
  assert.equal(catalog.actionById('unknown.action'), null)
  assert.notEqual(catalog.allActions(), catalog.Actions)
})
