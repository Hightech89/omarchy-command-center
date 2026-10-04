const assert = require('node:assert/strict')
const test = require('node:test')
const path = require('node:path')
const { loadQmlJs } = require('./load-qml-js.cjs')
const rules = loadQmlJs(path.join(__dirname, '..', 'diagnostics', 'DiagnosticRules.js'))

function system(cpu = 50, normalized = 0.5, memory = 50, storage = 50, failedCount = 0) {
  const overview = { status: 'success', data: { cpu: { usagePercent: cpu, logicalProcessors: 2 }, load: { one: normalized * 2, five: 1, fifteen: 1 }, memory: { total: 1000, available: memory * 10, used: 1000 - memory * 10 }, rootStorage: { usePercent: storage, target: '/' }, components: {} } }
  const failed = { status: 'success', data: { scopes: { system: { status: 'success', count: failedCount }, user: { status: 'success', count: 0 } } } }
  const state = { status: 'success', data: { state: 'running' } }
  return { overview, failed, state }
}
function evaluated(value) { const x = value; return rules.systemHealth(x.overview, x.failed, x.state) }
for (const [index, cases] of [
  [[69.9, 'healthy'], [70, 'warning'], [89.9, 'warning'], [90, 'critical']],
  [[0.69, 'healthy'], [0.70, 'warning'], [0.99, 'warning'], [1, 'critical']],
  [[20, 'healthy'], [19.9, 'warning'], [10, 'warning'], [9.9, 'critical']],
  [[79.9, 'healthy'], [80, 'warning'], [89.9, 'warning'], [90, 'critical']],
  [[0, 'healthy'], [1, 'warning'], [2, 'warning'], [3, 'critical']]
].entries()) {
  test(`system check ${index} exact boundaries`, () => {
    for (const [value, expected] of cases) {
      const args = [50, 0.5, 50, 50, 0]
      args[index] = value
      assert.equal(evaluated(system(...args)).checks[index].status, expected, String(value))
    }
  })
}
test('system aggregation preserves severity and incomplete data', () => {
  assert.equal(evaluated(system(90, 0.8)).status, 'critical')
  assert.equal(evaluated(system(70)).status, 'warning')
  const x = system()
  x.overview.data.cpu.usagePercent = null
  assert.equal(evaluated(x).status, 'unavailable')
  assert.equal(evaluated(x).completeness, 'unavailable')
  const unknown = system()
  unknown.state.data.state = 'unknown'
  assert.equal(evaluated(unknown).checks[5].status, 'unavailable')
  unknown.state.data.state = 'maintenance'
  assert.equal(evaluated(unknown).checks[5].status, 'critical')
  x.overview.data.rootStorage.usePercent = 90
  assert.equal(evaluated(x).status, 'critical')
  assert.equal(evaluated(x).completeness, 'unavailable')
})

const local = { status: 'success', data: { connectionState: 'connected-local', primaryInterface: { name: 'eth0', operationalState: 'UP' }, route: { interfaceName: 'eth0', gateway: '192.0.2.1', family: 'ipv4', metric: 100 }, ipv4: ['192.0.2.2'], ipv6: [], linkLocal: ['fe80::1'] } }
test('network local failures and partial source data', () => {
  const missing = rules.networkLocal({ status: 'unavailable', message: 'missing' })
  assert.equal(missing.stages[0].status, 'unavailable')
  assert.equal(rules.networkLocal({ status: 'success', data: { ...local.data, primaryInterface: null } }).stages[0].status, 'critical')
  assert.equal(rules.networkLocal({ status: 'success', data: { ...local.data, connectionState: 'interface-down' } }).stages[0].status, 'critical')
  assert.equal(rules.networkLocal({ status: 'success', data: { ...local.data, ipv4: [] } }).stages[1].status, 'critical')
  assert.equal(rules.networkLocal({ status: 'success', data: { ...local.data, route: null } }).stages[2].status, 'critical')
})
test('gateway, DNS and public ICMP negative results are qualified', () => {
  const noReply = { status: 'success', data: { replied: false } }
  const gateway = rules.gatewayResult(noReply, '192.0.2.1')
  const dns = rules.dnsResult({ status: 'success', data: { ipv4: ['93.184.215.14'], ipv6: [] } })
  assert.equal(gateway.status, 'warning')
  assert.equal(dns.status, 'healthy')
  assert.equal(rules.networkOverall([gateway, dns], false).status, 'warning')
  assert.equal(rules.dnsResult({ status: 'empty', data: { ipv4: [], ipv6: [] } }).status, 'warning')
  const target = { provider: 'Cloudflare', address: '1.1.1.1' }
  const publicFail = rules.publicResult([{ target, result: noReply }], null)
  assert.equal(publicFail.status, 'warning')
  assert.match(publicFail.explanation, /ICMP can be blocked/)
  assert.doesNotMatch(JSON.stringify([gateway, publicFail]).toLowerCase(), /internet (?:down|offline)|no internet/)
  const publicPass = rules.publicResult([{ target, result: { status: 'success', data: { replied: true } } }], target)
  assert.equal(publicPass.status, 'healthy')
  assert.equal(rules.networkOverall([gateway, dns, publicPass], false).status, 'warning')
  assert.equal(rules.dnsResult({ status: 'error', message: 'Malformed response' }).status, 'error')
  assert.equal(rules.dnsResult({ status: 'empty', completeness: 'partial', data: { ipv4: [], ipv6: [] } }).status, 'unavailable')
  assert.equal(rules.gatewayResult(null, null).status, 'skipped')
  assert.equal(rules.networkOverall([rules.gatewayResult(null, null), dns, publicPass], false).status, 'healthy')
})
test('partial IPv6 route evidence keeps a successful IPv4 chain incomplete', () => {
  const result = rules.networkLocal({ ...local, evidence: [{ component: 'route6', status: 'unavailable' }] })
  assert.equal(result.stages[2].completeness, 'partial')
  const stages = result.stages.slice(0, 3).concat([
    rules.gatewayResult({ status: 'success', data: { replied: true } }, '192.0.2.1'),
    rules.dnsResult({ status: 'success', data: { ipv4: ['93.184.215.14'], ipv6: [] } }),
    rules.publicResult([], { provider: 'Cloudflare', address: '1.1.1.1' })
  ])
  assert.equal(rules.networkOverall(stages, false).status, 'unavailable')
})
test('public targets are fixed, ordered, and require matching address and route', () => {
  assert.deepEqual(Array.from(rules.publicTargets(local.data), item => item.address), ['1.1.1.1', '9.9.9.9', '8.8.8.8'])
  assert.equal(rules.publicTargets({ ...local.data, ipv4: [] }).length, 0)
  const dual = { ...local.data, ipv6: ['2001:db8::2'], defaultRoutes: [local.data.route, { interfaceName: 'eth0', family: 'ipv6' }] }
  assert.deepEqual(Array.from(rules.publicTargets(dual), item => item.address), [
    '1.1.1.1', '2606:4700:4700::1111', '9.9.9.9', '2620:fe::fe', '8.8.8.8', '2001:4860:4860::8888'
  ])
})
