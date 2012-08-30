fs    = require 'fs'
util  = require 'util'
path  = require 'path'
sys   = require 'sys'
{spawn, exec}   = require 'child_process'

# The current version number
exports.VERSION = '0.0.1'

generator = {
  collection: {}

  addGenerator: (name, callback) ->
    @collection[name] = callback

  exists: (name) ->
    !!@collection[name]

  init: ->
    @addGenerator 'project', projectGenerator

  do: (name, args...) ->
    @collection[name](args...)
}

projectGenerator = (command, args) ->
  switch command
    when "create"
#      createDir 'public'
#      createDir 'public/app'
#      createDir 'public/bundles'
#      createDir 'public/bundles/cord'
#      createDir 'public/bundles/cord/core'
#      createDir 'public/vendor'

      console.log 'Cloning based project layout...'
      sendCommand "git clone https://github.com/cordjs/cordjs.git .", ->
        createDir 'public/bundles/cord'
        createDir 'public/bundles/cord/core'
        console.log 'Cloning core...'
        sendCommand "git clone https://github.com/cordjs/core.git public/bundles/cord/core"

    when "update"
      sendCommand "git pull"

generator.init()

exports.generator = generator

# Create directory
createDir = (dir) ->
  root = process.cwd()
  pathDir = path.join root, dir
  if !fs.existsSync pathDir
    fs.mkdirSync path.join(root, dir), '0755'
    console.log 'Create directory: ', dir

sendCommand = (command, callback) ->
  exec command, (error, stdout, stderr) ->
    if error
      console.log "#{ error }"
    else
      console.log stdout if stdout

    callback?(arguments...)