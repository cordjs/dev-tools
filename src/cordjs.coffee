fs    = require 'fs'
util  = require 'util'
path  = require 'path'
sys   = require 'sys'
{spawn, exec}   = require 'child_process'

# The current version number
exports.VERSION = '0.0.4'

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
        console.log 'Cloning core...'
        sendCommand "git clone https://github.com/cordjs/core.git public/bundles/cord/core"

    when "update"
      sendCommand "git pull"

# Bundle commands
bundleGenerator = (command, args) ->
  switch command
    when "create"
      bundleName = args.shift()
      if !bundleName
        console.log 'Error: Empty bandle name'
        process.exit()

      createDir path.join("public/bundles", bundleName)
      console.log "Bundle #{ bundleName } create!"

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
#    console.log 'Create directory: ', dir

# exec command-line
sendCommand = (command, callback) ->
  exec command, (error, stdout, stderr) ->
    if error
      console.log "#{ error }"
    else
      console.log stdout if stdout

    callback?(arguments...)

# Utilites
utils = {
  timeLog: (message) -> console.log "#{(new Date).toLocaleTimeString()} - #{message}"
  timeLogError: (message) -> console.log ""
}
exports.utils = utils