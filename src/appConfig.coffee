path      = require 'path'
requirejs = require 'requirejs'

Future = require './utils/Future'


appConfFile    = 'app/application'

savedBundlesFuture = null

exports.getBundles = (targetDir) ->
  ###
  Loads application config and returns list of bundles of the application including core bundle.
  @param String targetDir directory with compiled cordjs project
  @return Future[Array[String]]
  ###
  if savedBundlesFuture
    savedBundlesFuture
  else
    requirejs.config
      baseUrl: path.join(targetDir, 'public')

    savedBundlesFuture = Future.require(appConfFile).map (bundles) ->
      [['cord/core'].concat(bundles)] # core is always enabled

    savedBundlesFuture
