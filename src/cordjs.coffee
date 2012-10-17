fs    = require 'fs'
util  = require 'util'
path  = require 'path'
sys   = require 'sys'
{spawn, exec}   = require 'child_process'
colors = require 'colors'

# The current version number
exports.VERSION = '0.1.16'

Generator = {
  collection: {}

  addGenerator: (name, callback) ->
    @collection[name] = callback

  exists: (name) ->
    !!@collection[name]

  do: (name, args...) ->
    @collection[name](args...)

  list: ->
    Object.keys(@collection).join ', '

  init: ->
    # def list generators
    @addGenerator 'project', projectGenerator
    @addGenerator 'bundle', bundleGenerator
}

# Project commands
projectGenerator = (command, args) ->
  switch command
    when "create"
      utils.timeLog 'Cloning based project layout...'
      sendCommand "git clone https://github.com/cordjs/cordjs.git .", ->
        createDir 'public/bundles/cord'
        createDir 'public/bundles/cord/core'
        utils.timeLog 'Cloning core...'
        sendCommand "git clone https://github.com/cordjs/core.git public/bundles/cord/core"

    when "update"
      return utils.timeLogError 'Can\'t find public!' if !fs.existsSync 'public'
      utils.timeLog 'Update based project layout...'
      sendCommand "git pull", ->
        return utils.timeLogError 'Can\'t find cord/core!' if !fs.existsSync 'public/bundles/cord/core'
        utils.timeLog 'Update core...'
        sendCommand "cd public/bundles/cord; git pull; cd -", ->


# Bundle commands
bundleGenerator = (command, args) ->
  switch command
    when "create"
      bundleName = args.shift()
      if !bundleName
        utils.timeLogError 'Empty bandle name'
        process.exit()

      createDir path.join("public/bundles", bundleName)
      utils.timeLog "Bundle #{ bundleName } create!"

# Init def-generators
Generator.init()

# Export
exports.Generator = Generator

# Create directory
createDir = (dir) ->
  root = process.cwd()
  pathDir = path.join root, dir
  if !fs.existsSync pathDir
    fs.mkdirSync path.join(root, dir), '0755'

# exec command-line
sendCommand = (command, callback) ->
  exec command, (error, stdout, stderr) ->
    utils.printWarn stderr if stderr
    utils.printLine stdout if stdout

    callback?(arguments...)

exports.createDir = createDir
exports.sendCommand = sendCommand

# Utilites
utils = {
  time:         (new Date).toLocaleTimeString()
  timeLog:      (message) -> console.log "#{ utils.time } - #{ message }"
  timeLogError: (message, text = '') -> console.log "#{ utils.time } - ".red + "#{ utils.textError message } #{ text }"
  logError:     (message) -> console.log utils.textError( message )
  textError:    (message) -> "#{ 'ERROR:'.bold } #{ message }".red
  printLine:    (line) -> process.stdout.write line + '\n'
  printWarn:    (line) -> process.stderr.write line + '\n'
}
exports.utils = utils
