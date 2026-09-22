const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const test = require('node:test')

const source = fs.readFileSync(path.join(__dirname, '..', 'services', 'SystemService.qml'), 'utf8')

test('SystemService exposes only explicit refresh and cancellation operations', () => {
  for (const method of [
    'refreshSystemOverview', 'refreshDiskUsage', 'refreshMemoryUsage',
    'refreshFailedServices', 'refreshDashboardSystemSnapshot',
    'refreshSystemdSystemState', 'cancelAll'
  ]) assert.match(source, new RegExp(`function ${method}\\(`))

  assert.doesNotMatch(source, /function\s+(?:run|execute|command|probe)\s*\([^)]*(?:executable|argv|arguments|command)/i)
  assert.equal((source.match(/\bProcessRunner\s*\{/g) || []).length, 4)
})

test('SystemService uses only the reviewed fixed read-only executable paths', () => {
  const executables = Array.from(source.matchAll(/executable:\s*"([^"]+)"/g), match => match[1])
  assert.ok(executables.length > 0)
  assert.deepEqual(new Set(executables), new Set(['/usr/bin/cat', '/usr/bin/findmnt', '/usr/bin/systemctl']))
  assert.doesNotMatch(source, /executable:\s*[^"\s]/)
  assert.doesNotMatch(source, /\/usr\/bin\/(?:bash|sh|sudo|pkexec)\b/)
  assert.doesNotMatch(source, /"(?:start|stop|restart|reset-failed|enable|disable)"/)
})

test('SystemService contains the exact preferred system request shapes', () => {
  assert.match(source, /arguments:\s*\["\/proc\/sys\/kernel\/hostname"\]/)
  assert.match(source, /arguments:\s*\["\/etc\/os-release"\]/)
  assert.match(source, /arguments:\s*\["\/proc\/stat"\]/)
  assert.match(source, /arguments:\s*\["\/proc\/meminfo"\]/)
  assert.match(source, /"--json", "--bytes", "--df", "--target", "\/"/)
  assert.match(source, /"--json", "--bytes", "--df", "--real"/)
  assert.match(source, /"--system", "--failed"/)
  assert.match(source, /"--user", "--failed"/)
  assert.match(source, /arguments:\s*\["is-system-running"\]/)
  assert.match(source, /interval:\s*500/)
})
