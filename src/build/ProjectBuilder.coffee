walk = require('walk')
{EventEmitter} = require('events')

class ProjectBuilder extends EventEmitter

  constructor: (@params) ->
    console.log "build params", @params


  build: ->
    console.log "building project..."

    walker = walk.walk(@params.baseDir + '/public')
    walker.on 'node', (root, stat, next) ->
      if   root.indexOf('.git') < 0 and stat.name.indexOf('.git') < 0 \
       and root.indexOf('.hg') < 0 and stat.name.indexOf('.hg') < 0
        console.log "walker", root, stat
      next()

    this

exports.ProjectBuilder = ProjectBuilder
