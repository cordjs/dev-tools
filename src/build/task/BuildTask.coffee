path = require('path')

Future = require('../../utils/Future')

class ExpectedError extends Error

  name: 'ExpectedError'

  constructor: (@underlyingError) ->
    @underlyingError = underlyingError
    super(@underlyingError.message, @underlyingError.id)


class BuildTask
  ###
  Base class for all build tasks.
  @abstract
  ###

  @ExpectedError: ExpectedError

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
