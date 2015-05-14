path = require('path')
Future = require('../../utils/Future')
BuildTask = require('./BuildTask')
requirejsConfig = require('./requirejs-config')


class CompileWidgetTemplate extends BuildTask

  run: ->
    src = "#{ @params.baseDir }/#{ @params.file }"

    requirejsConfig(@params.targetDir).flatMap ->
      Future.require('cord!compile/WidgetCompiler')
    .flatMap (WidgetCompiler) =>
      WidgetCompiler.compileWidgetTemplate(@_getWidgetCanonicalName(), src)
    .failAloud()
    .link(@readyPromise)


  _getWidgetCanonicalName: ->
    ###
    Builds and returns canonical name of the widget of the template file from the task params
    @return String
    ###
    name = @params.info.lastDirName 
    className = name.charAt(0).toUpperCase() + name.slice(1)
    parts = @params.file.split('/').slice(2, -2)
    parts.push(className)
    '/' + parts.join('/').replace('/widgets/', '//')



module.exports = CompileWidgetTemplate
