path      = require 'path'

requirejs = require process.cwd() + '/node_modules/requirejs'

Future = require './utils/Future'


appConfFile = 'app/application'

savedBundlesPromise = null

exports.getBundles = (targetDir) ->
  ###
  Loads application config and returns list of bundles of the application including core bundle.
  @param String targetDir directory with compiled cordjs project
  @return Future[Array[String]]
  ###
  if savedBundlesPromise
    savedBundlesPromise
  else
    requirejs.config
      baseUrl: path.join(targetDir, 'public')

    savedBundlesPromise = Future.require(appConfFile).then (bundles) ->
      ['cord/core'].concat(bundles) # core is always enabled

    savedBundlesPromise
