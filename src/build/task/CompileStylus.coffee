fs = require 'fs'
path = require 'path'

mkdirp = require 'mkdirp'
stylus = require 'stylus'

Future = require '../../utils/Future'

BuildTask = require './BuildTask'
coreUtils = require './coreUtils'
stylusUtils = require './stylusUtils'


replaceImportRe = /^@import ['"](.*\/\/.+)['"]$/gm


class CompileStylus extends BuildTask

  run: ->
    dirname = path.dirname(@params.file)
    basename = path.basename(@params.file, '.styl')

    src = "#{ @params.baseDir }/#{ @params.file }"
    dst = "#{ @params.targetDir }/#{ dirname }/#{ basename }.css"

    compilePromise = Future.call(fs.readFile, src, 'utf8').then (stylusStr) =>
      if @params.info.inCss
        # css folder in bundle root is handled differently using stylus preprocessing to resolve @import paths
        stylusUtils.preprocessBundleStylus(stylusStr, @params.file, @params.targetDir)
      else
        # old-widget's stylus handling
        pu = coreUtils.pathUtils(@params.targetDir)
        stylusStr.replace replaceImportRe, (match, p1) ->
          "@import '#{ pu.convertCssPath(p1, src) }'"
    .then (preprocessedStr) =>
      styl = stylus(preprocessedStr)
        .set('filename', src)
        .set('compress', true)
        # for new-style stylus preprocessing we need to import preprocessed stylus files from the target directory
        # instead of source stylus file from base directory
        .include(if @params.info.inCss then @params.targetDir else @params.baseDir)
        .use(stylusUtils.importStylusLibs)
      Future.call([styl, 'render'])

    Future.all [
      compilePromise
      Future.call(mkdirp, path.dirname(dst))
    ]
    .spread (cssStr) ->
      Future.call(fs.writeFile, dst, cssStr)
    .catch (err) ->
      if err.constructor.name == 'ParseError'
        console.error "Stylus ParseError:\n#{err.message}"
        throw new BuildTask.ExpectedError(err)
      else
        throw err
    .then -> return
    .link(@readyPromise)



module.exports = CompileStylus
