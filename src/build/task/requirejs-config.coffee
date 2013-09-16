path = require('path')
requirejs = require('requirejs')
Future = require('../../utils/Future')

pathToCore = 'bundles/cord/core'


_requirejsReady = null

module.exports = (task) ->
  ###
  First call initiates cordjs framework requirejs configuration (paths and so on).
  Returns a future which completes when requirejs is configured.
  All subsequent calls returns the same future.
  @param Object task params to take base and target directories from
  @return Future[Nothing]
  ###
  if not _requirejsReady?
    pathConfig = require "#{ path.join(task.baseDir, 'public', pathToCore) }/requirejs/pathConfig"
    requirejs.config
      baseUrl: "#{ task.targetDir }/public"
      nodeRequire: require
      paths: pathConfig
    _requirejsReady = Future.require('pathUtils').map (pathUtils) =>
      pathUtils.setPublicPrefix('target/public')
  _requirejsReady
