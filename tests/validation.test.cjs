const assert = require('node:assert/strict')
const path = require('node:path')
const test = require('node:test')
const { loadQmlJs } = require('./load-qml-js.cjs')

const validation = loadQmlJs(path.join(__dirname, '..', 'parsers', 'Validation.js'))

function accepts(value, kind, normalized = value) {
  const result = validation.validateHostInput(value)
  assert.equal(result.ok, true, value)
  assert.equal(result.kind, kind, value)
  assert.equal(result.value, normalized, value)
}

function rejects(value) {
  assert.equal(validation.validateHostInput(value).ok, false, value)
}

test('accepts strict IPv4 and rejects malformed dotted decimal without hostname fallback', () => {
  accepts('192.0.2.1', 'ipv4')
  for (const value of ['01.2.3.4', '1.2.3.256', '1.2.3', '1..2.3', '1.2.3.4.5']) rejects(value)
})

test('accepts compressed, uncompressed, and embedded-IPv4 IPv6 forms', () => {
  accepts('::', 'ipv6')
  accepts('2001:DB8::1', 'ipv6', '2001:db8::1')
  accepts('2001:db8:0:0:0:0:2:1', 'ipv6')
  accepts('::ffff:192.0.2.128', 'ipv6')
  accepts('0:0:0:0:0:ffff:192.0.2.128', 'ipv6')
  for (const value of ['2001::db8::1', '2001:db8:1', '1:2:3:4:5:6:7:8:9',
    '::ffff:192.168.001.1', '1:2:3:4:192.0.2.1:6']) rejects(value)
})

test('accepts ASCII names including root dot, single labels, and punycode', () => {
  accepts('example.com', 'name')
  accepts('printer', 'name')
  accepts('Example.COM.', 'name', 'example.com.')
  accepts('xn--bcher-kva.example', 'name')
  assert.equal(validation.validateHostInput('Example.COM.').displayValue, 'Example.COM.')
})

test('rejects unsafe, unsupported, and overlong input forms', () => {
  const label64 = 'a'.repeat(64)
  const name254 = `${'a'.repeat(63)}.${'b'.repeat(63)}.${'c'.repeat(63)}.${'d'.repeat(62)}`
  for (const value of ['bücher.example', label64 + '.example', name254, '-host.example',
    ' host.example', 'host.example ', 'https://example.com', 'example.com:443',
    'example.com/path', 'user@example.com', 'fe80::1%eth0', '[2001:db8::1]',
    'host\nname']) rejects(value)
})

test('Ping accepts typed hosts and DNS accepts names only', () => {
  assert.deepEqual(validation.validatePingTarget('198.51.100.7'), validation.validateHostInput('198.51.100.7'))
  assert.deepEqual(validation.validateDnsName('example.test'), validation.validateHostInput('example.test'))
  assert.equal(validation.validateDnsName('198.51.100.7').ok, false)
  assert.equal(validation.validateDnsName('2001:db8::1').ok, false)
})
