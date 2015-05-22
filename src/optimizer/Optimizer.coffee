fs = require 'fs'

_      = require 'underscore'
mkdirp = require 'mkdirp'

Future = require '../utils/Future'
rmrf   = require '../utils/rmrf'
sha1   = require '../utils/sha1'

browserInitGenerator = require './browserInitGenerator'
CssOptimizer         = require './CssOptimizer'
JsOptimizer          = require './JsOptimizer'


class Optimizer
  ###
  Build optimizer.
  * grouping modules into single files
  * minifying, gzipping
  * and so on
  ###

  _zDir: null
  _requireConfig: null
  _cleanFuture: null


  constructor: (@params) ->
    @_zDir = "#{@params.targetDir}/public/assets/z"


  run: ->
    start = process.hrtime()

    zDirFuture = (if @params.clean then rmrf(@_zDir) else Future.resolved()).then =>
      Future.call(mkdirp, @_zDir)

    cssOptimizerPromise =
      if @params.css
        (new CssOptimizer(@params, zDirFuture)).run()
      else
        Future.call(fs.unlink, "#{@params.targetDir}/conf/css-to-group-generated.js")
          .then -> {}
          .catch -> {}

    jsOptimizerPromise =
      if @params.js
        (new JsOptimizer(@params, zDirFuture)).run()
      else
        Future.resolved({})

    Future.all([jsOptimizerPromise, cssOptimizerPromise]).spread (jsGroupMap, cssGroupMap) =>
      console.log "Generating browser-init script..."
      browserInitPromise =
        browserInitGenerator.generate(@params, jsGroupMap, cssGroupMap).then (browserInitScriptString) =>
          fileName = sha1(browserInitScriptString)
          Future.all [
            Future.call(fs.writeFile, "#{@_zDir}/#{fileName}.js", browserInitScriptString)
            Future.call(fs.writeFile, "#{@_zDir}/browser-init.id", fileName)
          ]
      Future.all [
        browserInitPromise
        @_saveGroupMapCacheFile(jsGroupMap, cssGroupMap)
      ]
    .then ->
      diff = process.hrtime(start)
      console.log "Optimization complete in #{ (diff[0] * 1e9 + diff[1]) / 1e6 } ms"
    .failAloud('Optimizer::run')


  _saveGroupMapCacheFile: (jsGroupMap, cssGroupMap) ->
    ###
    Saves optimizer's computed groups mapping into the cache file for later use by `purgeOptimizedSources` command.
    @param {Object} jsGroupMap
    @param {Object} cssGroupMap
    @return {Future<undefined>}
    ###
    jsToGroup = {}
    for groupId, urls of jsGroupMap
      for file in urls
        jsToGroup[file] = groupId

    cssToGroup = {}
    for groupId, urls of cssGroupMap
      for css in urls
        cssToGroup[css] = groupId

    mergedMap =
      js: jsToGroup
      css: cssToGroup

    fileName = "#{@params.targetDir}/conf/optimizer-group-cache-generated.js"
    Future.call(fs.writeFile, fileName, "module.exports = #{ JSON.stringify(mergedMap, null, 2) };")



module.exports = Optimizer
