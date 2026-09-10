const fs = require('node:fs')
const vm = require('node:vm')

function loadQmlJs(path) {
  const context = { console, Number, Object, Array, String, RegExp, Math }
  vm.createContext(context)
  vm.runInContext(fs.readFileSync(path, 'utf8'), context, { filename: path })
  return context
}

module.exports = { loadQmlJs }
