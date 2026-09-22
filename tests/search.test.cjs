const assert = require('node:assert/strict')
const path = require('node:path')
const test = require('node:test')
const { loadQmlJs } = require('./load-qml-js.cjs')

const catalog = loadQmlJs(path.join(__dirname, '..', 'catalog', 'CommandCatalog.js'))
const search = loadQmlJs(path.join(__dirname, '..', 'catalog', 'Search.js'))
const actions = catalog.Actions
const ids = results => Array.from(results, action => action.id)

test('search returns the catalog order for an empty normalized query', () => {
  assert.deepEqual(ids(search.search(actions, '')), ids(actions))
  assert.deepEqual(ids(search.search(actions, '   \t\n ')), ids(actions))
})

test('search ranks exact names, prefixes, and name substrings in that order', () => {
  assert.equal(search.search(actions, 'System Overview')[0].id, 'system.overview')
  assert.equal(search.search(actions, 'network o')[0].id, 'network.overview')
  assert.equal(search.search(actions, 'tening')[0].id, 'network.listening-ports')
})

test('search matches keyword, category, and description word-prefix fields', () => {
  assert.equal(search.search(actions, 'gateway')[0].id, 'network.overview')
  assert.deepEqual(ids(search.search(actions, 'diagnostics')), [
    'diagnostics.system-health', 'diagnostics.network-diagnostic'
  ])
  const descriptionOnly = [{
    id: 'test.description', name: 'Probe', description: 'Observe latency evidence.',
    category: 'Test', keywords: ['probe']
  }]
  assert.equal(search.search(descriptionOnly, 'late')[0].id, 'test.description')
})

test('search is an AND query, case-insensitive, whitespace-normalized, and deterministic', () => {
  assert.deepEqual(ids(search.search(actions, '  DNS\tNETWORK  ')), ['network.overview', 'network.dns-lookup', 'diagnostics.network-diagnostic'])
  const tied = [
    { id: 'test.first', name: 'One', description: 'Shared evidence.', category: 'Test', keywords: ['one'] },
    { id: 'test.second', name: 'Two', description: 'Shared evidence.', category: 'Test', keywords: ['two'] }
  ]
  assert.deepEqual(ids(search.search(tied, 'sha')), ['test.first', 'test.second'])
})

test('search has expected command-center results and reports no match as an empty array', () => {
  assert.equal(search.search(actions, 'ports')[0].id, 'network.listening-ports')
  assert.equal(search.search(actions, 'dns')[0].id, 'network.dns-lookup')
  assert.equal(search.search(actions, 'memory')[0].id, 'system.memory-usage')
  assert.deepEqual(ids(search.search(actions, 'system')), [
    'system.overview', 'diagnostics.system-health', 'system.disk-usage',
    'system.memory-usage', 'system.failed-services'
  ])
  assert.deepEqual(ids(search.search(actions, 'no-such-action')), [])
})
