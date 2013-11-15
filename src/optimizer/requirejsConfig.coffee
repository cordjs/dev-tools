path      = require 'path'
requirejs = require 'requirejs'
_         = require 'lodash'

Future    = require '../utils/Future'
appConfig = require '../appConfig'


pathConfigFile = 'public/bundles/cord/core/requirejs/pathConfig'

savedConfigFuture = null

exports.collect = (targetDir) ->
  ###
  Collects and merges requirejs configuration into single config object from the different sources:
  * cordjs path-config
  * enabled bundles configs
  @param String targetDir directory with compiled cordjs project
  @return Future[Object]
  ###
  if savedConfigFuture
    savedConfigFuture
  else
    pathConfig = require "#{ path.join(targetDir, pathConfigFile) }"

    resultConfig =
      baseUrl: '/'
      urlArgs: 'release=' + Math.random()
      paths: pathConfig

    requirejs.config
      baseUrl: path.join(targetDir, 'public')
      paths: pathConfig

    savedConfigFuture = appConfig.getBundles(targetDir).flatMap (bundles) ->
      configs = ("cord!/#{ bundle }/config" for bundle in bundles)
      Future.require(configs)
    .map (configs...) ->
      _.merge(resultConfig, config.requirejs) for config in configs when config.requirejs
      resultConfig
