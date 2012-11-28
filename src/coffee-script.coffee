fs            = require 'fs'
Cordjs        = require './cordjs'
CoffeeScript  = require '../../node_modules/coffee-script/lib/coffee-script/coffee-script'
helpers       = require '../../node_modules/coffee-script/lib/coffee-script/helpers'

{EventEmitter}  = require 'events'

# Allow CoffeeScript to emit Node.js events.
helpers.extend CoffeeScript, new EventEmitter

# Compile a single source coffee-script
compile = (source, base, options, callback) ->
  fs.readFile source, (err, code) =>
    throw err if err and err.code isnt 'ENOENT'
    return callback?() if err?.code is 'ENOENT'
    string = code.toString()

    output = ''
    try
      t = task = {source, string, options}
      CoffeeScript.emit 'compile', task
      output = CoffeeScript.compile t.string, { compile: true, bare: true }
      CoffeeScript.emit 'success', task
    catch err
      Cordjs.utils.timeLogError "CoffeScript: #{ source }"
      CoffeeScript.emit 'failure', err, task
#      return if CoffeeScript.listeners('failure').length
      printLine err.message + '\x07' if options.watch
      printLine err instanceof Error and err.stack or "ERROR: #{err}"
    output = if output.length <= 0 then ' ' else output
    callback? output

exports.CoffeeScript = CoffeeScript
exports.compile = compile

printLine = (line) -> process.stdout.write line + '\n'
printWarn = (line) -> process.stderr.write line + '\n'
