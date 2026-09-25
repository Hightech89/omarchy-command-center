const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const test = require('node:test')

const root = path.join(__dirname, '..')
const read = name => fs.readFileSync(path.join(root, name), 'utf8')

test('UI composes typed SystemService views without direct process access', () => {
  const menu = read('Menu.qml')
  for (const name of ['DashboardView', 'SearchView', 'SystemOverviewView', 'DiskUsageView', 'MemoryUsageView', 'FailedServicesView'])
    assert.match(menu, new RegExp(name + '\\s*\\{'))
  assert.match(menu, /refreshDashboardLive\(\)/)
  assert.match(menu, /refreshDashboardInventory\(\)/)
  assert.doesNotMatch(menu, /ProcessRunner|executable\s*:|arguments\s*:|argv|\bcommand\s*:/i)
  assert.doesNotMatch(menu, /network\.(?:ping|dns)|\/usr\/bin\/(?:ping|ip|ss|resolvectl)/)
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

test('dashboard root storage copy uses validated capacity fields', () => {
  const dashboard = read('ui/DashboardView.qml')
  assert.match(dashboard, /Formatters\.bytes\(storage\.used\) \+ " used \/ " \+ Formatters\.bytes\(storage\.available\) \+ " available"/)
  assert.doesNotMatch(dashboard, /rootStorage\.avail\b|storage\.avail\b/)
})
