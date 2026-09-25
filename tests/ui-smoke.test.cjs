const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const test = require('node:test')

const root = path.join(__dirname, '..')
const read = name => fs.readFileSync(path.join(root, name), 'utf8')

test('UI composes typed system and network service views without direct process access', () => {
  const menu = read('Menu.qml')
  for (const name of ['DashboardView', 'SearchView', 'SystemOverviewView', 'DiskUsageView', 'MemoryUsageView', 'FailedServicesView',
    'NetworkInputView', 'NetworkOverviewView', 'ListeningPortsView', 'PingResultView', 'DnsLookupView'])
    assert.match(menu, new RegExp(name + '\\s*\\{'))
  assert.match(menu, /refreshDashboardLive\(\)/)
  assert.match(menu, /refreshDashboardInventory\(\)/)
  assert.match(menu, /refreshDashboardNetwork\(\)/)
  assert.doesNotMatch(menu, /ProcessRunner|executable\s*:|arguments\s*:|argv|\bcommand\s*:/i)
  assert.doesNotMatch(menu, /\/usr\/bin\/(?:ping|ip|ss|resolvectl)/)
})

test('dashboard refresh is visible-only and uses conservative split cadences', () => {
  const menu = read('Menu.qml')
  assert.match(menu, /interval:\s*2000/)
  assert.match(menu, /interval:\s*5000/)
  assert.match(menu, /interval:\s*30000/)
  assert.match(menu, /cpuTimer\.stop\(\).*liveTimer\.stop\(\).*inventoryTimer\.stop\(\).*uptimeTimer\.stop\(\)/s)
  const service = read('services/SystemService.qml')
  assert.match(service, /function refreshDashboardLiveSnapshot\(/)
  assert.match(service, /function refreshDashboardInventorySnapshot\(/)
  assert.match(menu, /networkTimer\.stop\(\)/)
  assert.match(menu, /!systemService\.busy && !networkService\.busy/)
})

test('dashboard cards preserve successful observations through background refreshes', () => {
  const dashboard = read('ui/DashboardView.qml')
  for (const name of ['lastCpu', 'lastMemory', 'lastRootStorage', 'lastFailedServices'])
    assert.match(dashboard, new RegExp(`property var ${name}`))
  assert.match(dashboard, /Refreshing… last observed/)
  assert.match(dashboard, /Stale, last observed/)
  assert.match(dashboard, /componentProblem\(root\.cpuResult,\s*"cpuUsage"\)/)
  assert.match(dashboard, /componentProblem\(root\.liveResult,\s*"memory"\)/)
  assert.match(dashboard, /componentProblem\(root\.inventoryResult,\s*"rootStorage"\)/)
  assert.match(dashboard, /failedServicesProblem\(root\.inventoryResult\)/)
})

test('dashboard cards reserve stable single-line detail geometry', () => {
  const card = read('ui/StatusCard.qml')
  const dashboard = read('ui/DashboardView.qml')
  assert.match(card, /implicitHeight:\s*column\.implicitHeight \+ Style\.spacing\.xl \* 2/)
  assert.match(card, /FontMetrics\s*\{\s*id:\s*detailMetrics;\s*font:\s*detailText\.font\s*\}/s)
  assert.match(card, /id:\s*detailText[\s\S]*wrapMode:\s*Text\.NoWrap[\s\S]*height:\s*detailMetrics\.height/)
  assert.doesNotMatch(card, /visible:\s*root\.detail\s*!==\s*""/)
  assert.equal((dashboard.match(/StatusCard\s*\{/g) || []).length, 6)
})

test('search layout is downstream of a stable dashboard geometry', () => {
  const menu = read('Menu.qml')
  assert.match(menu, /DashboardView\s*\{[\s\S]*width:\s*parent\.width[\s\S]*\}/)
  assert.match(menu, /SearchView\s*\{[\s\S]*height:\s*parent\.height - y/)
})

test('dashboard root storage copy uses validated capacity fields', () => {
  const dashboard = read('ui/DashboardView.qml')
  assert.match(dashboard, /Formatters\.bytes\(storage\.used\) \+ " used \/ " \+ Formatters\.bytes\(storage\.available\) \+ " available"/)
  assert.doesNotMatch(dashboard, /rootStorage\.avail\b|storage\.avail\b/)
})

test('dashboard network card uses structured local evidence and avoids internet claims', () => {
  const dashboard = read('ui/DashboardView.qml')
  assert.match(dashboard, /property var lastNetwork/)
  assert.match(dashboard, /Connected locally/)
  assert.match(dashboard, /No default route/)
  assert.doesNotMatch(dashboard, /Internet connected/)
})

test('network input validates locally and service is the only execution boundary', () => {
  const input = read('ui/NetworkInputView.qml')
  assert.match(input, /Validation\.validatePingTarget/)
  assert.match(input, /Validation\.validateDnsName/)
  assert.match(input, /if \(checked\.ok\) root\.submit/)
  for (const file of ['ui/NetworkInputView.qml', 'ui/NetworkOverviewView.qml', 'ui/ListeningPortsView.qml', 'ui/PingResultView.qml', 'ui/DnsLookupView.qml'])
    assert.doesNotMatch(read(file), /ProcessRunner|executable\s*:|arguments\s*:|\/usr\/bin\//)
})

test('network result views expose another-input actions', () => {
  const ping = read('ui/PingResultView.qml')
  const dns = read('ui/DnsLookupView.qml')
  assert.match(ping, /signal anotherRequested\(\)/)
  assert.match(ping, /text:\s*"Ping Another Host"/)
  assert.match(dns, /signal anotherRequested\(\)/)
  assert.match(dns, /text:\s*"Lookup Another Name"/)
  assert.match(read('Menu.qml'), /onAnotherRequested:\s*root\.backOrDismiss\(\)/)
})
