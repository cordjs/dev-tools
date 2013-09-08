walk = require('walk')
{EventEmitter} = require('events')
{Future} = require('../utils/Future')
{buildManager} = require('./BuildManager')


class ProjectBuilder extends EventEmitter
  ###
  Builds the whole cordjs application project
  ###

  constructor: (@params) ->
    console.log "build params", @params


  build: ->
    console.log "building project..."

    start = process.hrtime()

    completePromise = new Future
    relativePos = @params.baseDir.length + 1

    dirList = [
      @params.baseDir + '/public/app'
      @params.baseDir + '/public/bundles'
      @params.baseDir + '/public/vendor'
    ]

    for dir in dirList
      do (dir) =>
        completePromise.fork()
        walker = walk.walk(dir)
        walker.on 'file', (root, stat, next) =>
          if   root.indexOf('.git') < 0 and stat.name.indexOf('.git') < 0 \
           and root.indexOf('.hg') < 0 and stat.name.indexOf('.hg') < 0
            relativeDir = root.substr(relativePos)
            completePromise.when(
              buildManager.createTask("#{relativeDir}/#{stat.name}", @params.baseDir, @params.targetDir)
            )
          next()

        walker.on 'end', ->
          console.log "walker for dir #{ dir } completed!"
          completePromise.resolve()

    completePromise.done ->
      diff = process.hrtime(start)
      console.log "Build complete in #{ (diff[0] * 1e9 + diff[1]) / 1e6 } ms"

    this



exports.ProjectBuilder = ProjectBuilder
