const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const test = require('node:test')
const { loadQmlJs } = require('./load-qml-js.cjs')

const parsers = loadQmlJs(path.join(__dirname, '..', 'parsers', 'NetworkParsers.js'))
const fixture = name => fs.readFileSync(path.join(__dirname, 'fixtures', name), 'utf8')
const failed = result => assert.equal(result.ok, false)

test('strictly parses default routes and deterministically selects lowest-metric candidates', () => {
  const single = parsers.parseIpRouteJson(fixture('ip-route-default.json'))
  assert.equal(single.ok, true)
  assert.equal(single.data.routes[0].preferredSource, '192.0.2.44')
  assert.equal(single.data.routes[0].metric, 600)

  const multiple = parsers.parseIpRouteJson(fixture('ip-route-multiple.json'))
  const selected = parsers.selectPrimaryRoute(multiple.data.routes)
  assert.equal(selected.route.interfaceName, 'eth0')
  assert.equal(selected.equalBestCount, 2)
  assert.equal(selected.ambiguous, true)
  assert.equal(selected.multipleRoutes, true)

  const onLink = parsers.parseIpRouteJson('[{"dst":"default","dev":"tun0","flags":[]}]')
  assert.equal(onLink.ok, true)
  assert.equal(onLink.data.routes[0].gateway, null)
  failed(parsers.parseIpRouteJson('{"dst":"default"}'))
  failed(parsers.parseIpRouteJson('[{"dst":"default","dev":"eth0","metric":-1}]'))
  failed(parsers.parseIpRouteJson('[{"dst":"192.0.2.0/24","dev":"eth0"}]'))
})

test('parses link state, carrier, down state, and loopback identity', () => {
  const result = parsers.parseIpLinkJson(fixture('ip-links.json'))
  assert.equal(result.ok, true)
  assert.equal(result.data.links[0].loopback, true)
  assert.equal(result.data.links[1].administrativelyUp, true)
  assert.equal(result.data.links[1].carrierUp, true)
  assert.equal(result.data.links[2].operationalState, 'DOWN')
  assert.equal(result.data.links[2].carrierUp, false)
  failed(parsers.parseIpLinkJson('[{"ifname":"eth0","flags":[],"operstate":"UP"}]'))
  failed(parsers.parseIpLinkJson('[{"ifindex":2,"ifname":"eth0","flags":"UP","operstate":"UP"}]'))
})

test('parses IPv4, IPv6, global, link-local, loopback, and multiple addresses', () => {
  const result = parsers.parseIpAddressJson(fixture('ip-addresses.json'))
  assert.equal(result.ok, true)
  const loopback = result.data.interfaces[0].addresses
  assert.equal(loopback.every(address => address.loopback), true)
  const primary = result.data.interfaces[1].addresses
  assert.deepEqual(Array.from(primary.filter(address => address.usableGlobal), address => address.family), ['ipv4', 'ipv6'])
  assert.equal(primary[2].linkLocal, true)
  assert.equal(result.data.interfaces[2].addresses.length, 0)
  failed(parsers.parseIpAddressJson('[{"ifindex":2,"ifname":"eth0","addr_info":[{"family":"inet","local":"999.1.1.1","prefixlen":24,"scope":"global"}]}]'))
  failed(parsers.parseIpAddressJson('[{"ifindex":2,"ifname":"eth0"}]'))
})

test('parses verified resolvectl status array with per-interface DNS and domains', () => {
  const result = parsers.parseResolvectlStatusJson(fixture('resolvectl-status.json'))
  assert.equal(result.ok, true)
  assert.equal(result.data.links.length, 2)
  assert.deepEqual(Array.from(result.data.links[0].servers, server => server.address), ['192.0.2.53', '2001:db8::53'])
  assert.equal(result.data.links[0].searchDomains[1].routeOnly, true)
  const partial = parsers.parseResolvectlStatusJson('[{"ifname":"eth0","ifindex":2}]')
  assert.equal(partial.ok, true)
  assert.equal(partial.completeness, 'partial')
  failed(parsers.parseResolvectlStatusJson('{"ifname":"eth0"}'))
  failed(parsers.parseResolvectlStatusJson('[{"ifname":"eth0","ifindex":2,"servers":[{"addressString":"bad","port":53}]}]'))
})

