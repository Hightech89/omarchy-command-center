const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const test = require('node:test')

const source = fs.readFileSync(path.join(__dirname, '..', 'services', 'NetworkService.qml'), 'utf8')

test('NetworkService exposes only explicit network operations and cancellation', () => {
  for (const method of ['refreshNetworkOverview', 'refreshListeningPorts', 'pingHost', 'lookupDns',
    'refreshDashboardNetworkSnapshot', 'cancelNetworkOverview', 'cancelListeningPorts', 'cancelPing',
    'cancelDns', 'cancelDashboardNetworkSnapshot', 'cancelAll'])
    assert.match(source, new RegExp(`function ${method}\\(`))
  assert.equal((source.match(/\bProcessRunner\s*\{/g) || []).length, 4)
  assert.doesNotMatch(source, /function\s+(?:run|execute|command)\s*\([^)]*(?:executable|argv|arguments|command)/i)
})

test('NetworkService uses only reviewed fixed absolute read-only executables and argv', () => {
  const executables = Array.from(source.matchAll(/executable:\s*"([^"]+)"/g), match => match[1])
  assert.deepEqual(new Set(executables), new Set(['/usr/bin/ip', '/usr/bin/resolvectl', '/usr/bin/ss', '/usr/bin/ping']))
  assert.doesNotMatch(source, /\/usr\/bin\/(?:bash|sh|sudo|pkexec)\b/)
  assert.doesNotMatch(source, /executable:\s*[^"\s]/)
  assert.match(source, /arguments:\s*\["-j", "route", "show", "default"\]/)
  assert.match(source, /arguments:\s*\["-j", "link", "show"\]/)
  assert.match(source, /arguments:\s*\["-j", "address", "show"\]/)
  assert.match(source, /arguments:\s*\["--json=short", "status"\]/)
  assert.match(source, /arguments:\s*\["-H", "-l", "-n", "-t", "-u", "-p"\]/)
  assert.match(source, /family\.concat\(\["-n", "-c", "4", "-W", "1", "-w", "5", "--", context\.input\.value\]\)/)
})

test('NetworkService revalidates input and has no generic or arbitrary public execution boundary', () => {
  assert.match(source, /Validation\.validatePingTarget\(raw\)/)
  assert.match(source, /Validation\.validateDnsName\(raw\)/)
  assert.match(source, /context\.input\.value/)
  assert.doesNotMatch(source, /clearEnvironment\s*:|environment\s*:|bash\s+-c|sh\s+-c|eval\s*\(/i)
})
