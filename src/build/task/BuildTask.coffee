path = require('path')
mkdirp = require('mkdirp')

Future = require('../../utils/Future')

class BuildTask
  ###
  Base class for all build tasks.
  @abstract
  ###

  # this promise must
  readyPromise: null

  constructor: (@params) ->
    @readyPromise = Future.single()


  run: ->
    ###
    Actual task executor.
    Should be implemented in concrete task class.
    readyPromise must be completed here.
    ###
    throw new Error('BuildTask.run() method must be overriden by concrete task!')


  ready: -> @readyPromise



module.exports = BuildTask
