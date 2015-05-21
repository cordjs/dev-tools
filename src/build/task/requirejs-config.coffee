path = require 'path'

requirejs = require process.cwd() + '/node_modules/requirejs'

Future = require '../../utils/Future'


pathToCore = 'bundles/cord/core'

_requirejsReady = null

module.exports = (targetDir) ->
  ###
  First call initiates cordjs framework requirejs configuration (paths and so on).
  Returns a future which completes when requirejs is configured.
  All subsequent calls returns the same future.
  @param String targetDir target directory from which requirejs configuration should be loaded
  @return Future[Nothing]
  ###
  if not _requirejsReady?
    pathConfig = require "#{ path.join(targetDir, 'public', pathToCore) }/requirejs/pathConfig"
    requirejs.config
      baseUrl: path.join(targetDir, 'public')
      nodeRequire: require
      paths: pathConfig
    _requirejsReady = Future.require('pathUtils').then (pathUtils) ->
      pathUtils.setPublicPrefix('target/public')
  _requirejsReady
