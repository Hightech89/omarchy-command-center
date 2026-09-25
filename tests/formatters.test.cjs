const assert = require('node:assert/strict')
const path = require('node:path')
const test = require('node:test')
const { loadQmlJs } = require('./load-qml-js.cjs')

const formatters = loadQmlJs(path.join(__dirname, '..', 'presentation', 'Formatters.js'))

test('formatters produce bounded human-readable display values', () => {
  assert.equal(formatters.bytes(1024), '1.0 KiB')
  assert.equal(formatters.bytes(-1), 'Unavailable')
  assert.equal(formatters.percent(42.2), '42%')
  assert.equal(formatters.duration(90061), '1d 1h 1m')
  assert.equal(formatters.load(1.234), '1.23')
})