test('derives local connection state, preferred address, DNS, and no-route state', () => {
  const routes = parsers.parseIpRouteJson(fixture('ip-route-default.json')).data
  const links = parsers.parseIpLinkJson(fixture('ip-links.json')).data
  const addresses = parsers.parseIpAddressJson(fixture('ip-addresses.json')).data
  const dns = parsers.parseResolvectlStatusJson(fixture('resolvectl-status.json')).data
  const overview = parsers.deriveNetworkOverview(routes, links, addresses, dns)
  assert.equal(overview.ok, true)
  assert.equal(overview.data.connectionState, 'connected-local')
  assert.equal(overview.data.ipv4[0], '192.0.2.44')
  assert.equal(overview.data.ipv6[0], '2001:db8::44')
  assert.equal(overview.data.linkLocal[0], 'fe80::44')
  assert.equal(overview.data.dnsServers[0].address, '192.0.2.53')

  const noRoute = parsers.deriveNetworkOverview({ routes: [] }, links, addresses, dns)
  assert.equal(noRoute.data.connectionState, 'no-default-route')
  assert.equal(noRoute.data.primaryInterface, null)
})

test('parses TCP/UDP, IPv4/IPv6, wildcard, scoped, and owner-limited ss rows', () => {
  const result = parsers.parseSsListening(fixture('ss-listening.txt'))
  assert.equal(result.ok, true)
  assert.equal(result.data.count, 4)
  assert.equal(result.data.sockets[0].owners[0].process, 'demo-server')
  assert.equal(result.data.sockets[0].owners.length, 2)
  assert.equal(result.data.sockets[1].ownerAvailable, false)
  assert.equal(result.data.sockets[2].localAddress, '2001:db8::1')
  assert.equal(result.data.sockets[3].localWildcard, true)

  const scoped = parsers.parseSsListening('udp UNCONN 0 0 127.0.0.53%lo:53 0.0.0.0:*')
  assert.equal(scoped.data.sockets[0].localZone, 'lo')
  const unbracketed = parsers.parseSsListening('tcp LISTEN 0 1 2001:db8::2:443 :::*')
  assert.equal(unbracketed.data.sockets[0].localAddress, '2001:db8::2')
  failed(parsers.parseSsListening('tcp LISTEN broken row'))
  failed(parsers.parseSsListening('raw LISTEN 0 0 0.0.0.0:1 0.0.0.0:*'))
})

test('parses successful, no-reply, partial-loss, IPv4/IPv6 ping summaries', () => {
  const success = parsers.parsePingSummary(fixture('ping-success.txt'))
  assert.equal(success.ok, true)
  assert.equal(success.data.replied, true)
  assert.equal(success.data.latency.averageMs, 2)
  const noReply = parsers.parsePingSummary(fixture('ping-no-reply.txt'))
  assert.equal(noReply.ok, true)
  assert.equal(noReply.data.replied, false)
  assert.equal(noReply.data.latency, null)
  const partial = parsers.parsePingSummary('4 packets transmitted, 3 received, 25% packet loss, time 1ms\nrtt min/avg/max/mdev = 1/2/3/1 ms\n')
  assert.equal(partial.data.packetLossPercent, 25)
  failed(parsers.parsePingSummary('PING 192.0.2.1\n'))
  failed(parsers.parsePingSummary('4 packets transmitted, 4 received, 0% packet loss\n'))
  failed(parsers.parsePingSummary('4 packets transmitted, 5 received, 0% packet loss\n'))
})

test('parses verified resolvectl A/AAAA JSON-lines, empty families, and deduplicates', () => {
  const a = parsers.parseResolvectlDnsQueryJsonLines(fixture('dns-a.jsonl'), 'A')
  const aaaa = parsers.parseResolvectlDnsQueryJsonLines(fixture('dns-aaaa.jsonl'), 'AAAA')
  assert.deepEqual(Array.from(a.data.answers), ['192.0.2.20'])
  assert.deepEqual(Array.from(aaaa.data.answers), ['2001:db8::20'])
  assert.deepEqual(Array.from(parsers.parseResolvectlDnsQueryJsonLines('', 'AAAA').data.answers), [])
  failed(parsers.parseResolvectlDnsQueryJsonLines('{bad json}\n', 'A'))
  failed(parsers.parseResolvectlDnsQueryJsonLines('{"key":{"class":1,"type":28,"name":"example.test"},"address":[0]}\n', 'A'))
  failed(parsers.parseResolvectlDnsQueryJsonLines(fixture('dns-a.jsonl'), 'MX'))
})

test('classifies a strict resolver negative response separately from malformed output', () => {
  const negative = parsers.parseResolvectlDnsNegative(fixture('dns-negative.txt'))
  assert.equal(negative.ok, true)
  assert.equal(negative.data.reason, 'not-found')
  failed(parsers.parseResolvectlDnsNegative('temporary bus failure\n'))
  failed(parsers.parseResolvectlDnsNegative("name: resolve call failed: Name 'x' not found\nextra\n"))
})

test('rejects network parser inputs beyond the bounded limit', () => {
  failed(parsers.parseIpRouteJson(' '.repeat(1024 * 1024 + 1)))
  failed(parsers.parseSsListening('x'.repeat(1024 * 1024 + 1)))
  failed(parsers.parsePingSummary('x'.repeat(1024 * 1024 + 1)))
})
