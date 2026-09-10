const assert = require('node:assert/strict')
const path = require('node:path')
const test = require('node:test')
const { loadQmlJs } = require('./load-qml-js.cjs')

const result = loadQmlJs(path.join(__dirname, '..', 'parsers', 'Result.js'))

test('result helpers provide the v0.1 status and parser contracts', () => {
  assert.deepEqual(Object.values(result.Status), ['loading', 'success', 'empty', 'unavailable', 'error', 'timeout', 'canceled'])
  assert.deepEqual(Object.values(result.Completeness), ['complete', 'partial'])
  assert.deepEqual(Object.values(result.DiagnosticSeverity), ['healthy', 'warning', 'critical', 'unavailable', 'error'])
  const success = result.success('system.memory', { total: 1 }, { evidence: [{ label: 'source', value: 'proc' }] })
  assert.equal(success.status, 'success')
  assert.equal(success.completeness, 'complete')
  assert.deepEqual(result.parsed({ seconds: 1 }, 'partial', ['optional field missing']).warnings, ['optional field missing'])
  assert.equal(result.failure('malformed-output', 'bad').ok, false)
})
