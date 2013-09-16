Future = require('../../utils/Future')
BuildTask = require('./BuildTask')


class Fake extends BuildTask
  ###
  Fake build task to skip any actions for the particular files.
  ###

  constructor: (@params) ->
    @readyPromise = Future.resolved()


  run: -> # doing nothing



module.exports = Fake
