fs = require 'fs'

_        = require 'underscore'
mkdirp   = require 'mkdirp'

Future = require '../utils/Future'
rmrf   = require '../utils/rmrf'
sha1   = require '../utils/sha1'

browserInitGenerator     = require './browserInitGenerator'
CssOptimizer             = require './CssOptimizer'
JsOptimizer              = require './JsOptimizer'
requirejsConfig          = require './requirejsConfig'


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

    zDirFuture = (if @params.clean then rmrf(@_zDir) else Future.resolved()).flatMap =>
      Future.call(mkdirp, @_zDir)

    jsOptimizer  = new JsOptimizer(@params, zDirFuture)
    cssOptimizer = new CssOptimizer(@params, zDirFuture)
    jsOptimizer.run().zip(cssOptimizer.run()).flatMap (jsGroupMap, cssGroupMap) =>
      console.log "Generating browser-init script..."
      browserInitGenerator.generate(@params, jsGroupMap, cssGroupMap)
    .flatMap (browserInitScriptString) =>
      fileName = sha1(browserInitScriptString)
      Future.call(fs.writeFile, "#{@_zDir}/#{fileName}.js", browserInitScriptString)
        .zip(Future.call(fs.writeFile, "#{@_zDir}/browser-init.id", fileName))
    .done ->
      diff = process.hrtime(start)
      console.log "Optimization complete in #{ (diff[0] * 1e9 + diff[1]) / 1e6 } ms"



module.exports = Optimizer
